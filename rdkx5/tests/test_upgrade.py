#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""[RDK X5 side] 商用化升级 Wave 1 单元测试（PC 上无需硬件即可运行）。

覆盖：
- validate_video_params：set_video 参数范围/偶数校验；
- set_video 热生效：仿真管线（有/无 BPU 模型两条路径）宽/高/帧率/质量真实应用，
  越界拒绝且不应用，切换摄像头后仍然生效；
- stream_server 的 set_video ack：成功/失败/非法参数三种返回；
- frame 消息 sent_ts：存在、float、>= 采集时刻 ts、随 seq 单调；
- list_snapshots / fetch_snapshot：正常列表、base64 内容、路径穿越拒绝、文件不存在；
- 推送循环端到端：frame 带 sent_ts，telemetry 带 pixhawk 全字段。

运行：cd rdkx5 && python -m unittest discover -s tests -v
"""

import asyncio
import base64
import json
import shutil
import tempfile
import time
import unittest
from pathlib import Path

import cv2
import numpy as np

from pixhawk_link import SimulatedPixhawk
from stream_server import CommandHandler, StreamServer
from vision import VideoFrame, VideoPipeline, validate_video_params


def _make_jpeg(width: int = 8, height: int = 8) -> bytes:
    """生成一张最小 JPEG（带 SOI 头），用于快照与帧内容断言。"""
    ok, buf = cv2.imencode(".jpg", np.zeros((height, width, 3), dtype=np.uint8))
    assert ok
    return buf.tobytes()


def _wait_for_frame(pipeline: VideoPipeline, min_seq: int = 0, timeout: float = 3.0):
    """轮询等待管线产出 seq > min_seq 的新帧，超时返回 None。"""
    deadline = time.time() + timeout
    frame = None
    while time.time() < deadline:
        frame = pipeline.latest()
        if frame is not None and frame.seq > min_seq and frame.jpeg:
            break
        time.sleep(0.02)
    return frame


class VideoParamValidationTest(unittest.TestCase):
    """set_video 参数范围校验（宽高 320-1920 且偶数、fps 1-30、quality 30-95）。"""

    def test_valid_boundary_values(self) -> None:
        ok, _ = validate_video_params(320, 320, 1, 30)
        self.assertTrue(ok)
        ok, _ = validate_video_params(1920, 1080, 30, 95)
        self.assertTrue(ok)

    def test_rejects_odd_or_out_of_range_size(self) -> None:
        for width, height in ((321, 240), (640, 241), (319, 240), (640, 319),
                              (1921, 240), (640, 1921), (0, 0)):
            ok, message = validate_video_params(width, height, 15, 78)
            self.assertFalse(ok, f"should reject {width}x{height}")
            self.assertTrue(message)

    def test_rejects_out_of_range_fps_and_quality(self) -> None:
        self.assertFalse(validate_video_params(640, 480, 0, 78)[0])
        self.assertFalse(validate_video_params(640, 480, 31, 78)[0])
        self.assertFalse(validate_video_params(640, 480, 15, 29)[0])
        self.assertFalse(validate_video_params(640, 480, 15, 96)[0])


class SetVideoSimulationTest(unittest.TestCase):
    """set_video 在仿真管线上的热生效（无 BPU 模型路径）。"""

    def _build(self) -> VideoPipeline:
        config = {
            "source": "simulation",
            "width": 320,
            "height": 240,
            "fps": 30,
            "jpeg_quality": 78,
            "enabled": False,  # 仿真不加载 BPU 模型
        }
        return VideoPipeline(config, Path("."), simulation=True)

    def test_set_video_rejects_out_of_range_without_apply(self) -> None:
        pipeline = self._build()
        pipeline.start()
        try:
            self.assertIsNotNone(_wait_for_frame(pipeline))
            camera = pipeline.active_camera()
            for width, height, fps, quality in (
                (4000, 240, 15, 78),   # 宽越界
                (320, 240, 15, 96),    # 质量越界
                (320, 240, 0, 78),     # 帧率越界
                (321, 240, 15, 78),    # 非偶数
            ):
                ok, message = pipeline.set_video(width, height, fps, quality)
                self.assertFalse(ok)
                self.assertTrue(message)
            # 拒绝后原参数保持不变
            self.assertEqual(pipeline.jpeg_quality, 78)
            self.assertEqual((camera.width, camera.height, camera.fps), (320, 240, 30))
        finally:
            pipeline.stop()

    def test_set_video_hot_applies_to_pipeline(self) -> None:
        pipeline = self._build()
        pipeline.start()
        try:
            first = _wait_for_frame(pipeline)
            self.assertIsNotNone(first)
            ok, message = pipeline.set_video(480, 360, 10, 60)
            self.assertTrue(ok, message)
            self.assertEqual(pipeline.jpeg_quality, 60)
            camera = pipeline.active_camera()
            self.assertEqual((camera.width, camera.height, camera.fps), (480, 360, 10))
            # 等待新帧：取帧循环每轮按 camera.fps 重算间隔，新参数立即生效
            second = _wait_for_frame(pipeline, min_seq=first.seq)
            self.assertIsNotNone(second)
            self.assertEqual((second.width, second.height), (480, 360))
        finally:
            pipeline.stop()

    def test_set_video_persists_across_camera_switch(self) -> None:
        config = {
            "enabled": False,
            "jpeg_quality": 78,
            "cameras": {
                "camera_1": {"source": "simulation", "width": 320, "height": 240, "fps": 15},
                "camera_2": {"source": "simulation", "width": 320, "height": 240, "fps": 15},
            },
        }
        pipeline = VideoPipeline(config, Path("."), simulation=True)
        pipeline.start()
        try:
            ok, _ = pipeline.set_video(480, 360, 10, 60)
            self.assertTrue(ok)
            pipeline.set_camera("camera_2")
            camera = pipeline.active_camera()
            self.assertEqual(pipeline.active_camera_id, "camera_2")
            # 热更新参数对切换后的摄像头同样生效
            self.assertEqual((camera.width, camera.height, camera.fps), (480, 360, 10))
        finally:
            pipeline.stop()


class SetVideoNoModelFallbackTest(unittest.TestCase):
    """set_video 在"模型缺失→回退原始帧"路径上同样生效（实机降级场景）。"""

    def test_set_video_applies_when_segmenter_missing(self) -> None:
        config = {
            "source": "simulation",
            "width": 320,
            "height": 240,
            "fps": 30,
            "jpeg_quality": 80,
            "enabled": True,  # 尝试加载模型
            "model_path": "./does_not_exist.bin",
            "yolo_script": "./does_not_exist.py",
        }
        pipeline = VideoPipeline(config, Path("."), simulation=False)
        self.assertIsNone(pipeline.segmenter)  # 模型缺失，降级为无检测推流
        pipeline.start()
        try:
            first = _wait_for_frame(pipeline)
            self.assertIsNotNone(first)
            ok, _ = pipeline.set_video(480, 360, 10, 65)
            self.assertTrue(ok)
            second = _wait_for_frame(pipeline, min_seq=first.seq)
            self.assertIsNotNone(second)
            self.assertEqual((second.width, second.height), (480, 360))
        finally:
            pipeline.stop()


class SetVideoHandlerAckTest(unittest.TestCase):
    """stream_server 对 set_video 的 ack：成功/越界/非法参数。"""

    def setUp(self) -> None:
        config = {
            "source": "simulation",
            "width": 320,
            "height": 240,
            "fps": 15,
            "jpeg_quality": 78,
            "enabled": False,
        }
        self.pipeline = VideoPipeline(config, Path("."), simulation=True)
        self.pipeline.start()
        self.handler = CommandHandler(
            SimulatedPixhawk(), self.pipeline, [9, 10], 11, [], {"deadman_ms": 1000},
        )

    def tearDown(self) -> None:
        self.pipeline.stop()

    def test_success_ack_carries_applied_params(self) -> None:
        ack = asyncio.run(self.handler.handle({
            "type": "set_video",
            "params": {"width": 1280, "height": 720, "fps": 15, "jpeg_quality": 90},
        }))
        self.assertEqual(ack["command"], "set_video")
        self.assertTrue(ack["success"])
        self.assertEqual(
            (ack["width"], ack["height"], ack["fps"], ack["jpeg_quality"]),
            (1280, 720, 15, 90),
        )
        self.assertEqual(self.pipeline.jpeg_quality, 90)

    def test_out_of_range_returns_failure_ack(self) -> None:
        before = self.pipeline.jpeg_quality
        ack = asyncio.run(self.handler.handle({
            "type": "set_video",
            "params": {"width": 5000, "height": 720, "fps": 15, "jpeg_quality": 90},
        }))
        self.assertEqual(ack["command"], "set_video")
        self.assertFalse(ack["success"])  # 越界回失败 ack（400 语义）
        self.assertIn("width", ack.get("message", ""))
        self.assertNotIn("width", ack)  # 失败时不回带应用参数
        self.assertEqual(self.pipeline.jpeg_quality, before)  # 未应用

    def test_non_numeric_params_rejected(self) -> None:
        ack = asyncio.run(self.handler.handle({
            "type": "set_video",
            "params": {"width": "abc"},
        }))
        self.assertFalse(ack["success"])
        self.assertIn("invalid", ack.get("message", ""))


class FrameSentTsTest(unittest.TestCase):
    """frame 消息 sent_ts：存在、float、>= ts、随 seq 单调。"""

    def test_to_json_sent_ts_present_and_monotonic(self) -> None:
        config = {
            "source": "simulation",
            "width": 320,
            "height": 240,
            "fps": 30,
            "jpeg_quality": 78,
            "enabled": False,
        }
        pipeline = VideoPipeline(config, Path("."), simulation=True)
        pipeline.start()
        try:
            deadline = time.time() + 3.0
            messages: list[dict] = []
            seen: set[int] = set()
            while time.time() < deadline and len(messages) < 5:
                frame = pipeline.latest()
                if frame is None or frame.seq in seen or not frame.jpeg:
                    time.sleep(0.01)
                    continue
                seen.add(frame.seq)
                messages.append(frame.to_json())
            self.assertGreaterEqual(len(messages), 2)
            previous_sent = 0.0
            for message in messages:
                self.assertIn("sent_ts", message)
                self.assertIsInstance(message["sent_ts"], float)
                # ts=采集时刻 不晚于 sent_ts=发送时刻（同一时钟源）
                self.assertLessEqual(message["ts"], message["sent_ts"] + 1e-6)
                self.assertGreater(message["sent_ts"], 1.0e9)  # epoch 秒量级
            for message in messages:  # 按 seq 顺序单调不减
                self.assertGreaterEqual(message["sent_ts"], previous_sent)
                previous_sent = message["sent_ts"]
        finally:
            pipeline.stop()


class _FakeWebsocket:
    """极简 websocket 替身：只记录 send 的原文。"""

    def __init__(self) -> None:
        self.messages: list[str] = []

    async def send(self, raw: str) -> None:
        self.messages.append(raw)


class _FakeVideo:
    """顺序吐出预置帧的视频源替身（供推送循环测试）。"""

    def __init__(self, frames: list[VideoFrame]) -> None:
        self._frames = frames
        self._index = 0

    def latest(self):
        if self._index < len(self._frames):
            frame = self._frames[self._index]
            self._index += 1
            return frame
        return self._frames[-1] if self._frames else None

    def camera_ids(self):
        return ["camera_1"]


class _FakeSensorHub:
    def latest(self):
        return {}


class PushLoopSentTsTest(unittest.TestCase):
    """推送循环端到端：frame 带 sent_ts，telemetry 带 pixhawk 全字段。"""

    def test_push_loop_frames_and_telemetry(self) -> None:
        frames = [
            VideoFrame(
                jpeg=_make_jpeg(),
                width=8,
                height=8,
                camera_id="camera_1",
                seq=index + 1,
                ts=time.time(),
                fps=15.0,
            )
            for index in range(3)
        ]
        server = StreamServer(
            "127.0.0.1", 0,
            video=_FakeVideo(frames),
            sensor_hub=_FakeSensorHub(),
            pixhawk=SimulatedPixhawk(),
            handler=None,
            telemetry_hz=20,
        )

        async def collect() -> list[str]:
            websocket = _FakeWebsocket()
            task = asyncio.create_task(server._push_loop(websocket))
            await asyncio.sleep(0.4)
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
            return websocket.messages

        messages = [json.loads(raw) for raw in asyncio.run(collect())]
        frame_messages = [m for m in messages if m.get("type") == "frame"]
        telemetry_messages = [m for m in messages if m.get("type") == "telemetry"]
        self.assertGreaterEqual(len(frame_messages), 2)
        previous_sent = 0.0
        for message in sorted(frame_messages, key=lambda m: m["seq"]):
            self.assertIn("sent_ts", message)
            self.assertIsInstance(message["sent_ts"], float)
            self.assertGreaterEqual(message["sent_ts"], previous_sent)
            previous_sent = message["sent_ts"]
        self.assertGreaterEqual(len(telemetry_messages), 1)
        pixhawk = telemetry_messages[0]["pixhawk"]
        # pixhawk 全字段（契约 §5/§7：motors_pwm/aux_pwm/vcc_v/vservo_v/sensors_health）
        for field in ("connected", "armed", "mode", "battery_v", "battery_remaining",
                      "attitude_deg", "alt_m", "motors_pwm", "aux_pwm",
                      "vcc_v", "vservo_v", "sensors_health"):
            self.assertIn(field, pixhawk)
        self.assertIsInstance(pixhawk["motors_pwm"], list)
        self.assertIsInstance(pixhawk["aux_pwm"], list)


class _StaticVideo:
    """固定返回一帧的视频源替身（供快照保存命令测试）。"""

    def __init__(self) -> None:
        self.jpeg_quality = 78

    def latest(self):
        return VideoFrame(
            jpeg=_make_jpeg(), width=8, height=8,
            camera_id="camera_1", seq=1, ts=time.time(), fps=15.0,
        )

    def camera_ids(self):
        return ["camera_1"]

    def set_video(self, width: int, height: int, fps: int, jpeg_quality: int):
        self.jpeg_quality = jpeg_quality
        return True, "ok"


class SnapshotCommandsTest(unittest.TestCase):
    """list_snapshots / fetch_snapshot：正常流程 + 安全拒绝。"""

    def setUp(self) -> None:
        self.base = Path(tempfile.mkdtemp(prefix="seaui_snap_test_"))
        self.snaps = self.base / "snapshots"
        self.snaps.mkdir()
        (self.snaps / "rdk_1.jpg").write_bytes(_make_jpeg())
        (self.snaps / "rdk_2.jpg").write_bytes(_make_jpeg(16, 16))
        (self.snaps / "notes.txt").write_text("not an image", encoding="utf-8")
        (self.base / "secret.jpg").write_bytes(b"SECRET")  # 目录外的敏感文件
        self.handler = CommandHandler(
            SimulatedPixhawk(), _StaticVideo(), [9, 10], 11, [], {},
            snapshot_dir=self.snaps,
        )

    def tearDown(self) -> None:
        shutil.rmtree(self.base, ignore_errors=True)

    def _run(self, command: str, params: dict | None = None) -> dict:
        return asyncio.run(self.handler.handle({
            "type": "command",
            "command": command,
            "params": params or {},
        }))

    def test_list_snapshots_returns_jpg_only(self) -> None:
        ack = self._run("list_snapshots")
        self.assertTrue(ack["success"])
        self.assertTrue(ack["ok"])
        names = [item["name"] for item in ack["snapshots"]]
        self.assertEqual(names, ["rdk_1.jpg", "rdk_2.jpg"])  # notes.txt 不列出
        for item in ack["snapshots"]:
            self.assertGreater(item["size"], 0)
            self.assertGreater(item["ts"], 0)

    def test_fetch_snapshot_returns_base64_jpeg(self) -> None:
        ack = self._run("fetch_snapshot", {"name": "rdk_1.jpg"})
        self.assertTrue(ack["success"])
        self.assertTrue(ack["ok"])
        self.assertEqual(ack["name"], "rdk_1.jpg")
        data = base64.b64decode(ack["jpeg"])
        self.assertTrue(data.startswith(b"\xff\xd8"))  # JPEG SOI
        self.assertEqual(ack["size"], len(data))

    def test_fetch_snapshot_missing_file_fails(self) -> None:
        ack = self._run("fetch_snapshot", {"name": "rdk_missing.jpg"})
        self.assertFalse(ack["success"])
        self.assertIn("not found", ack.get("message", ""))

    def test_fetch_snapshot_rejects_path_traversal(self) -> None:
        for bad_name in ("../secret.jpg", "..\\secret.jpg",
                         "sub/../../secret.jpg", "..", "a/b.jpg"):
            ack = self._run("fetch_snapshot", {"name": bad_name})
            self.assertFalse(ack["success"], bad_name)
            self.assertNotIn("jpeg", ack)  # 决不能返回目录外内容
            self.assertNotIn(base64.b64encode(b"SECRET").decode("ascii"),
                             json.dumps(ack))

    def test_fetch_snapshot_rejects_non_jpg(self) -> None:
        ack = self._run("fetch_snapshot", {"name": "notes.txt"})
        self.assertFalse(ack["success"])

    def test_snapshot_command_saves_into_snapshot_dir(self) -> None:
        ack = self._run("snapshot")
        self.assertTrue(ack["success"])
        saved = Path(ack["path"])
        self.assertEqual(saved.parent, self.snaps)
        self.assertTrue(saved.name.startswith("rdk_"))
        self.assertTrue(saved.read_bytes().startswith(b"\xff\xd8"))
        listing = self._run("list_snapshots")
        self.assertIn(saved.name, [item["name"] for item in listing["snapshots"]])


if __name__ == "__main__":
    unittest.main()
