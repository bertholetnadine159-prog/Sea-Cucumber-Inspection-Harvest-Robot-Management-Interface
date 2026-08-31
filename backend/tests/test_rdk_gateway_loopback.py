"""真 RDK X5 网关代码回环测试（PC 上以仿真模式运行 rdkx5/gateway.py）。

验证：真实的 rdkx5/gateway.py + stream_server.py + sensors.py + vision.py
（仿真路径）能正常启动，向后端推视频帧与传感器遥测，并响应控制命令。
不依赖任何硬件；MIPI/BPU/pymavlink 实机路径由 rdkx5/check_hardware.py 验证。
"""

import asyncio
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

import yaml
import websockets

try:
    from test_integration import http_json, wait_http
except ImportError:  # 以 tests 包方式导入时
    from tests.test_integration import http_json, wait_http


BACKEND_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_DIR.parent
RDKX5_DIR = REPO_ROOT / "rdkx5"
APP_PY = BACKEND_DIR / "app.py"


def wait_tcp(host: str, port: int, timeout: float = 15.0) -> None:
    import socket

    deadline = time.time() + timeout
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            with socket.create_connection((host, port), timeout=2):
                return
        except OSError as exc:  # noqa: BLE001
            last_error = exc
            time.sleep(0.2)
    raise RuntimeError(f"tcp {host}:{port} not ready ({last_error})")


class RdkGatewayLoopbackTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp_dir = tempfile.TemporaryDirectory()
        cls.gateway_config = Path(cls.tmp_dir.name) / "config_loopback.yaml"
        config = yaml.safe_load((RDKX5_DIR / "config.yaml").read_text(encoding="utf-8"))
        config.setdefault("server", {})["port"] = 18090
        cls.gateway_config.write_text(yaml.safe_dump(config), encoding="utf-8")

        cls.gateway = subprocess.Popen(
            [sys.executable, str(RDKX5_DIR / "gateway.py"), "--config", str(cls.gateway_config), "--simulate"],
            cwd=str(RDKX5_DIR),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        wait_tcp("127.0.0.1", 18090)

        env = os.environ.copy()
        env["ROV_BACKEND_MODE"] = "rdk"
        env["ROV_RDK_HOST"] = "127.0.0.1"
        env["ROV_RDK_PORT"] = "18090"
        env["ROV_WS_PORT"] = "18767"
        env["ROV_API_PORT"] = "15002"
        env["ROV_DB_PATH"] = str(Path(cls.tmp_dir.name) / "test_loopback.sqlite3")
        cls.backend = subprocess.Popen(
            [sys.executable, str(APP_PY)],
            cwd=str(BACKEND_DIR),
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        wait_http("http://127.0.0.1:15002/api/health")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.backend.terminate()
        cls.backend.wait(timeout=5)
        cls.gateway.terminate()
        cls.gateway.wait(timeout=5)
        cls.tmp_dir.cleanup()

    async def _flow(self) -> None:
        seen_frame = False
        seen_sensors = False
        rdk_connected = False
        ack_ok = False

        async with websockets.connect("ws://127.0.0.1:18767") as websocket:
            deadline = time.time() + 25
            # 先等 RDK 链路建立
            while time.time() < deadline:
                message = json.loads(await asyncio.wait_for(websocket.recv(), 10))
                mtype = message.get("type")
                if mtype == "frame":
                    seen_frame = True
                    self.assertIn("data", message)
                elif mtype == "sensors":
                    seen_sensors = True
                    self.assertIn("ms5837_depth", message.get("data", {}))
                elif mtype == "status":
                    rdk_connected = bool(message.get("data", {}).get("rdk", {}).get("connected"))
                if seen_frame and seen_sensors and rdk_connected:
                    break

            self.assertTrue(seen_frame, "no video frame relayed from real RDK gateway")
            self.assertTrue(seen_sensors, "no sensor telemetry relayed from real RDK gateway")
            self.assertTrue(rdk_connected, "backend did not connect to RDK gateway")

            # 控制命令经后端转发到真实网关，网关应回 ack success
            await websocket.send(json.dumps({
                "type": "command",
                "command": "forward",
                "token": "",
                "speed": 0.6,
            }))
            deadline = time.time() + 8
            while time.time() < deadline:
                message = json.loads(await asyncio.wait_for(websocket.recv(), 10))
                if message.get("type") == "ack" and message.get("command") == "move":
                    ack_ok = bool(message.get("success"))
                    break
            self.assertTrue(ack_ok, "move command was not acknowledged by RDK gateway")

        # 遥测应已落库（网关遥测 source 默认 rdk_x5）
        status, login = http_json("POST", "http://127.0.0.1:15002/api/login", {"username": "zmm", "password": "Zmm771023"})
        self.assertEqual(status, 200)
        status, sensors = http_json("GET", "http://127.0.0.1:15002/api/sensors", token=login["token"])
        self.assertEqual(status, 200)
        names = [row["name"] for row in sensors["data"]]
        self.assertIn("ms5837_depth.depth_m", names)

    def test_real_rdk_gateway_loopback(self) -> None:
        asyncio.run(self._flow())


if __name__ == "__main__":
    unittest.main()
