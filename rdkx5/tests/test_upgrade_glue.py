#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Wave 3 测试补全（rdkx5）：set_video 跨摄像头 _override_params 重放 + fetch_snapshot 大文件完整性。

覆盖（契约 docs/UPGRADE_CONTRACTS.md §5）：
  1. set_video 热更新参数记忆 _override_params：
     - 反复切换摄像头（camera_2 → camera_1 → camera_2）每次激活都重放参数；
     - 越界拒绝不得污染已记忆的 _override_params 与 jpeg_quality；
     - 切换后产出的新帧分辨率/摄像头归属真实匹配（端到端验证而非仅查配置）。
  2. fetch_snapshot 对 >1MB 大图的 base64 完整性：
     - size 与原文件一致、base64 解码后字节级一致、SOI/EOI 标记完整；
     - ack 经 json 序列化（WS 传输路径）后解码仍与原文件一致（不截断不变形）；
     - list_snapshots 如实上报大文件尺寸。

运行：cd rdkx5 && python -m unittest discover -s tests
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
from stream_server import CommandHandler
from vision import VideoPipeline


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


def _wait_for_camera_frame(pipeline: VideoPipeline, camera_id: str, min_seq: int, timeout: float = 5.0):
    """轮询等待指定摄像头产出的新帧（切换后的首帧可能仍是旧画面，需按归属过滤）。"""
    deadline = time.time() + timeout
    frame = None
    while time.time() < deadline:
        frame = pipeline.latest()
        if frame is not None and frame.camera_id == camera_id and frame.seq > min_seq and frame.jpeg:
            break
        time.sleep(0.02)
    return frame


class SetVideoOverrideReplayTest(unittest.TestCase):
    """set_video 的 _override_params 跨摄像头重放行为（契约 §5 热更新全链路）。"""

    def _build(self) -> VideoPipeline:
        # camera_1/camera_2 原始分辨率刻意不同：验证重放后都被统一覆盖为 set_video 值
        config = {
            "enabled": False,  # 仿真不加载 BPU 模型
            "jpeg_quality": 78,
            "cameras": {
                "camera_1": {"source": "simulation", "width": 320, "height": 240, "fps": 15},
                "camera_2": {"source": "simulation", "width": 1280, "height": 720, "fps": 30},
            },
        }
        return VideoPipeline(config, Path("."), simulation=True)

    def test_override_replayed_on_every_camera_activation(self) -> None:
        """反复切换摄像头，每次激活都重放 _override_params（而非仅首次生效）。"""
        pipeline = self._build()
        pipeline.start()
        try:
            ok, message = pipeline.set_video(480, 360, 10, 60)
            self.assertTrue(ok, message)
            self.assertEqual(pipeline._override_params, (480, 360, 10))
            self.assertEqual(pipeline.jpeg_quality, 60)

            # camera_2 → camera_1 → camera_2：camera_1 原始 320x240@15、
            # camera_2 原始 1280x720@30，重放后必须都变成 480x360@10
            for camera_id in ("camera_2", "camera_1", "camera_2"):
                pipeline.set_camera(camera_id)
                camera = pipeline.active_camera()
                self.assertEqual(pipeline.active_camera_id, camera_id)
                self.assertIsNotNone(camera)
                self.assertEqual(
                    (camera.width, camera.height, camera.fps), (480, 360, 10),
                    f"切换到 {camera_id} 后必须重放 set_video 热更新参数",
                )
        finally:
            pipeline.stop()

    def test_rejected_set_video_keeps_override(self) -> None:
        """越界拒绝：不得污染已记忆的 _override_params 与 jpeg_quality。"""
        pipeline = self._build()
        pipeline.start()
        try:
            self.assertTrue(pipeline.set_video(480, 360, 10, 60)[0])
            before = pipeline._override_params

            # 宽度越界（>1920）→ 拒绝
            ok, message = pipeline.set_video(4000, 360, 10, 60)
            self.assertFalse(ok)
            self.assertTrue(message)
            self.assertEqual(pipeline._override_params, before)
            self.assertEqual(pipeline.jpeg_quality, 60)

            # 拒绝后再切换摄像头：重放的仍然是上次成功应用的参数
            pipeline.set_camera("camera_2")
            camera = pipeline.active_camera()
            self.assertEqual((camera.width, camera.height, camera.fps), (480, 360, 10))
        finally:
            pipeline.stop()

    def test_new_frames_match_overridden_size_after_switch(self) -> None:
        """切换后实际产出的新帧分辨率/摄像头归属真实匹配（端到端验证）。"""
        pipeline = self._build()
        pipeline.start()
        try:
            first = _wait_for_frame(pipeline)
            self.assertIsNotNone(first)

            ok, _ = pipeline.set_video(480, 360, 10, 60)
            self.assertTrue(ok)
            pipeline.set_camera("camera_2")

            frame = _wait_for_camera_frame(pipeline, "camera_2", min_seq=first.seq)
            self.assertIsNotNone(frame, "切换摄像头后未等到 camera_2 的新帧")
            self.assertEqual((frame.width, frame.height), (480, 360))
            self.assertEqual(frame.camera_id, "camera_2")
            self.assertTrue(frame.jpeg.startswith(b"\xff\xd8"))  # JPEG SOI
        finally:
            pipeline.stop()


