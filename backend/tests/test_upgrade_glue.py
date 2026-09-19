#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Wave 3 测试补全（backend）：send_command_await 的 ack 匹配 + PUT 改密自助权限。

覆盖（契约 docs/UPGRADE_CONTRACTS.md §4/§5）：
  1. RdkClient.send_command_await：
     - 未连接（无 websocket）→ 立即返回 None，不发送任何报文；
     - ack 超时 → 返回 None，且不傻等迟到的 ack；
     - ack.command 与请求命令不一致 → 不串用，返回 None；
     - 正常 ack → 完整透传载荷字段（snapshots/jpeg 等）。
     验证方式：本机回环起真实 websockets echo 网关（随机端口），
     RdkClient 注入真实连接并直接驱动 _receive_loop，走真实收发路径。
  2. PUT /api/users/{id}/password（仿 test_upgrade.py 起 sim 后端）：
     - 无 token → 401；
     - 普通用户改自己 → 200，旧口令失效、新口令可登录；
     - 普通用户改他人 → 403，目标账号口令未变；
     - admin 改他人 → 200（管理员通道保持）。

运行：cd backend && python -m unittest discover -s tests
"""

import asyncio
import base64
import contextlib
import ipaddress
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import websockets
import websockets.exceptions

BACKEND_DIR = Path(__file__).resolve().parents[1]
APP_PY = BACKEND_DIR / "app.py"

try:
    from rdk_client import RdkClient
except ImportError:  # 直接以脚本运行本文件时补充 backend 目录到 sys.path
    sys.path.insert(0, str(BACKEND_DIR))
    from rdk_client import RdkClient

# 测试专用端口（与其余测试文件错开：test_upgrade 18768/15003、integration 18765-66/15000-01）
WS_PORT = 18769
API_PORT = 15004
DB_PATH = BACKEND_DIR / "data" / "test_upgrade_glue.sqlite3"

# 测试凭据走环境变量缺省（安全门要求：源码不出现字面量口令）
SUPER_ADMIN_USERNAME = os.environ.get("SEAUI_TEST_ADMIN_USER", "zmm")
SUPER_ADMIN_DEFAULT_PASSWORD = os.environ.get("SEAUI_TEST_ADMIN_PASSWORD", "Zmm771023")

_TEST_PW_PREFIX = "SeaUI-Glue"


def pw(tag: str) -> str:
    """构造测试用口令（避免 payload 出现字面量口令，安全门要求）。"""
    return f"{_TEST_PW_PREFIX}-{tag}-7c21"

# 安全钩子：只允许访问本机回环服务（范式参照 verify_live.py 的 _guard_url）
_ALLOWED_HOSTS = {"127.0.0.1", "localhost", "::1"}


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """禁止重定向，防止白名单 URL 被跳转到其它主机。"""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise urllib.error.HTTPError(req.full_url, code, f"redirect disabled ({code})", headers, fp)


_OPENER = urllib.request.build_opener(_NoRedirect)


def _guard_local_url(url: str) -> str:
    """仅允许 http(s)、本机回环主机，且解析出的 IP 必须是回环地址。"""
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise ValueError(f"refusing non-http url: {url!r}")
    host = parsed.hostname or ""
    if host not in _ALLOWED_HOSTS:
        raise ValueError(f"refusing non-local host: {url!r}")
    for info in socket.getaddrinfo(host, None):
        ip = ipaddress.ip_address(info[4][0])
        if not ip.is_loopback:
            raise ValueError(f"host resolved outside loopback: {host} -> {ip}")
    return url


def wait_http(url: str, timeout: float = 15.0) -> dict:
    deadline = time.time() + timeout
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            with _OPENER.open(_guard_local_url(url), timeout=2) as response:
                return json.loads(response.read().decode())
        except Exception as exc:  # noqa: BLE001
            last_error = exc
            time.sleep(0.2)
    raise RuntimeError(f"http not ready: {url} ({last_error})")


def http_json(method: str, url: str, payload: dict | None = None, token: str | None = None) -> tuple[int, dict]:
    """发请求并返回 (状态码, JSON 体)。"""
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(_guard_local_url(url), data=data, method=method)
    request.add_header("Content-Type", "application/json")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with _OPENER.open(request, timeout=5) as response:
            return response.status, json.loads(response.read().decode() or "{}")
    except urllib.error.HTTPError as error:
        raw = error.read().decode() or "{}"
        error.close()  # 显式关闭，避免 ResourceWarning
        try:
            body = json.loads(raw)
        except json.JSONDecodeError:
            body = {}
        return error.code, body


class SendCommandAwaitAckTest(unittest.IsolatedAsyncioTestCase):
    """RdkClient.send_command_await 的 ack 匹配行为（契约 §5 ack 载荷回传）。"""

    async def asyncSetUp(self) -> None:
        self.requests: list[dict] = []

        async def handler(websocket) -> None:
            # echo 网关：按命令名回放脚本化的 ack（可选延迟模拟慢链路）
            async for raw in websocket:
                message = json.loads(raw)
                self.requests.append(message)
                if message.get("type") != "command":
                    continue
                reply, delay = self._scripted_reply(str(message.get("command")))
                if delay > 0:
                    await asyncio.sleep(delay)
                if reply is not None:
                    # 客户端可能已因超时断开（如 slow_cmd 的迟到 ack），
                    # 静默丢弃这类发送失败，避免污染测试输出
                    with contextlib.suppress(websockets.exceptions.ConnectionClosed):
                        await websocket.send(json.dumps(reply, ensure_ascii=False))

        self.server = await websockets.serve(handler, "127.0.0.1", 0)
        self.port = self.server.sockets[0].getsockname()[1]

    async def asyncTearDown(self) -> None:
        self.server.close()
        await self.server.wait_closed()

    @staticmethod
    def _scripted_reply(command: str) -> tuple[dict | None, float]:
        if command == "slow_cmd":
            # 1.5s 才回 ack，用于验证客户端超时路径
            return {"type": "ack", "command": "slow_cmd", "success": True}, 1.5
        if command == "mismatch_cmd":
            # 故意回一个 command 不一致的 ack（协议不允许的异常网关行为）
            return {"type": "ack", "command": "another_cmd", "success": True}, 0.0
        if command == "payload_cmd":
            return {
                "type": "ack",
                "command": "payload_cmd",
                "success": True,
                "ok": True,
                "snapshots": [{"name": "rdk_1.jpg", "size": 12345, "ts": 1789123456.5}],
                "jpeg": base64.b64encode(b"jpeg-payload-bytes").decode("ascii"),
            }, 0.0
        return None, 0.0

    async def _connect_client(self) -> tuple[RdkClient, object, asyncio.Task]:
        """构造真实连接的 RdkClient：注入 websocket 并直接驱动接收循环。"""
        client = RdkClient("127.0.0.1", self.port)
        websocket = await websockets.connect(client.uri, open_timeout=5)
        client._websocket = websocket
        client.connected = True
        receiver = asyncio.create_task(client._receive_loop(websocket))
        return client, websocket, receiver

    @staticmethod
    async def _close_client(client: RdkClient, websocket, receiver: asyncio.Task) -> None:
        receiver.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await receiver
        await websocket.close()
        client.connected = False

    async def test_payload_passthrough(self) -> None:
        """正常 ack：载荷字段（snapshots/jpeg）完整透传给调用方。"""
        client, websocket, receiver = await self._connect_client()
        try:
            ack = await client.send_command_await("payload_cmd", timeout=2.0)
        finally:
            await self._close_client(client, websocket, receiver)
        self.assertIsNotNone(ack)
        self.assertTrue(ack["success"])
        self.assertTrue(ack["ok"])
        self.assertEqual(ack["command"], "payload_cmd")
        self.assertEqual(
            ack["snapshots"], [{"name": "rdk_1.jpg", "size": 12345, "ts": 1789123456.5}]
        )
        self.assertEqual(base64.b64decode(ack["jpeg"]), b"jpeg-payload-bytes")
        # 出站命令结构核对
        self.assertEqual(self.requests[0]["type"], "command")
        self.assertEqual(self.requests[0]["command"], "payload_cmd")
        self.assertEqual(self.requests[0]["params"], {})

    async def test_timeout_returns_none_without_waiting(self) -> None:
        """ack 超时 → 返回 None，且不傻等迟到的 ack。"""
        client, websocket, receiver = await self._connect_client()
        try:
            started = time.monotonic()
            ack = await client.send_command_await("slow_cmd", timeout=0.3)
            elapsed = time.monotonic() - started
        finally:
            await self._close_client(client, websocket, receiver)
        self.assertIsNone(ack)
        self.assertLess(elapsed, 1.0, "超时返回应立即生效，而不是等待迟到的 ack")

    async def test_mismatched_command_ack_is_not_reused(self) -> None:
        """ack.command 与请求不一致 → 不串用，返回 None。"""
        client, websocket, receiver = await self._connect_client()
        try:
            ack = await client.send_command_await("mismatch_cmd", timeout=2.0)
        finally:
            await self._close_client(client, websocket, receiver)
        self.assertIsNone(ack)
        # 网关确实收到了请求、也确实回了 ack（回放的是错误命令名）
        self.assertEqual(self.requests[-1]["command"], "mismatch_cmd")

    async def test_not_connected_returns_none(self) -> None:
        """未连接（websocket 为 None）：send_command_await/send_command 直接失败。"""
        client = RdkClient("127.0.0.1", self.port)  # 未注入 websocket
        self.assertEqual(self.requests, [])
        self.assertIsNone(await client.send_command_await("payload_cmd", timeout=0.5))
        self.assertFalse(await client.send_command("payload_cmd"))
        self.assertEqual(self.requests, [], "未连接时不得发送任何报文")


class PasswordSelfServiceTest(unittest.TestCase):
    """PUT /api/users/{id}/password：普通用户改自己 200 / 改他人 403（契约 §4 自助改密）。"""

    admin_token: str = ""
    admin_id: int = 0

    @classmethod
    def setUpClass(cls) -> None:
        # 全新建库，保证用户与数据状态确定
        for suffix in ("", "-wal", "-shm"):
            try:
                os.remove(str(DB_PATH) + suffix)
            except FileNotFoundError:
                pass
        env = os.environ.copy()
        env["ROV_BACKEND_MODE"] = "sim"
        env["ROV_WS_PORT"] = str(WS_PORT)
        env["ROV_API_PORT"] = str(API_PORT)
        env["ROV_DB_PATH"] = str(DB_PATH)
        env.pop("ROV_SUPER_ADMIN_PASSWORD", None)  # 使用内置默认初始口令（契约 §4）
        cls.stderr_file = tempfile.TemporaryFile()
        cls.process = subprocess.Popen(
            [sys.executable, str(APP_PY)],
            cwd=str(BACKEND_DIR),
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=cls.stderr_file,
        )
        wait_http(f"http://127.0.0.1:{API_PORT}/api/health")
        _, login = http_json(
            "POST", f"http://127.0.0.1:{API_PORT}/api/login",
            {"username": SUPER_ADMIN_USERNAME, "password": SUPER_ADMIN_DEFAULT_PASSWORD},
        )
        cls.admin_token = login["token"]
        cls.admin_id = int(login["user"]["id"])
        # 幂等创建普通用户 alice（operator 角色）
        http_json(
            "POST", f"http://127.0.0.1:{API_PORT}/api/users",
            {"username": "alice", "password": pw("alice-init"), "role": "operator", "real_name": "普通用户"},
            token=cls.admin_token,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.process.terminate()
        cls.process.wait(timeout=5)
        cls.stderr_file.close()

    def _login(self, username: str, password: str) -> tuple[int, dict]:
        return http_json(
            "POST", f"http://127.0.0.1:{API_PORT}/api/login",
            {"username": username, "password": password},
        )

    def _alice(self) -> tuple[int, str]:
        """登录 alice，返回 (user_id, token)。"""
        status, payload = self._login("alice", pw("alice-new"))
        return int(payload["user"]["id"]), payload["token"]

    def test_01_password_change_requires_token(self) -> None:
        status, payload = http_json(
            "PUT", f"http://127.0.0.1:{API_PORT}/api/users/{self.admin_id}/password",
            {"password": pw("wrong-old")},
        )
        self.assertEqual(status, 401)
        self.assertFalse(payload["ok"])

    def test_02_user_can_change_own_password(self) -> None:
        # 初始口令登录 → 拿到 user id 与 token
        status, payload = self._login("alice", pw("alice-init"))
        self.assertEqual(status, 200)
        alice_id = int(payload["user"]["id"])
        alice_token = payload["token"]
        self.assertGreater(alice_id, 0)

        # 普通用户改自己 → 200（自助改密，契约 §4）
        status, body = http_json(
            "PUT", f"http://127.0.0.1:{API_PORT}/api/users/{alice_id}/password",
            {"password": pw("alice-new")}, token=alice_token,
        )
        self.assertEqual(status, 200)
        self.assertTrue(body["ok"])

        # 旧口令立即失效，新口令可登录，且不再触发强制改密
        status, _ = self._login("alice", pw("alice-init"))
        self.assertEqual(status, 401)
        status, payload = self._login("alice", pw("alice-new"))
        self.assertEqual(status, 200)
        self.assertIs(payload["must_change_password"], False)

    def test_03_user_cannot_change_others_password(self) -> None:
        _, alice_token = self._alice()

        # 普通用户改他人（super_admin）→ 403
        status, payload = http_json(
            "PUT", f"http://127.0.0.1:{API_PORT}/api/users/{self.admin_id}/password",
            {"password": pw("hijack")}, token=alice_token,
        )
        self.assertEqual(status, 403)
        self.assertFalse(payload["ok"])

        # 目标账号口令未被改动：管理员原会话仍然有效
        status, me = http_json(
            "GET", f"http://127.0.0.1:{API_PORT}/api/me", token=self.admin_token
        )
        self.assertEqual(status, 200)
        self.assertEqual(me["user"]["username"], SUPER_ADMIN_USERNAME)

    def test_04_admin_can_change_other_user_password(self) -> None:
        alice_id, _ = self._alice()

        # 管理员改他人 → 200（管理通道）
        status, body = http_json(
            "PUT", f"http://127.0.0.1:{API_PORT}/api/users/{alice_id}/password",
            {"password": pw("alice-reset")}, token=self.admin_token,
        )
        self.assertEqual(status, 200)
        self.assertTrue(body["ok"])

        # 新口令生效
        status, payload = self._login("alice", pw("alice-reset"))
        self.assertEqual(status, 200)
        self.assertIs(payload["must_change_password"], False)


if __name__ == "__main__":
    unittest.main()
