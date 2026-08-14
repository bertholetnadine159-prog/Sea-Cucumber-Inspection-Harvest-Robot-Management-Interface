"""端到端回环测试：backend(sim/rdk) + REST + UI WebSocket + 假 RDK 网关。"""

import asyncio
import json
import os
import subprocess
import sys
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

import websockets

from fake_rdk_gateway import main as run_fake_rdk


BACKEND_DIR = Path(__file__).resolve().parents[1]
APP_PY = BACKEND_DIR / "app.py"


def wait_http(url: str, timeout: float = 15.0) -> dict:
    deadline = time.time() + timeout
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=2) as response:
                return json.loads(response.read().decode())
        except Exception as exc:  # noqa: BLE001
            last_error = exc
            time.sleep(0.2)
    raise RuntimeError(f"http not ready: {url} ({last_error})")


def http_json(method: str, url: str, payload: dict | None = None, token: str | None = None) -> tuple[int, dict]:
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Content-Type", "application/json")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status, json.loads(response.read().decode())
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read().decode())


class SimModeIntegrationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        env = os.environ.copy()
        env["ROV_BACKEND_MODE"] = "sim"
        env["ROV_WS_PORT"] = "18765"
        env["ROV_API_PORT"] = "15000"
        env["ROV_DB_PATH"] = str(BACKEND_DIR / "data" / "test_sim.sqlite3")
        cls.process = subprocess.Popen(
            [sys.executable, str(APP_PY)],
            cwd=str(BACKEND_DIR),
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        wait_http("http://127.0.0.1:15000/api/health")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.process.terminate()
        cls.process.wait(timeout=5)

    def test_login_intercepts_missing_and_wrong_credentials(self) -> None:
        status, payload = http_json("POST", "http://127.0.0.1:15000/api/login", {"username": "", "password": ""})
        self.assertEqual(status, 401)
        status, payload = http_json("POST", "http://127.0.0.1:15000/api/login", {"username": "zmm", "password": "bad"})
        self.assertEqual(status, 401)
        self.assertFalse(payload["ok"])

    def test_super_admin_login_and_admin_api(self) -> None:
        status, payload = http_json("POST", "http://127.0.0.1:15000/api/login", {"username": "zmm", "password": "Zmm771023"})
        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        token = payload["token"]

        status, users = http_json("GET", "http://127.0.0.1:15000/api/users", token=token)
        self.assertEqual(status, 200)
        self.assertTrue(any(user["username"] == "zmm" for user in users["data"]))

        status, _ = http_json("GET", "http://127.0.0.1:15000/api/users")
        self.assertEqual(status, 401)

    async def _ui_flow(self) -> None:
        async with websockets.connect("ws://127.0.0.1:18765") as websocket:
            hello = json.loads(await asyncio.wait_for(websocket.recv(), 5))
            self.assertEqual(hello["type"], "hello")

            # sim 模式应持续推送视频帧
            frame = None
            deadline = time.time() + 8
            while time.time() < deadline:
                message = json.loads(await asyncio.wait_for(websocket.recv(), 5))
                if message.get("type") == "frame":
                    frame = message
                    break
            self.assertIsNotNone(frame)
            self.assertIn("data", frame)

            # WS 登录：错误凭据被拦截
            await websocket.send(json.dumps({"type": "auth", "action": "login", "username": "zmm", "password": "nope"}))
            result = json.loads(await asyncio.wait_for(websocket.recv(), 5))
            while result.get("type") != "auth_result":
                result = json.loads(await asyncio.wait_for(websocket.recv(), 5))
            self.assertFalse(result["success"])

            # 正确凭据登录
            await websocket.send(json.dumps({"type": "auth", "action": "login", "username": "zmm", "password": "Zmm771023"}))
            result = json.loads(await asyncio.wait_for(websocket.recv(), 5))
            while result.get("type") != "auth_result":
                result = json.loads(await asyncio.wait_for(websocket.recv(), 5))
            self.assertTrue(result["success"])

            # sim 模式下命令 ack 成功
            await websocket.send(json.dumps({"type": "command", "command": "forward", "params": {"speed": 1.0}}))
            ack = json.loads(await asyncio.wait_for(websocket.recv(), 5))
            while ack.get("type") != "ack":
                ack = json.loads(await asyncio.wait_for(websocket.recv(), 5))
            self.assertTrue(ack["success"])

    def test_ui_websocket_flow(self) -> None:
        asyncio.run(self._ui_flow())


class RdkBridgeIntegrationTest(unittest.TestCase):
    """backend(rdk) 连上假 RDK X5 后，视频与遥测能转发到 UI。"""

    @classmethod
    def setUpClass(cls) -> None:
        cls.rdk_server = subprocess.Popen(
            [sys.executable, "-c", "import asyncio, sys; sys.path.insert(0, r'.'); from fake_rdk_gateway import main; asyncio.run(main(18080))"],
            cwd=str(Path(__file__).resolve().parent),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        env = os.environ.copy()
        env["ROV_BACKEND_MODE"] = "rdk"
        env["ROV_RDK_HOST"] = "127.0.0.1"
        env["ROV_RDK_PORT"] = "18080"
        env["ROV_WS_PORT"] = "18766"
        env["ROV_API_PORT"] = "15001"
        env["ROV_DB_PATH"] = str(BACKEND_DIR / "data" / "test_rdk.sqlite3")
        cls.process = subprocess.Popen(
            [sys.executable, str(APP_PY)],
            cwd=str(BACKEND_DIR),
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        wait_http("http://127.0.0.1:15001/api/health")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.process.terminate()
        cls.process.wait(timeout=5)
        cls.rdk_server.terminate()
        cls.rdk_server.wait(timeout=5)

    async def _flow(self) -> None:
        async with websockets.connect("ws://127.0.0.1:18766") as websocket:
            await websocket.recv()  # hello
            seen_frame = False
            seen_status = False
            deadline = time.time() + 10
            while time.time() < deadline and not (seen_frame and seen_status):
                message = json.loads(await asyncio.wait_for(websocket.recv(), 5))
                if message.get("type") == "frame":
                    seen_frame = True
                if message.get("type") == "status":
                    seen_status = True
                    if message["data"]["rdk"]["connected"]:
                        self.assertEqual(message["data"]["rdk"]["host"], "127.0.0.1")
            self.assertTrue(seen_frame)
            self.assertTrue(seen_status)

            # 登录后取遥测应能看到传感器数据
            status, login = http_json("POST", "http://127.0.0.1:15001/api/login", {"username": "zmm", "password": "Zmm771023"})
            self.assertEqual(status, 200)
            await websocket.send(json.dumps({"type": "get_telemetry"}))
            await asyncio.sleep(0.5)

            # 传感器数据库应有假网关的数据（遥测回调触发）
            status, sensors = http_json("GET", "http://127.0.0.1:15001/api/sensors", token=login["token"])
            self.assertEqual(status, 200)
            names = [row["name"] for row in sensors["data"]]
            self.assertIn("ms5837_depth.depth_m", names)

    def test_rdk_bridge_flow(self) -> None:
        asyncio.run(self._flow())


if __name__ == "__main__":
    unittest.main()
