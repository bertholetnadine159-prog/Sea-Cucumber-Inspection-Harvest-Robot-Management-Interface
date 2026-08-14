#!/usr/bin/env python3
"""
SeaUI 桌面端本地后端（PC 上运行）

三种运行模式（环境变量 ROV_BACKEND_MODE）：
  rdk   默认。视频、AI 检测、传感器、Pixhawk 控制全部走 RDK X5（网线直连）。
        PC 只做“桥接 + 数据库 + 鉴权”，不再在 PC 上跑 ONNX。
  local 兼容旧版：PC 本地摄像头 + best.onnx 推理（无 RDK X5 时开发调试用）。
  sim   无硬件仿真：合成视频帧与遥测，用于界面联调。

对外接口：
  ws://127.0.0.1:8765     Flutter 界面（视频帧 / 遥测 / 状态 / 控制 / 鉴权）
  http://127.0.0.1:5000   REST（登录、管理员、传感器、日志、命令）

控制链：Flutter UI -> 本服务 -> RDK X5 -> Pixhawk 2.4.8
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import os
import threading
import time
import warnings
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

import cv2
import numpy as np

from database import Database
from rdk_client import RdkClient

warnings.filterwarnings("ignore")

LOGGER = logging.getLogger("backend.app")
logging.basicConfig(level=logging.INFO, format="[%(asctime)s] [%(name)s] %(levelname)s %(message)s")

# ============================================================================
# 配置
# ============================================================================
BASE_DIR = Path(__file__).resolve().parent.parent
BACKEND_DIR = Path(__file__).resolve().parent

MODE = os.getenv("ROV_BACKEND_MODE", "rdk").lower()
if MODE not in ("rdk", "local", "sim"):
    MODE = "rdk"

RDK_HOST = os.getenv("ROV_RDK_HOST", "192.168.127.10")
RDK_PORT = int(os.getenv("ROV_RDK_PORT", "8080"))

UI_HOST = os.getenv("ROV_WS_HOST", "127.0.0.1")
UI_PORT = int(os.getenv("ROV_WS_PORT", "8765"))
API_HOST = "127.0.0.1"
API_PORT = int(os.getenv("ROV_API_PORT", "5000"))

VIDEO_SOURCE = os.getenv("ROV_VIDEO_SOURCE") or "0"
MODEL_PATH = os.getenv("ROV_MODEL_PATH", str(BASE_DIR / "best.onnx"))
CONF_THRESH = float(os.getenv("ROV_CONF_THRESH", "0.25"))
JPEG_QUAL = int(os.getenv("ROV_JPEG_QUAL", "80"))
DB_PATH = os.getenv("ROV_DB_PATH", str(BACKEND_DIR / "data" / "seaUI.db"))

COLORS = [
    (0, 200, 255), (0, 255, 128), (255, 80, 80), (80, 80, 255),
    (200, 0, 200), (0, 220, 220), (255, 200, 0), (100, 255, 100),
]

db = Database(DB_PATH)
rdk_client = RdkClient(RDK_HOST, RDK_PORT)

# 最新 JPEG 帧（rdk/local/sim 三种模式共用）
latest_frame_bytes: bytes = b""
latest_frame_meta: dict[str, Any] = {}
frame_lock = threading.Lock()
frame_seq = 0

# UI WebSocket 客户端集合
ui_clients: set = set()

# 运动命令死区状态
move_state_lock = threading.Lock()
last_move: dict[str, Any] | None = None
move_active = False


# ============================================================================
# 本地 ONNX 推理（仅 MODE=local 使用）
# ============================================================================
def draw_seg(frame: np.ndarray, result) -> np.ndarray:
    annotated = frame.copy()
    h, w = frame.shape[:2]
    boxes = result.boxes
    masks = result.masks
    for idx, box in enumerate(boxes):
        cls_id = int(box.cls[0])
        conf = float(box.conf[0])
        x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
        color = COLORS[idx % len(COLORS)]
        if masks is not None:
            mask_np = masks.data[idx].cpu().numpy()
            mask_rs = cv2.resize(mask_np, (w, h), interpolation=cv2.INTER_NEAREST)
            bm = (mask_rs > 0.5).astype(np.uint8)
            overlay = np.zeros_like(annotated, dtype=np.uint8)
            overlay[bm == 1] = color
            annotated = cv2.addWeighted(annotated, 1.0, overlay, 0.45, 0)
            contours, _ = cv2.findContours(bm, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            cv2.drawContours(annotated, contours, -1, color, 2)
        cv2.rectangle(annotated, (x1, y1), (x2, y2), color, 2)
        label = f"{result.names[cls_id]} {conf:.2f}"
        font, fs, thick = cv2.FONT_HERSHEY_SIMPLEX, 0.6, 1
        (lw, lh), _ = cv2.getTextSize(label, font, fs, thick)
        ty = max(y1 - lh - 6, 0)
        cv2.rectangle(annotated, (x1, ty), (x1 + lw + 6, y1), color, -1)
        cv2.putText(annotated, label, (x1 + 3, y1 - 4), font, fs, (0, 0, 0), thick, cv2.LINE_AA)
    return annotated


def local_inference_loop() -> None:
    """PC 本地摄像头 + ONNX 推理（旧版兼容模式）。"""
    global latest_frame_bytes, latest_frame_meta, frame_seq
    from ultralytics import YOLO

    if not Path(MODEL_PATH).exists():
        LOGGER.error("Model file not found: %s", MODEL_PATH)
        return
    video_source = int(VIDEO_SOURCE) if str(VIDEO_SOURCE).isdigit() else VIDEO_SOURCE
    model = YOLO(MODEL_PATH)
    cap = cv2.VideoCapture(video_source)
    if not cap.isOpened():
        LOGGER.error("Cannot open video source %s", VIDEO_SOURCE)
        return
    while True:
        ret, frame = cap.read()
        if not ret:
            cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
            continue
        results = model(frame, conf=CONF_THRESH, verbose=False)
        annotated = draw_seg(frame, results[0])
        ok, buf = cv2.imencode(".jpg", annotated, [cv2.IMWRITE_JPEG_QUALITY, JPEG_QUAL])
        if ok:
            with frame_lock:
                latest_frame_bytes = buf.tobytes()
                frame_seq += 1
                latest_frame_meta = {"seq": frame_seq, "width": annotated.shape[1], "height": annotated.shape[0]}
        time.sleep(1 / 30)


def sim_video_loop() -> None:
    """无硬件仿真视频（界面联调用）。"""
    global latest_frame_bytes, latest_frame_meta, frame_seq
    index = 0
    while True:
        frame = np.zeros((720, 1280, 3), dtype=np.uint8)
        frame[:, :] = (72, 58, 38)
        offset = max(0, 240 - index * 4)
        cv2.ellipse(frame, (640 + offset, 380), (110, 55), 0, 0, 360, (180, 120, 28), -1)
        cv2.line(frame, (640, 0), (640, 720), (130, 80, 80), 1)
        cv2.putText(frame, "SEAUI SIM MODE", (24, 48), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 255, 255), 2)
        ok, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 80])
        if ok:
            with frame_lock:
                latest_frame_bytes = buf.tobytes()
                frame_seq += 1
                latest_frame_meta = {"seq": frame_seq, "width": 1280, "height": 720}
        index += 1
        time.sleep(1 / 15)


def sim_telemetry_loop() -> None:
    """sim 模式合成传感器遥测：入库并推送界面，便于无硬件演示完整链路。"""
    import math

    start = time.time()
    while True:
        elapsed = time.time() - start
        sensors = {
            "ms5837_depth": {
                "ok": True,
                "values": {
                    "pressure_mbar": 1018.5 + 0.3 * math.sin(elapsed / 20.0),
                    "temperature_c": 18.4,
                    "depth_m": 0.5 + 0.08 * math.sin(elapsed / 15.0),
                },
            },
            "ds18b20_water_1": {"ok": True, "values": {"temperature_c": 18.8}},
            "ds18b20_water_2": {"ok": True, "values": {"temperature_c": 19.1}},
            "veml7700_front_light": {"ok": True, "values": {"lux": 170.0 + 30.0 * math.sin(elapsed / 10.0)}},
            "veml7700_down_light": {"ok": True, "values": {"lux": 88.0 + 12.0 * math.sin(elapsed / 13.0)}},
            "ultrasonic_front_suction_mouth": {"ok": True, "values": {"distance_m": 0.35}},
            "ultrasonic_downward_altitude": {"ok": True, "values": {"distance_m": 0.72}},
        }
        handle_telemetry({
            "ts": time.time(),
            "source": "sim",
            "sensors": sensors,
            "pixhawk": {"connected": True, "armed": False, "mode": "SIM"},
            "link": {"fps": 15.0},
        })
        time.sleep(2)


# ============================================================================
# 状态与遥测
# ============================================================================
def current_status() -> dict[str, Any]:
    rdk_telemetry = rdk_client.latest_telemetry or {}
    return {
        "backend_mode": MODE,
        "rdk": {
            "connected": rdk_client.connected,
            "host": rdk_client.host,
            "port": rdk_client.port,
            "last_error": rdk_client.last_error,
            "caps": rdk_client.last_hello.get("caps", []),
            "cameras": rdk_client.last_hello.get("cameras", []),
            "active_camera": (rdk_client.latest_frame or {}).get("camera_id", ""),
        },
        "pixhawk": rdk_telemetry.get("pixhawk", {}),
        "link": rdk_telemetry.get("link", {}),
    }


def handle_telemetry(telemetry: dict[str, Any]) -> None:
    """RDK X5 遥测到达：入库 + 广播给 Flutter 界面。"""
    sensors = telemetry.get("sensors", {})
    source = str(telemetry.get("source", "rdk_x5"))
    try:
        db.log_sensor_snapshot(sensors, source=source)
    except Exception as exc:  # noqa: BLE001
        LOGGER.warning("sensor logging failed: %s", exc)
    message = json.dumps({
        "type": "sensors",
        "ts": telemetry.get("ts", time.time()),
        "data": sensors,
        "pixhawk": telemetry.get("pixhawk", {}),
    }, ensure_ascii=False)
    broadcast_to_ui(message)


def broadcast_to_ui(text: str) -> None:
    for websocket in list(ui_clients):
        try:
            asyncio.create_task(websocket.send(text))
        except Exception:
            pass


def sync_frame_from_rdk() -> bool:
    """把 RDK X5 的最新帧同步到 UI 缓存；返回是否有新帧。"""
    global latest_frame_bytes, latest_frame_meta, frame_seq
    frame = rdk_client.latest_frame
    if not frame:
        return False
    seq = int(frame.get("seq", 0))
    with frame_lock:
        if seq == frame_seq:
            return False
        try:
            data = base64.b64decode(frame.get("jpeg", ""))
        except Exception:
            return False
        if not data:
            return False
        latest_frame_bytes = data
        frame_seq = seq
        latest_frame_meta = {
            "seq": seq,
            "camera_id": frame.get("camera_id", ""),
            "width": frame.get("width", 0),
            "height": frame.get("height", 0),
            "inference_ms": frame.get("inference_ms", 0),
            "fps": frame.get("fps", 0),
        }
        return True


# ============================================================================
# UI WebSocket（Flutter 连接）
# ============================================================================
async def push_frames_to_ui(websocket) -> None:
    last_seq = -1
    last_status_at = 0.0
    try:
        while True:
            sync_frame_from_rdk()
            with frame_lock:
                data = latest_frame_bytes
                seq = frame_seq
                meta = dict(latest_frame_meta)
            if data and seq != last_seq:
                last_seq = seq
                await websocket.send(json.dumps({
                    "type": "frame",
                    "data": base64.b64encode(data).decode(),
                    "camera_id": meta.get("camera_id", ""),
                    "seq": seq,
                }))
            now = time.monotonic()
            if now - last_status_at >= 1.0:
                last_status_at = now
                await websocket.send(json.dumps({"type": "status", "data": current_status()}, ensure_ascii=False))
            await asyncio.sleep(1 / 30)
    except asyncio.CancelledError:
        raise
    except Exception:
        pass


async def ui_handler(websocket) -> None:
    ui_clients.add(websocket)
    address = getattr(websocket, "remote_address", "?")
    LOGGER.info("[UI] client connected: %s", address)
    try:
        await websocket.send(json.dumps({"type": "hello", "backend": "seaUI-bridge", "mode": MODE}))
    except Exception:
        pass
    push_task = asyncio.create_task(push_frames_to_ui(websocket))
    try:
        async for raw in websocket:
            try:
                message = json.loads(raw)
            except json.JSONDecodeError:
                continue
            await handle_ui_message(websocket, message)
    finally:
        push_task.cancel()
        ui_clients.discard(websocket)
        LOGGER.info("[UI] client disconnected: %s", address)


async def handle_ui_message(websocket, message: dict[str, Any]) -> None:
    mtype = message.get("type", "")
    if mtype == "auth":
        await handle_auth_message(websocket, message)
        return
    if mtype == "command":
        await handle_ui_command(websocket, message)
        return
    if mtype == "set_rdk_config":
        host = str(message.get("host", rdk_client.host))
        port = int(message.get("port", rdk_client.port))
        db.set_setting("rdk_host", host)
        db.set_setting("rdk_port", str(port))
        rdk_client.host = host
        rdk_client.port = port
        await websocket.send(json.dumps({"type": "ack", "command": "set_rdk_config", "success": True}))
        return
    if mtype == "get_status":
        await websocket.send(json.dumps({"type": "status", "data": current_status()}, ensure_ascii=False))
        return
    if mtype == "get_telemetry":
        await rdk_client.send_raw({"type": "get_telemetry"})
        return
    await websocket.send(json.dumps({"type": "ack", "command": mtype, "success": False, "message": "unknown message type"}))


async def handle_auth_message(websocket, message: dict[str, Any]) -> None:
    action = message.get("action", "")
    if action == "login":
        username = str(message.get("username", "")).strip()
        password = str(message.get("password", ""))
        user = db.verify_credentials(username, password)
        if user is None:
            await websocket.send(json.dumps({"type": "auth_result", "success": False, "error": "用户名或密码错误"}))
            return
        token, expires_at = db.create_session(user["id"])
        await websocket.send(json.dumps({
            "type": "auth_result",
            "success": True,
            "token": token,
            "expires_at": expires_at,
            "user": user,
        }))
        return
    if action == "logout":
        db.revoke_session(str(message.get("token", "")))
        await websocket.send(json.dumps({"type": "auth_result", "success": True, "action": "logout"}))
        return
    await websocket.send(json.dumps({"type": "auth_result", "success": False, "error": "unknown auth action"}))


def translate_ui_command(command: str, params: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    """把 Flutter 的旧命令名翻译成 RDK X5 协议命令。"""
    try:
        speed = max(-1.0, min(1.0, float(params.get("speed", 1.0))))
    except (TypeError, ValueError):
        speed = 1.0

    def move(axes: dict[str, float]) -> tuple[str, dict[str, Any]]:
        return "move", {"axes": axes, "deadman_ms": int(params.get("deadman_ms", 1000))}

    mapping: dict[str, tuple[str, dict[str, Any]]] = {
        "forward": move({"surge": speed}),
        "backward": move({"surge": -speed}),
        "left": move({"yaw": -speed}),
        "right": move({"yaw": speed}),
        "up": move({"heave": -speed}),
        "down": move({"heave": speed}),
        "stop": ("stop", {}),
        "grab": ("suction", {"power_percent": 100}),
        "release": ("suction", {"power_percent": 0}),
        "lightOn": ("light_on", {}),
        "lightOff": ("light_off", {}),
        "sonarOn": ("sonar_on", {}),
        "sonarOff": ("sonar_off", {}),
        "laserOn": ("laser_on", {}),
        "laserOff": ("laser_off", {}),
        "autoCruise": ("auto_cruise", {"enabled": bool(params.get("enabled", False))}),
        "emergencyStop": ("emergency_stop", {}),
        "snapshot": ("snapshot", {}),
        "resetPosition": ("reset_position", {}),
    }
    return mapping.get(command, (command, params))


async def handle_ui_command(websocket, message: dict[str, Any]) -> None:
    global last_move, move_active
    command = str(message.get("command", ""))
    params = message.get("params", {}) or {}
    # Flutter 客户端把 speed/enabled 等参数平铺在消息根层，这里合并回 params
    if isinstance(params, dict):
        params = dict(params)
    else:
        params = {}
    for key, value in message.items():
        if key in ("type", "command", "token", "timestamp", "params"):
            continue
        params.setdefault(key, value)
    command, params = translate_ui_command(command, params)
    token = str(message.get("token", ""))
    user = db.validate_session(token)
    username = user["username"] if user else "anonymous"

    if MODE == "rdk":
        if command == "move":
            move_payload = {
                "axes": params.get("axes", {}),
                "deadman_ms": params.get("deadman_ms", 1000),
            }
            with move_state_lock:
                last_move = move_payload
                move_active = True
            ok = await rdk_client.send_command("move", move_payload)
        elif command == "stop":
            with move_state_lock:
                move_active = False
                last_move = None
            ok = await rdk_client.send_command("stop")
        else:
            ok = await rdk_client.send_command(command, params)
    else:
        ok = True  # local/sim 模式没有 RDK，命令视为仿真执行

    db.log_control(username, command, params, ok)
    await websocket.send(json.dumps({"type": "ack", "command": command, "success": ok}))


async def move_deadman_loop() -> None:
    """move 命令死区看门狗：活跃期间每 100ms 重发，超时自动 stop。"""
    global move_active
    while True:
        with move_state_lock:
            move = dict(last_move) if last_move else None
        if move:
            await rdk_client.send_command("move", move)
        elif move_active:
            move_active = False
            await rdk_client.send_command("stop")
        await asyncio.sleep(0.1)


# ============================================================================
# REST API（管理员 / 传感器 / 日志 / 命令）
# ============================================================================
def _read_json_body(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    length = int(handler.headers.get("Content-Length", 0))
    if length <= 0:
        return {}
    raw = handler.rfile.read(length)
    try:
        return json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError:
        return {}


def _send_json(handler: BaseHTTPRequestHandler, status: int, payload: dict[str, Any]) -> None:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
    handler.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
    handler.end_headers()
    handler.wfile.write(body)


def _bearer_user(handler: BaseHTTPRequestHandler) -> dict[str, Any] | None:
    header = handler.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    return db.validate_session(header[len("Bearer "):].strip())


def _require_user(handler: BaseHTTPRequestHandler) -> dict[str, Any] | None:
    user = _bearer_user(handler)
    if user is None:
        _send_json(handler, 401, {"ok": False, "error": "unauthorized"})
    return user


def _is_admin(user: dict[str, Any]) -> bool:
    return user.get("role") in ("super_admin", "admin")


class ApiHandler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
        LOGGER.debug("%s - %s", self.address_string(), format % args)

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        if parsed.path == "/api/health":
            _send_json(self, 200, {"ok": True, **current_status()})
            return
        if parsed.path == "/api/sensors":
            if _require_user(self) is None:
                return
            limit = int(query.get("limit", ["500"])[0])
            _send_json(self, 200, {"ok": True, "data": db.get_sensor_readings(limit)})
            return
        if parsed.path == "/api/logs":
            if _require_user(self) is None:
                return
            limit = int(query.get("limit", ["500"])[0])
            _send_json(self, 200, {"ok": True, "data": db.get_control_logs(limit)})
            return
        if parsed.path == "/api/users":
            user = _require_user(self)
            if user is None:
                return
            if not _is_admin(user):
                _send_json(self, 403, {"ok": False, "error": "admin only"})
                return
            _send_json(self, 200, {"ok": True, "data": db.list_users()})
            return
        if parsed.path == "/api/me":
            user = _require_user(self)
            if user is None:
                return
            _send_json(self, 200, {"ok": True, "user": user})
            return
        _send_json(self, 404, {"ok": False, "error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        body = _read_json_body(self)
        if parsed.path == "/api/login":
            user = db.verify_credentials(str(body.get("username", "")), str(body.get("password", "")))
            if user is None:
                _send_json(self, 401, {"ok": False, "error": "用户名或密码错误"})
                return
            token, expires_at = db.create_session(user["id"])
            _send_json(self, 200, {"ok": True, "token": token, "expires_at": expires_at, "user": user})
            return
        if parsed.path == "/api/command":
            user = _require_user(self)
            if user is None:
                return
            command = str(body.get("command", ""))
            params = body.get("params", {}) or {}
            future = asyncio.run_coroutine_threadsafe(rdk_client.send_command(command, params), MAIN_LOOP)
            try:
                ok = bool(future.result(timeout=3))
            except Exception:
                ok = False
            db.log_control(user["username"], command, params, ok)
            _send_json(self, 200, {"ok": ok, "command": command})
            return
        if parsed.path == "/api/users":
            user = _require_user(self)
            if user is None:
                return
            if not _is_admin(user):
                _send_json(self, 403, {"ok": False, "error": "admin only"})
                return
            try:
                user_id = db.create_user(
                    str(body.get("username", "")),
                    str(body.get("password", "")),
                    str(body.get("role", "admin")),
                    str(body.get("real_name", "")),
                )
            except Exception as exc:
                _send_json(self, 400, {"ok": False, "error": str(exc)})
                return
            _send_json(self, 200, {"ok": True, "id": user_id})
            return
        _send_json(self, 404, {"ok": False, "error": "not found"})

    def do_PUT(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        parts = [part for part in parsed.path.strip("/").split("/") if part]
        body = _read_json_body(self)
        if len(parts) == 4 and parts[0] == "api" and parts[1] == "users" and parts[3] == "password":
            user = _require_user(self)
            if user is None:
                return
            if not _is_admin(user):
                _send_json(self, 403, {"ok": False, "error": "admin only"})
                return
            try:
                db.change_password(int(parts[2]), str(body.get("password", "")))
            except Exception as exc:
                _send_json(self, 400, {"ok": False, "error": str(exc)})
                return
            _send_json(self, 200, {"ok": True})
            return
        if len(parts) == 3 and parts[0] == "api" and parts[1] == "users":
            user = _require_user(self)
            if user is None:
                return
            if not _is_admin(user):
                _send_json(self, 403, {"ok": False, "error": "admin only"})
                return
            db.update_user(
                int(parts[2]),
                role=body.get("role"),
                real_name=body.get("real_name"),
                enabled=body.get("enabled"),
            )
            _send_json(self, 200, {"ok": True})
            return
        _send_json(self, 404, {"ok": False, "error": "not found"})

    def do_DELETE(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        parts = [part for part in parsed.path.strip("/").split("/") if part]
        if len(parts) == 3 and parts[0] == "api" and parts[1] == "users":
            user = _require_user(self)
            if user is None:
                return
            if not _is_admin(user):
                _send_json(self, 403, {"ok": False, "error": "admin only"})
                return
            removed = db.delete_user(int(parts[2]))
            _send_json(
                self,
                200 if removed else 400,
                {"ok": removed, "error": "" if removed else "super admin cannot be deleted"},
            )
            return
        _send_json(self, 404, {"ok": False, "error": "not found"})


# ============================================================================
# 启动
# ============================================================================
MAIN_LOOP: asyncio.AbstractEventLoop | None = None


def start_api_server() -> ThreadingHTTPServer:
    server = ThreadingHTTPServer((API_HOST, API_PORT), ApiHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    LOGGER.info("[API] ready at http://%s:%s", API_HOST, API_PORT)
    return server


async def main() -> None:
    global MAIN_LOOP
    MAIN_LOOP = asyncio.get_running_loop()

    saved_host = db.get_setting("rdk_host")
    saved_port = db.get_setting("rdk_port")
    if saved_host:
        rdk_client.host = saved_host
    if saved_port:
        try:
            rdk_client.port = int(saved_port)
        except ValueError:
            pass

    rdk_client.set_telemetry_callback(handle_telemetry)
    if MODE == "rdk":
        rdk_client.start(MAIN_LOOP)
        LOGGER.info("[backend] mode=rdk bridge -> ws://%s:%s", rdk_client.host, rdk_client.port)
    elif MODE == "local":
        threading.Thread(target=local_inference_loop, daemon=True).start()
        LOGGER.info("[backend] mode=local (PC camera + best.onnx)")
    else:
        threading.Thread(target=sim_video_loop, daemon=True).start()
        threading.Thread(target=sim_telemetry_loop, daemon=True).start()
        LOGGER.info("[backend] mode=sim (synthetic frames)")

    api_server = start_api_server()
    move_task = asyncio.create_task(move_deadman_loop())

    try:
        import websockets
    except ImportError:
        LOGGER.error("pip install websockets")
        return

    LOGGER.info("[UI] WebSocket starting on ws://%s:%s", UI_HOST, UI_PORT)
    try:
        async with websockets.serve(ui_handler, UI_HOST, UI_PORT, max_size=20 * 1024 * 1024):
            LOGGER.info("[UI] ready. Flutter connects to ws://%s:%s", UI_HOST, UI_PORT)
            await asyncio.Future()
    finally:
        move_task.cancel()
        await rdk_client.stop()
        api_server.shutdown()


if __name__ == "__main__":
    asyncio.run(main())
