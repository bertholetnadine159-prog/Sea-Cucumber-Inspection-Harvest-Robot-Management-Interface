# ============================================================================
# [RDK X5 side] 摄像头采集 + BPU YOLO11 分割推理 + 标注渲染 + JPEG 编码
# 在 RDK X5 上完成 AI 检测，PC 只负责显示（不再在 PC 上跑 ONNX）。
# ============================================================================
from __future__ import annotations

import base64
import importlib.util
import logging
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import cv2
import numpy as np


LOGGER = logging.getLogger("rdkx5.vision")

COLORS_BGR = [
    (255, 200, 0), (128, 255, 0), (80, 80, 255), (255, 80, 80),
    (200, 0, 200), (220, 220, 0), (0, 200, 255), (100, 255, 100),
]


def probe_usb_capture_devices(max_devices: int = 8) -> list[str]:
    """探测可用的 USB/UVC 采集节点，跳过 metadata 节点。

    返回类似 ``["/dev/video0", "/dev/video2"]`` 的路径列表：每个物理 UVC 摄像头
    通常同时注册 capture 与 metadata 两个节点，只有真正能读到帧的才算采集节点。
    """
    found: list[str] = []
    for index in range(max_devices):
        path = Path(f"/dev/video{index}")
        if not path.exists():
            continue
        capture = cv2.VideoCapture(str(path), cv2.CAP_V4L2)
        try:
            ok = capture.isOpened() and capture.read()[0]
        except Exception:  # noqa: BLE001
            ok = False
        capture.release()
        if ok:
            found.append(str(path))
    return found


@dataclass
class Detection:
    class_id: int
    class_name: str
    score: float
    mask: np.ndarray | None = None
    bbox: tuple[int, int, int, int] | None = None

    def to_dict(self) -> dict[str, Any]:
        data: dict[str, Any] = {
            "class_id": self.class_id,
            "label": self.class_name,
            "confidence": self.score,
        }
        if self.bbox is not None:
            x1, y1, x2, y2 = self.bbox
            data.update({"x": x1, "y": y1, "width": x2 - x1, "height": y2 - y1})
        return data


@dataclass
class VideoFrame:
    jpeg: bytes
    width: int
    height: int
    camera_id: str = ""
    seq: int = 0
    ts: float = 0.0
    inference_ms: float = 0.0
    fps: float = 0.0
    detections: list[dict[str, Any]] = field(default_factory=list)

    def to_json(self) -> dict[str, Any]:
        return {
            "type": "frame",
            "seq": self.seq,
            "ts": self.ts,
            "camera_id": self.camera_id,
            "width": self.width,
            "height": self.height,
            "jpeg": base64.b64encode(self.jpeg).decode("ascii"),
            "detections": self.detections,
            "inference_ms": round(self.inference_ms, 1),
            "fps": round(self.fps, 1),
        }


