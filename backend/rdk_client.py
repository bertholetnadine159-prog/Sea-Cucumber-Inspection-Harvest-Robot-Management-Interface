#!/usr/bin/env python3
"""PC 端 -> RDK X5 的 WebSocket 客户端（网线直连）。

职责：
  - 连接 ws://<ROV_RDK_HOST>:<ROV_RDK_PORT>，断线自动重连
  - 缓存最新视频帧与遥测，供 app.py 转发给 Flutter 界面
  - 把界面命令转发给 RDK X5
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from typing import Any, Callable

import websockets


LOGGER = logging.getLogger("backend.rdk_client")


class RdkClient:
    def __init__(self, host: str = "192.168.127.10", port: int = 8080):
        self.host = host
        self.port = port
        self.connected = False
        self.last_error = ""
        self.last_hello: dict[str, Any] = {}
        self.latest_frame: dict[str, Any] | None = None
        self.latest_telemetry: dict[str, Any] | None = None
        self._websocket = None
        self._send_lock = asyncio.Lock()
        self._task: asyncio.Task | None = None
        self._stop = asyncio.Event()
        self._on_telemetry: Callable[[dict[str, Any]], None] | None = None

    @property
    def uri(self) -> str:
        return f"ws://{self.host}:{self.port}"

    def start(self, loop: asyncio.AbstractEventLoop) -> None:
        self._task = loop.create_task(self._run())

    async def stop(self) -> None:
        self._stop.set()
        if self._task is not None:
            self._task.cancel()
            try:
                await self._task
            except (asyncio.CancelledError, Exception):  # noqa: BLE001
                pass
        if self._websocket is not None:
            await self._websocket.close()

    def set_telemetry_callback(self, callback: Callable[[dict[str, Any]], None]) -> None:
        self._on_telemetry = callback

    async def send_command(self, command: str, params: dict[str, Any] | None = None) -> bool:
        """发送控制命令。未连接时返回 False。"""
        if self._websocket is None or not self.connected:
            return False
        message = {
            "type": "command",
            "command": command,
            "params": params or {},
        }
        try:
            async with self._send_lock:
                await self._websocket.send(json.dumps(message, ensure_ascii=False))
            return True
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("send_command(%s) failed: %s", command, exc)
            return False

    async def set_video(self, width: int, height: int, fps: int, jpeg_quality: int) -> bool:
        if self._websocket is None or not self.connected:
            return False
        try:
            async with self._send_lock:
                await self._websocket.send(json.dumps({
                    "type": "set_video",
                    "params": {"width": width, "height": height, "fps": fps, "jpeg_quality": jpeg_quality},
                }))
            return True
        except Exception:
            return False

    async def set_camera(self, camera_id: str) -> bool:
        """切换 RDK X5 的活动摄像头（camera_1 前视 / camera_2 吸口近距）。"""
        return await self.send_command("set_camera", {"camera_id": camera_id})

    async def send_raw(self, message: dict[str, Any]) -> bool:
        if self._websocket is None or not self.connected:
            return False
        try:
            async with self._send_lock:
                await self._websocket.send(json.dumps(message, ensure_ascii=False))
            return True
        except Exception:
            return False

    async def _run(self) -> None:
        while not self._stop.is_set():
            try:
                LOGGER.info("Connecting to RDK X5 %s", self.uri)
                async with websockets.connect(
                    self.uri,
                    ping_interval=20,
                    ping_timeout=10,
                    open_timeout=5,
                    max_size=20 * 1024 * 1024,
                ) as websocket:
                    self._websocket = websocket
                    self.connected = True
                    self.last_error = ""
                    LOGGER.info("RDK X5 connected")
                    await self._receive_loop(websocket)
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # noqa: BLE001
                self.last_error = str(exc)
                LOGGER.warning("RDK X5 connection lost: %s (retry in 2s)", exc)
            finally:
                self.connected = False
                self._websocket = None
            if not self._stop.is_set():
                await asyncio.sleep(2)

    async def _receive_loop(self, websocket) -> None:
        async for raw in websocket:
            try:
                message = json.loads(raw)
            except json.JSONDecodeError:
                continue
            mtype = message.get("type")
            if mtype == "hello":
                self.last_hello = message
            elif mtype == "frame":
                self.latest_frame = message
            elif mtype == "telemetry":
                self.latest_telemetry = message
                if self._on_telemetry is not None:
                    try:
                        self._on_telemetry(message)
                    except Exception as exc:  # noqa: BLE001
                        LOGGER.warning("telemetry callback failed: %s", exc)
            elif mtype == "log":
                LOGGER.info("[RDK X5] %s", message.get("message", ""))
