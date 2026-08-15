# ============================================================================
# [RDK X5 side] WebSocket 服务
# 一条通道同时承载：标注后视频帧（下行）、传感器/Pixhawk 遥测（下行）、
# PC 控制命令（上行）。协议详见 PROTOCOL.md。
# ============================================================================
from __future__ import annotations

import asyncio
import json
import logging
import time
from typing import Any

import websockets


LOGGER = logging.getLogger("rdkx5.stream")


class CommandHandler:
    """把 PC 命令翻译成 RDK X5 本地的执行动作。"""

    def __init__(
        self,
        pixhawk,
        video,
        suction_channels: list[int],
        servo_channel: int | None,
        light_channels: list[int],
        safety: dict[str, Any],
    ):
        self.pixhawk = pixhawk
        self.video = video
        self.suction_channels = suction_channels
        self.servo_channel = servo_channel
        self.light_channels = light_channels
        self.safety = safety
        self._light_on = False
        self._sonar_on = False
        self._laser_on = False
        self._auto_cruise = False

    async def handle(self, message: dict[str, Any]) -> dict[str, Any]:
        mtype = message.get("type", "")
        command = message.get("command", "")
        params = message.get("params", {}) or {}

        if mtype == "command":
            return self._handle_command(command, params)
        if mtype == "set_video":
            self.video.set_quality(
                int(params.get("width", 1280)),
                int(params.get("height", 720)),
                int(params.get("fps", 15)),
                int(params.get("jpeg_quality", 78)),
            )
            return {"type": "ack", "command": "set_video", "success": True}
        if mtype == "get_telemetry":
            return {"type": "ack", "command": "get_telemetry", "success": True}
        return {"type": "ack", "command": command or mtype, "success": False, "message": "unknown message type"}

    def _handle_command(self, command: str, params: dict[str, Any]) -> dict[str, Any]:
        try:
            if command == "move":
                axes = params.get("axes", {})
                allowed = ("surge", "sway", "heave", "roll", "pitch", "yaw")
                cleaned = {axis: float(axes.get(axis, 0.0)) for axis in allowed}
                deadman_ms = int(params.get("deadman_ms", self.safety.get("deadman_ms", 1000)))
                self.pixhawk.set_deadman_ms(deadman_ms)
                self.pixhawk.set_axes(cleaned)
                return {"type": "ack", "command": command, "success": True}

            if command == "stop":
                self.pixhawk.neutralize()
                return {"type": "ack", "command": command, "success": True}

            if command in ("arm", "disarm"):
                self.pixhawk.arm(command == "arm", force=bool(params.get("force", False)))
                return {"type": "ack", "command": command, "success": True}

            if command == "set_mode":
                self.pixhawk.set_mode(str(params["mode"]))
                return {"type": "ack", "command": command, "success": True}

            if command == "set_camera":
                camera_id = str(params.get("camera_id", ""))
                try:
                    self.video.set_camera(camera_id)
                except Exception as exc:  # noqa: BLE001
                    return {"type": "ack", "command": command, "success": False, "message": str(exc)}
                return {
                    "type": "ack",
                    "command": command,
                    "success": True,
                    "camera_id": self.video.active_camera_id,
                }

            if command == "suction":
                percent = max(0.0, min(100.0, float(params.get("power_percent", 0.0))))
                pwm = int(1000 + (percent / 100.0) * 1000)
                for channel in self.suction_channels:
                    self.pixhawk.set_pwm(channel, pwm)
                return {"type": "ack", "command": command, "success": True, "pwm": pwm}

            if command == "servo":
                channel = int(params.get("channel", self.servo_channel or 0))
                pwm = int(params.get("pwm", 1500))
                self.pixhawk.set_pwm(channel, pwm)
                return {"type": "ack", "command": command, "success": True}

            if command in ("light_on", "light_off"):
                self._light_on = command == "light_on"
                pwm = 1900 if self._light_on else 1100
                for channel in self.light_channels:
                    self.pixhawk.set_pwm(channel, pwm)
                return {"type": "ack", "command": command, "success": True, "on": self._light_on}

            if command in ("sonar_on", "sonar_off"):
                self._sonar_on = command == "sonar_on"
                return {"type": "ack", "command": command, "success": True, "on": self._sonar_on}

            if command in ("laser_on", "laser_off"):
                self._laser_on = command == "laser_on"
                return {"type": "ack", "command": command, "success": True, "on": self._laser_on}

            if command == "auto_cruise":
                self._auto_cruise = bool(params.get("enabled", False))
                return {"type": "ack", "command": command, "success": True, "enabled": self._auto_cruise}

            if command == "snapshot":
                frame = self.video.latest()
                if frame is None or not frame.jpeg:
                    return {"type": "ack", "command": command, "success": False, "message": "no frame available"}
                import pathlib

                folder = pathlib.Path(__file__).resolve().parent / "snapshots"
                folder.mkdir(exist_ok=True)
                target = folder / f"rdk_{int(time.time())}.jpg"
                target.write_bytes(frame.jpeg)
                path = str(target)
                return {"type": "ack", "command": command, "success": True, "path": path}

            if command == "emergency_stop":
                self.pixhawk.emergency_stop(disarm=bool(self.safety.get("emergency_stop_disarm", False)))
                return {"type": "ack", "command": command, "success": True}

            if command == "reset_position":
                return {"type": "ack", "command": command, "success": True}

            return {"type": "ack", "command": command, "success": False, "message": f"unknown command: {command}"}
        except Exception as exc:  # noqa: BLE001
            LOGGER.exception("[RDK X5] command failed: %s", command)
            return {"type": "ack", "command": command, "success": False, "message": str(exc)}