class CameraSource:
    """单个摄像头：MIPI（srcampy/hobot_vio）或 USB（OpenCV V4L2）或仿真。"""

    def __init__(self, config: dict[str, Any], simulation: bool = False):
        self.config = config
        self.simulation = simulation
        self.source_type = str(config.get("source", "usb")).lower()
        self.width = int(config.get("width", 1280))
        self.height = int(config.get("height", 720))
        self.fps = int(config.get("fps", 15))
        self.device = config.get("device", config.get("camera_id", 0))
        self._cam = None
        self._cv_capture = None
        self._frame_index = 0
        self._mipi_read_error_logged = False

    def open(self) -> None:
        if self.simulation or self.source_type == "simulation":
            self.simulation = True
            return
        if self.source_type == "mipi":
            Camera = None
            try:
                from srcampy import Camera
            except Exception:
                try:
                    from hobot_vio import libsrcampy as srcampy_module
                    Camera = srcampy_module.Camera
                except Exception:
                    LOGGER.warning("[RDK X5] srcampy/hobot_vio unavailable, falling back to USB/OpenCV")
            if Camera is not None:
                camera_id = int(self.config.get("camera_id", 0))
                self._cam = Camera()
                # 官方示例用法：open_cam(pipe_id, video_index, fps, [w], [h])
                self._cam.open_cam(
                    0,
                    camera_id,
                    self.fps,
                    [self.width, self.width],
                    [self.height, self.height],
                )
                LOGGER.info("[RDK X5] MIPI camera opened id=%s", camera_id)
                return
            self.source_type = "usb"
        if self.source_type == "usb":
            if isinstance(self.device, int):
                self._cv_capture = cv2.VideoCapture(self.device)
            else:
                self._cv_capture = cv2.VideoCapture(str(self.device), cv2.CAP_V4L2)
            self._cv_capture.set(cv2.CAP_PROP_FRAME_WIDTH, self.width)
            self._cv_capture.set(cv2.CAP_PROP_FRAME_HEIGHT, self.height)
            self._cv_capture.set(cv2.CAP_PROP_FPS, self.fps)
            if not self._cv_capture.isOpened():
                raise RuntimeError(f"USB camera {self.device} failed to open")
            LOGGER.info("[RDK X5] USB camera opened device=%s", self.device)
            return
        raise ValueError(f"unsupported video source: {self.source_type}")

    def is_open(self) -> bool:
        if self.simulation:
            return True
        if self._cam is not None:
            return True
        return self._cv_capture is not None and self._cv_capture.isOpened()

    def read(self) -> np.ndarray | None:
        if self.simulation:
            return self._simulated_frame()
        if self._cam is not None:
            try:
                nv12 = self._cam.get_img(2, self.width, self.height)
                if nv12 is None:
                    if not self._mipi_read_error_logged:
                        LOGGER.warning("[RDK X5] MIPI get_img returned None (is the camera sensor connected?)")
                        self._mipi_read_error_logged = True
                    return None
                yuv = np.frombuffer(nv12, dtype=np.uint8).reshape(self.height * 3 // 2, self.width)
                bgr = cv2.cvtColor(yuv, cv2.COLOR_YUV2BGR_NV12)
                return bgr
            except Exception as exc:  # noqa: BLE001
                if not self._mipi_read_error_logged:
                    LOGGER.warning("[RDK X5] MIPI read failed: %s", exc)
                    self._mipi_read_error_logged = True
                return None
        if self._cv_capture is not None:
            ok, frame = self._cv_capture.read()
            return frame if ok else None
        return None

    def _simulated_frame(self) -> np.ndarray:
        self._frame_index += 1
        frame = np.zeros((self.height, self.width, 3), dtype=np.uint8)
        frame[:, :] = (72, 58, 38)
        offset = max(0, 160 - self._frame_index * 4)
        center = (self.width // 2 + offset, self.height // 2 + 40)
        cv2.ellipse(frame, center, (90, 45), 0, 0, 360, (180, 120, 28), -1)
        cv2.line(frame, (self.width // 2, 0), (self.width // 2, self.height), (130, 80, 80), 1)
        cv2.circle(frame, (self.width // 2, self.height // 2), 6, (220, 80, 80), -1)
        cv2.putText(frame, "RDK X5 SIM", (20, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
        return frame

    def close(self) -> None:
        if self._cam is not None:
            try:
                self._cam.close_cam()
            except Exception:
                pass
        if self._cv_capture is not None:
            self._cv_capture.release()
        self._cam = None
        self._cv_capture = None


class RDKSegmenter:
    """加载参考仓库转换好的 YOLO11 分割 BIN 模型，在 BPU 上推理。"""

    def __init__(self, config: dict[str, Any], base_dir: Path):
        self.class_names = list(config.get("class_names", ["sea_cucumber"]))
        script_path = Path(config.get("yolo_script", "./yolo11_seg_rdk.py"))
        if not script_path.is_absolute():
            script_path = base_dir / script_path
        if not script_path.exists():
            raise FileNotFoundError(f"[RDK X5] YOLO script not found: {script_path}")
        spec = importlib.util.spec_from_file_location("yolo11_seg_rdk_runtime", script_path)
        if spec is None or spec.loader is None:
            raise RuntimeError(f"[RDK X5] failed to load YOLO script: {script_path}")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        model_path = Path(config.get("model_path", "./YOLO11_LBL.bin"))
        if not model_path.is_absolute():
            model_path = base_dir / model_path
        self.model = module.YOLO11_Segment(
            str(model_path),
            float(config.get("confidence_threshold", 0.25)),
            float(config.get("iou_threshold", 0.45)),
            mask_thres=float(config.get("mask_threshold", 0.5)),
        )
        LOGGER.info("[RDK X5] BPU segmenter loaded: %s", model_path)

    def predict(self, frame: np.ndarray) -> list[Detection]:
        input_tensor = self.model.bgr2nv12(frame)
        outputs = self.model.c2numpy(self.model.forward(input_tensor))
        ids, scores, bboxes, masks = self.model.postProcess(outputs)
        detections: list[Detection] = []
        for class_id, score, bbox, mask in zip(ids, scores, bboxes, masks):
            class_index = int(class_id)
            name = self.class_names[class_index] if class_index < len(self.class_names) else str(class_index)
            box = tuple(int(v) for v in bbox[:4]) if len(bbox) >= 4 else None
            detections.append(Detection(class_index, name, float(score), mask.astype(np.uint8), box))
        return detections


def draw_detections(frame: np.ndarray, detections: list[Detection]) -> np.ndarray:
    annotated = frame.copy()
    height, width = frame.shape[:2]
    for index, detection in enumerate(detections):
        color = COLORS_BGR[index % len(COLORS_BGR)]
        if detection.mask is not None:
            mask_rs = cv2.resize(detection.mask.astype(np.float32), (width, height), interpolation=cv2.INTER_NEAREST)
            binary = (mask_rs > 0.5).astype(np.uint8)
            overlay = np.zeros_like(annotated, dtype=np.uint8)
            overlay[binary == 1] = color
            annotated = cv2.addWeighted(annotated, 1.0, overlay, 0.45, 0)
            contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            cv2.drawContours(annotated, contours, -1, color, 2)
        if detection.bbox is not None:
            x1, y1, x2, y2 = detection.bbox
            cv2.rectangle(annotated, (x1, y1), (x2, y2), color, 2)
        label = f"{detection.class_name} {detection.score:.2f}"
        font, fs, thick = cv2.FONT_HERSHEY_SIMPLEX, 0.55, 1
        (lw, lh), _ = cv2.getTextSize(label, font, fs, thick)
        ty = max(0, (detection.bbox[1] if detection.bbox else 0) - lh - 6)
        tx = detection.bbox[0] if detection.bbox else 0
        cv2.rectangle(annotated, (tx, ty), (tx + lw + 6, ty + lh + 4), color, -1)
        cv2.putText(annotated, label, (tx + 3, ty + lh), font, fs, (0, 0, 0), thick, cv2.LINE_AA)
    return annotated


class VideoPipeline:
    """多摄像头采集 -> 推理 -> 标注 -> JPEG 编码，独立线程。

    对齐机器人仓库的双摄流程：camera_1 前视检测、camera_2 吸口近距对准。
    同一时间只打开一路以节省 USB 带宽；通过 set_camera() 切换活动摄像头。
    """

    def __init__(self, config: dict[str, Any], base_dir: Path, simulation: bool = False):
        self.config = config
        self.base_dir = base_dir
        self.simulation = simulation
        self.cameras: dict[str, CameraSource] = {}
        self.active_camera_id: str | None = None
        self._camera_lock = threading.Lock()
        # 仿真模式不加载 BPU 模型；实机模型/脚本缺失时降级为无检测，仍推送原视频
        self.segmenter = None
        if config.get("enabled", True) and not simulation:
            try:
                self.segmenter = RDKSegmenter(config, base_dir)
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("[RDK X5] segmenter init failed (video will stream without detections): %s", exc)
        self.jpeg_quality = int(config.get("jpeg_quality", 78))
        self._latest: VideoFrame | None = None
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._seq = 0
        self._fps_ema = 0.0

    def start(self) -> None:
        try:
            self._build_cameras()
            self._activate(self._default_camera_id())
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("[RDK X5] camera start failed (telemetry stays available): %s", exc)
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def camera_ids(self) -> list[str]:
        with self._camera_lock:
            return list(self.cameras.keys())

    def _build_cameras(self) -> None:
        cameras_cfg = self.config.get("cameras")
        if not cameras_cfg:
            # 兼容旧的单摄像头配置（video.source: mipi | usb | simulation）
            cameras_cfg = {
                "camera_1": {
                    **{
                        key: value
                        for key, value in self.config.items()
                        # enabled 在旧配置里表示“是否启用视觉推理”，不是摄像头开关
                        if key not in ("cameras", "active_camera", "enabled")
                    },
                    "enabled": True,
                    "default_open": True,
                    "device": self.config.get("device", self.config.get("camera_id", 0)),
                    "source": self.config.get("source", "usb"),
                }
            }
        auto_devices: list[str] | None = None
        for key, raw in cameras_cfg.items():
            if not isinstance(raw, dict) or not raw.get("enabled", True):
                continue
            cfg = dict(raw)
            cfg.setdefault("width", 1280)
            cfg.setdefault("height", 720)
            cfg.setdefault("fps", 15)
            if str(cfg.get("device", "auto")).lower() in ("auto", "auto_usb"):
                if auto_devices is None:
                    auto_devices = probe_usb_capture_devices() if not self.simulation else ["simulation"]
                cfg["device"] = auto_devices.pop(0) if auto_devices else 0
            cfg["source"] = "simulation" if self.simulation else str(cfg.get("source", "usb")).lower()
            self.cameras[key] = CameraSource(cfg, self.simulation)

    def _default_camera_id(self) -> str:
        configured = str(self.config.get("active_camera", "camera_1"))
        if configured in self.cameras:
            return configured
        for key, camera in self.cameras.items():
            if camera.config.get("default_open", False):
                return key
        return next(iter(self.cameras), "")

    def _close_all_locked(self, exclude: str | None = None) -> None:
        for key, camera in self.cameras.items():
            if key != exclude:
                camera.close()

    def _activate(self, camera_id: str) -> None:
        with self._camera_lock:
            if camera_id not in self.cameras:
                raise ValueError(f"unknown camera: {camera_id} (available: {list(self.cameras)})")
            camera = self.cameras[camera_id]
            if not camera.is_open():
                camera.open()
            if not camera.is_open():
                raise RuntimeError(f"camera {camera_id} failed to open")
            self._close_all_locked(exclude=camera_id)
            self.active_camera_id = camera_id
            LOGGER.info("[RDK X5] active camera -> %s (device=%s)", camera_id, camera.device)

    def set_camera(self, camera_id: str) -> None:
        """切换活动摄像头：camera_1（前视）/ camera_2（吸口近距）。"""
        self._activate(str(camera_id))

    def active_camera(self) -> CameraSource | None:
        with self._camera_lock:
            return self.cameras.get(self.active_camera_id or "")

    def set_quality(self, width: int, height: int, fps: int, jpeg_quality: int) -> None:
        self.jpeg_quality = max(30, min(95, int(jpeg_quality)))

    def _run(self) -> None:
        interval = 1.0 / 15.0
        last_t = time.monotonic()
        while not self._stop.wait(interval):
            camera = self.active_camera()
            if camera is None:
                continue
            interval = 1.0 / max(1, camera.fps)
            frame = camera.read()
            if frame is None:
                continue
            inference_ms = 0.0
            detections: list[Detection] = []
            if self.segmenter is not None:
                t0 = time.monotonic()
                try:
                    detections = self.segmenter.predict(frame)
                except Exception as exc:  # noqa: BLE001
                    LOGGER.warning("[RDK X5] BPU inference failed: %s", exc)
                inference_ms = (time.monotonic() - t0) * 1000.0
            annotated = draw_detections(frame, detections) if detections else frame
            ok, buf = cv2.imencode(".jpg", annotated, [cv2.IMWRITE_JPEG_QUALITY, self.jpeg_quality])
            if not ok:
                continue
            now = time.monotonic()
            elapsed = now - last_t
            last_t = now
            if elapsed > 0:
                self._fps_ema = self._fps_ema * 0.9 + (1.0 / elapsed) * 0.1
            self._seq += 1
            with self._lock:
                self._latest = VideoFrame(
                    jpeg=buf.tobytes(),
                    width=frame.shape[1],
                    height=frame.shape[0],
                    camera_id=self.active_camera_id or "",
                    seq=self._seq,
                    ts=time.time(),
                    inference_ms=inference_ms,
                    fps=self._fps_ema,
                    detections=[d.to_dict() for d in detections],
                )

    def latest(self) -> VideoFrame | None:
        with self._lock:
            return self._latest

    def stop(self) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=3.0)
        with self._camera_lock:
            self._close_all_locked()
