#!/usr/bin/env python3

import sys
import os
import asyncio
import json
import base64
import time
import warnings
import threading
from pathlib import Path

import cv2
import numpy as np

warnings.filterwarnings("ignore")

from ultralytics import YOLO

# =========================================================
#  配置
# =========================================================
BASE_DIR = Path(__file__).resolve().parents[1]

VIDEO_SOURCE = os.getenv("ROV_VIDEO_SOURCE") or os.getenv("ROV_VIDEO_PATH") or "0"
MODEL_PATH = os.getenv("ROV_MODEL_PATH", str(BASE_DIR / "best.onnx"))
WS_HOST = os.getenv("ROV_WS_HOST", "localhost")
WS_PORT = int(os.getenv("ROV_WS_PORT", "8765"))
CONF_THRESH = float(os.getenv("ROV_CONF_THRESH", "0.25"))
JPEG_QUAL = int(os.getenv("ROV_JPEG_QUAL", "80"))   # WebSocket传输画质

# 实例颜色池 BGR
COLORS = [
    (0, 200, 255), (0, 255, 128), (255,  80,  80), ( 80,  80, 255),
    (200,   0, 200), (0, 220, 220), (255, 200,   0), (100, 255, 100),
]

# =========================================================
#  全局共享: 最新标注帧
# =========================================================
latest_frame_bytes: bytes = b""
frame_lock = threading.Lock()


# =========================================================
#  YOLO 实例分割 + cv2 绘制
# =========================================================
def draw_seg(frame: np.ndarray, result) -> np.ndarray:
    """在frame上用cv2手动绘制实例分割结果，返回标注后的图像"""
    annotated = frame.copy()
    h, w = frame.shape[:2]
    boxes = result.boxes
    masks = result.masks  # None 若未检出

    for idx, box in enumerate(boxes):
        cls_id = int(box.cls[0])
        conf   = float(box.conf[0])
        x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
        color = COLORS[idx % len(COLORS)]

        # 1) 半透明分割mask
        if masks is not None:
            mask_np = masks.data[idx].cpu().numpy()          # (Hm, Wm) float32
            mask_rs = cv2.resize(mask_np, (w, h), interpolation=cv2.INTER_NEAREST)
            bm = (mask_rs > 0.5).astype(np.uint8)
            overlay = np.zeros_like(annotated, dtype=np.uint8)
            overlay[bm == 1] = color
            annotated = cv2.addWeighted(annotated, 1.0, overlay, 0.45, 0)
            # 轮廓线
            contours, _ = cv2.findContours(bm, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            cv2.drawContours(annotated, contours, -1, color, 2)

        # 2) 边界框
        cv2.rectangle(annotated, (x1, y1), (x2, y2), color, 2)

        # 3) 标签
        label = f"{result.names[cls_id]} {conf:.2f}"
        font, fs, thick = cv2.FONT_HERSHEY_SIMPLEX, 0.6, 1
        (lw, lh), _ = cv2.getTextSize(label, font, fs, thick)
        ty = max(y1 - lh - 6, 0)
        cv2.rectangle(annotated, (x1, ty), (x1 + lw + 6, y1), color, -1)
        cv2.putText(annotated, label, (x1 + 3, y1 - 4), font, fs, (0, 0, 0), thick, cv2.LINE_AA)

    return annotated


# =========================================================
#  后台视频+推理线程
# =========================================================
def inference_loop():
    global latest_frame_bytes

    if not Path(MODEL_PATH).exists():
        print(f"[Backend] ERROR: Model file not found: {MODEL_PATH}")
        print("[Backend] Set ROV_MODEL_PATH to your YOLO model file.")
        return

    video_source = int(VIDEO_SOURCE) if str(VIDEO_SOURCE).isdigit() else VIDEO_SOURCE
    if isinstance(video_source, str) and not Path(video_source).exists():
        print(f"[Backend] ERROR: Video source not found: {video_source}")
        print("[Backend] Set ROV_VIDEO_SOURCE to a camera index, video file, or stream URL.")
        return

    print(f"[Backend] Loading model: {MODEL_PATH}")
    model = YOLO(MODEL_PATH)
    print(f"[Backend] Model loaded: task={model.task}, classes={model.names}")

    print(f"[Backend] Opening video source: {VIDEO_SOURCE}")
    cap = cv2.VideoCapture(video_source)
    if not cap.isOpened():
        print(f"[Backend] ERROR: Cannot open video source {VIDEO_SOURCE}")
        return

    print("[Backend] Inference loop started.")
    while True:
        ret, frame = cap.read()
        if not ret:
            cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
            continue

        # YOLO推理
        results = model(frame, conf=CONF_THRESH, verbose=False)
        annotated = draw_seg(frame, results[0])

        # 编码JPEG
        ok, buf = cv2.imencode(".jpg", annotated, [cv2.IMWRITE_JPEG_QUALITY, JPEG_QUAL])
        if ok:
            with frame_lock:
                latest_frame_bytes = buf.tobytes()

        time.sleep(1 / 30)  # ~30 fps


# =========================================================
#  WebSocket 服务
# =========================================================
try:
    import websockets
except ImportError:
    print("请安装: pip install websockets")
    sys.exit(1)


connected_clients: set = set()


async def send_frames(websocket):
    """持续向客户端推送视频帧"""
    try:
        while True:
            with frame_lock:
                data = latest_frame_bytes
            if data:
                msg = json.dumps({"type": "frame", "data": base64.b64encode(data).decode()})
                await websocket.send(msg)
            await asyncio.sleep(1 / 30)
    except websockets.exceptions.ConnectionClosed:
        pass


async def handler(websocket, path=None):
    connected_clients.add(websocket)
    addr = getattr(websocket, "remote_address", "?")
    print(f"[WS] Client connected: {addr}")

    video_task = asyncio.create_task(send_frames(websocket))
    try:
        async for message in websocket:
            # 简单echo控制命令（兼容Flutter端）
            try:
                data = json.loads(message)
                print(f"[WS] CMD: {data.get('command', data.get('type', '?'))}")
                await websocket.send(json.dumps({"type": "ack", "success": True}))
            except Exception:
                pass
    finally:
        video_task.cancel()
        connected_clients.discard(websocket)
        print(f"[WS] Client disconnected: {addr}")


async def main():
    # 启动推理线程
    t = threading.Thread(target=inference_loop, daemon=True)
    t.start()

    print(f"[WS] Server starting on ws://{WS_HOST}:{WS_PORT}")
    async with websockets.serve(handler, WS_HOST, WS_PORT):
        print(f"[WS] Ready.  Connect Flutter to ws://{WS_HOST}:{WS_PORT}")
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    asyncio.run(main())