class StreamServer:
    def __init__(
        self,
        host: str,
        port: int,
        video,
        sensor_hub,
        pixhawk,
        handler: CommandHandler,
        telemetry_hz: int = 5,
    ):
        self.host = host
        self.port = port
        self.video = video
        self.sensor_hub = sensor_hub
        self.pixhawk = pixhawk
        self.handler = handler
        self.telemetry_hz = telemetry_hz
        self.clients: set[websockets.WebSocketServerProtocol] = set()
        self._server = None

    async def start(self) -> None:
        LOGGER.info("[RDK X5] WebSocket server starting ws://%s:%s", self.host, self.port)
        self._server = await websockets.serve(self._on_client, self.host, self.port)
        LOGGER.info("[RDK X5] WebSocket ready. PC connects to ws://<rdk_ip>:%s", self.port)

    async def serve_forever(self) -> None:
        await asyncio.Future()

    async def stop(self) -> None:
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()

    async def _on_client(self, websocket) -> None:
        remote = websocket.remote_address
        LOGGER.info("[RDK X5] PC connected: %s", remote)
        self.clients.add(websocket)
        await websocket.send(json.dumps({
            "type": "hello",
            "device": "rdk_x5",
            "version": "2.0.0",
            "caps": ["video", "sensors", "pixhawk"],
            "cameras": list(self.video.camera_ids()),
        }))

        push_task = asyncio.create_task(self._push_loop(websocket))
        try:
            async for raw in websocket:
                try:
                    message = json.loads(raw)
                except json.JSONDecodeError:
                    await websocket.send(json.dumps({"type": "ack", "command": "?", "success": False, "message": "invalid json"}))
                    continue
                response = await self.handler.handle(message)
                await websocket.send(json.dumps(response, ensure_ascii=False))
        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            push_task.cancel()
            self.clients.discard(websocket)
            LOGGER.info("[RDK X5] PC disconnected: %s", remote)

    async def _push_loop(self, websocket) -> None:
        telemetry_interval = 1.0 / max(1, self.telemetry_hz)
        last_telemetry = 0.0
        last_frame_seq = -1
        try:
            while True:
                frame = self.video.latest()
                if frame is not None and frame.seq != last_frame_seq:
                    last_frame_seq = frame.seq
                    await websocket.send(json.dumps(frame.to_json()))

                now = time.monotonic()
                if now - last_telemetry >= telemetry_interval:
                    last_telemetry = now
                    pixhawk = self.pixhawk.snapshot().to_dict()
                    payload = {
                        "type": "telemetry",
                        "ts": time.time(),
                        "sensors": self.sensor_hub.latest(),
                        "pixhawk": pixhawk,
                        "link": {"fps": frame.fps if frame else 0.0},
                    }
                    await websocket.send(json.dumps(payload, ensure_ascii=False))
                await asyncio.sleep(0.02)
        except (websockets.exceptions.ConnectionClosed, asyncio.CancelledError):
            pass