class _NullVideo:
    """占位视频源：fetch_snapshot/list_snapshots 不触碰视频通路。"""


class FetchSnapshotLargeFileTest(unittest.TestCase):
    """fetch_snapshot 对 >1MB 大图的 base64 完整性（契约 §5）。"""

    @classmethod
    def setUpClass(cls) -> None:
        cls.base = Path(tempfile.mkdtemp(prefix="seaui_glue_snap_"))
        cls.snaps = cls.base / "snapshots"
        cls.snaps.mkdir()
        # 随机噪声图：JPEG 几乎不可压缩，任何截断/损坏都会在字节对比中暴露
        rng = np.random.default_rng(20260919)
        noise = rng.integers(0, 256, size=(1600, 2000, 3), dtype=np.uint8)
        ok, buf = cv2.imencode(".jpg", noise, [cv2.IMWRITE_JPEG_QUALITY, 98])
        assert ok, "噪声 JPEG 编码失败"
        cls.jpeg_bytes = buf.tobytes()

        # 测试前提：确实生成了 >1MB 的 jpg（任务要求的"大文件"量级）
        assert len(cls.jpeg_bytes) > 1024 * 1024, (
            f"noise jpg too small: {len(cls.jpeg_bytes)} bytes"
        )
        (cls.snaps / "rdk_big.jpg").write_bytes(cls.jpeg_bytes)

        cls.handler = CommandHandler(
            SimulatedPixhawk(), _NullVideo(), [9, 10], 11, [], {},
            snapshot_dir=cls.snaps,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.base, ignore_errors=True)

    def _fetch(self, name: str = "rdk_big.jpg") -> dict:
        return asyncio.run(self.handler.handle({
            "type": "command",
            "command": "fetch_snapshot",
            "params": {"name": name},
        }))

    def test_large_snapshot_base64_roundtrip_is_byte_exact(self) -> None:
        """base64 解码后与原文件字节级一致，SOI/EOI 标记完整。"""
        ack = self._fetch()
        self.assertTrue(ack["success"])
        self.assertTrue(ack["ok"])
        self.assertEqual(ack["name"], "rdk_big.jpg")
        self.assertEqual(ack["size"], len(self.jpeg_bytes))

        decoded = base64.b64decode(ack["jpeg"])
        self.assertEqual(len(decoded), len(self.jpeg_bytes))
        self.assertEqual(decoded, self.jpeg_bytes)  # 字节级一致（大文件不截断）
        self.assertTrue(decoded.startswith(b"\xff\xd8"))  # SOI
        self.assertTrue(decoded.endswith(b"\xff\xd9"))  # EOI

    def test_large_snapshot_survives_json_serialization(self) -> None:
        """ack 经 json 序列化（WS 实际传输路径）后载荷不变形。"""
        ack = self._fetch()
        wire = json.dumps(ack, ensure_ascii=False)
        # base64 膨胀后报文必然大于原始文件（完整性前提）
        self.assertGreater(len(wire), len(self.jpeg_bytes))
        reparsed = json.loads(wire)
        self.assertEqual(reparsed["size"], len(self.jpeg_bytes))
        self.assertEqual(base64.b64decode(reparsed["jpeg"]), self.jpeg_bytes)

    def test_list_snapshots_reports_large_size(self) -> None:
        """list_snapshots 如实上报大文件尺寸与时间戳。"""
        ack = asyncio.run(self.handler.handle({
            "type": "command",
            "command": "list_snapshots",
        }))
        self.assertTrue(ack["success"])
        item = next(
            (entry for entry in ack["snapshots"] if entry["name"] == "rdk_big.jpg"),
            None,
        )
        self.assertIsNotNone(item)
        self.assertEqual(item["size"], len(self.jpeg_bytes))
        self.assertGreater(item["ts"], 0)


if __name__ == "__main__":
    unittest.main()
