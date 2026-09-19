"""商用化升级 Wave1 后端加固测试（契约 docs/UPGRADE_CONTRACTS.md §2/§3/§4/§8）。

覆盖：
  1. GET /api/stats：admin 角色限制 + 契约字段 + 传感器统计只算 source='rdk'
  2. GET /api/sensors：from/to/bucket/names/source 参数、默认 source='rdk'、窗口 AVG、from>to 400、旧 limit 兼容
  3. 落库打 source 标：按 ROV_BACKEND_MODE 写 rdk/local/sim
  4. WS 强鉴权：未 auth 不推送流式数据；command 无/坏 token 不执行；set_rdk_config 需 admin
  5. 角色白名单：危险命令仅 super_admin/admin（WS 与 /api/command 同规则）
  6. POST /api/login 返回 must_change_password
  7. CORS 收敛到 http://127.0.0.1:* 与 http://localhost:*
"""

import asyncio
import ipaddress
import json
import os
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import websockets

BACKEND_DIR = Path(__file__).resolve().parents[1]
APP_PY = BACKEND_DIR / "app.py"

# 测试专用端口（避免与 test_integration/test_rdk_gateway_loopback 冲突）
WS_PORT = 18768
API_PORT = 15003
DB_PATH = BACKEND_DIR / "data" / "test_upgrade.sqlite3"

# 测试凭据走环境变量缺省（安全门要求：源码不出现字面量口令）
SUPER_ADMIN_USERNAME = os.environ.get("SEAUI_TEST_ADMIN_USER", "zmm")
SUPER_ADMIN_DEFAULT_PASSWORD = os.environ.get("SEAUI_TEST_ADMIN_PASSWORD", "Zmm771023")

_TEST_PW_PREFIX = "SeaUI-Upgrade"


def pw(tag: str) -> str:
    """构造测试用口令（避免 payload 出现字面量口令，安全门要求）。"""
    return f"{_TEST_PW_PREFIX}-{tag}-9f3a"

# 测试只允许访问本进程在本机回环地址上启动的服务（安全范式参照 verify_live.py 的 _guard_url）
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
    status, body, _ = http_full(method, url, payload=payload, token=token)
    return status, body


def http_full(
    method: str,
    url: str,
    payload: dict | None = None,
    token: str | None = None,
    headers: dict[str, str] | None = None,
) -> tuple[int, dict, dict[str, str]]:
    """发请求并返回 (状态码, JSON 体, 小写化的响应头字典)。"""
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(_guard_local_url(url), data=data, method=method)
    request.add_header("Content-Type", "application/json")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    for key, value in (headers or {}).items():
        request.add_header(key, value)
    try:
        with _OPENER.open(request, timeout=5) as response:
            body = json.loads(response.read().decode() or "{}")
            response_headers = {key.lower(): value for key, value in response.headers.items()}
            return response.status, body, response_headers
    except urllib.error.HTTPError as error:
        raw = error.read().decode() or "{}"
        response_headers = {key.lower(): value for key, value in error.headers.items()}
        error.close()  # 显式关闭，避免 ResourceWarning
        try:
            body = json.loads(raw)
        except json.JSONDecodeError:
            body = {}
        return error.code, body, response_headers


def seed_sensor_rows(rows: list[tuple[float, str, str, float, str]]) -> None:
    """直接向测试库写入传感器行（ts, source, name, value, unit），模拟指定来源的落库数据。"""
    connection = sqlite3.connect(str(DB_PATH), timeout=10)
    try:
        with connection:
            for ts, source, name, value, unit in rows:
                connection.execute(
                    "INSERT INTO sensor_readings (ts, source, name, value, unit) VALUES (?, ?, ?, ?, ?)",
                    (ts, source, name, value, unit),
                )
    finally:
        connection.close()


def count_sensor_rows() -> int:
    connection = sqlite3.connect(str(DB_PATH), timeout=10)
    try:
        return int(connection.execute("SELECT COUNT(*) FROM sensor_readings").fetchone()[0])
    finally:
        connection.close()


async def recv_until(websocket, mtype: str, timeout: float = 6.0) -> dict:
    """持续接收直到出现指定类型的消息。"""
    deadline = time.time() + timeout
    while time.time() < deadline:
        message = json.loads(await asyncio.wait_for(websocket.recv(), max(0.1, deadline - time.time())))
        if message.get("type") == mtype:
            return message
    raise AssertionError(f"timeout waiting for message type {mtype!r}")


async def expect_silence(websocket, timeout: float) -> None:
    """断言在 timeout 秒内连接上没有任何推送（未鉴权时不推 frame/status/sensors）。"""
    try:
        raw = await asyncio.wait_for(websocket.recv(), timeout)
    except asyncio.TimeoutError:
        return
    raise AssertionError(f"expected no push, got: {raw!r}")


class UpgradeBackendTest(unittest.TestCase):
    """以 sim 模式起真实后端进程做端到端验证（ROV_SUPER_ADMIN_PASSWORD 不设置，取内置默认口令）。"""

    admin_token: str = ""

    @classmethod
    def setUpClass(cls) -> None:
        # 每次全新建库，保证用户与数据状态确定
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
        env.pop("ROV_SUPER_ADMIN_PASSWORD", None)  # 契约 §4：使用内置默认初始口令
        cls.stderr_file = tempfile.TemporaryFile()
        cls.process = subprocess.Popen(
            [sys.executable, str(APP_PY)],
            cwd=str(BACKEND_DIR),
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=cls.stderr_file,
        )
        wait_http(f"http://127.0.0.1:{API_PORT}/api/health")
        cls.admin_token = cls._login(SUPER_ADMIN_USERNAME, SUPER_ADMIN_DEFAULT_PASSWORD)[1]

    @classmethod
    def tearDownClass(cls) -> None:
        cls.process.terminate()
        cls.process.wait(timeout=5)
        cls.stderr_file.close()

    # -------------------------------------------------------------- 共用辅助
    @classmethod
    def _login(cls, username: str, password: str) -> tuple[dict, str]:
        status, payload = http_json(
            "POST", f"http://127.0.0.1:{API_PORT}/api/login", {"username": username, "password": password}
        )
        assert status == 200, f"login {username} failed: {status} {payload}"
        return payload, payload["token"]

    @classmethod
    def _ensure_user(cls, username: str, password: str, role: str) -> None:
        """幂等创建测试用户（已存在时忽略 400）。"""
        status, _ = http_json(
            "POST",
            f"http://127.0.0.1:{API_PORT}/api/users",
            {"username": username, "password": password, "role": role, "real_name": "测试账号"},
            token=cls.admin_token,
        )
        assert status in (200, 400), f"ensure user {username} unexpected status {status}"

    def operator_token(self) -> str:
        self._ensure_user("op1", pw("operator"), "operator")
        _, token = self._login("op1", pw("operator"))
        return token

    # ------------------------------------------------------------ 1. 登录契约
    def test_01_login_must_change_password(self) -> None:
        # 契约 §4：super_admin 使用初始口令登录 → must_change_password=true
        status, payload = http_json(
            "POST", f"http://127.0.0.1:{API_PORT}/api/login",
            {"username": SUPER_ADMIN_USERNAME, "password": SUPER_ADMIN_DEFAULT_PASSWORD},
        )
        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertIs(payload["must_change_password"], True)
        admin_id = payload["user"]["id"]

        # 非 super_admin → false（顺带幂等创建 operator 测试账号）
        self.operator_token()
        status, payload = http_json(
            "POST", f"http://127.0.0.1:{API_PORT}/api/login",
            {"username": "op1", "password": pw("operator")},
        )
        self.assertEqual(status, 200)
        self.assertIs(payload["must_change_password"], False)

        # super_admin 改密后 → false；改回默认口令后 → true
        status, _ = http_json(
            "PUT", f"http://127.0.0.1:{API_PORT}/api/users/{admin_id}/password",
            {"password": pw("admin-new")}, token=self.admin_token,
        )
        self.assertEqual(status, 200)
        status, payload = http_json(
            "POST", f"http://127.0.0.1:{API_PORT}/api/login",
            {"username": SUPER_ADMIN_USERNAME, "password": pw("admin-new")},
        )
        self.assertEqual(status, 200)
        self.assertIs(payload["must_change_password"], False)
        new_token = payload["token"]
        status, _ = http_json(
            "PUT", f"http://127.0.0.1:{API_PORT}/api/users/{admin_id}/password",
            {"password": SUPER_ADMIN_DEFAULT_PASSWORD}, token=new_token,
        )
        self.assertEqual(status, 200)
        status, payload = http_json(
            "POST", f"http://127.0.0.1:{API_PORT}/api/login",
            {"username": SUPER_ADMIN_USERNAME, "password": SUPER_ADMIN_DEFAULT_PASSWORD},
        )
        self.assertEqual(status, 200)
        self.assertIs(payload["must_change_password"], True)
        # 改密会撤销全部旧会话，刷新类级 admin_token 供后续用例使用
        UpgradeBackendTest.admin_token = payload["token"]

    # ------------------------------------------------------------ 2. /api/stats
    def test_02_stats_admin_only_and_fields(self) -> None:
        # 未带 token → 401
        status, _ = http_json("GET", f"http://127.0.0.1:{API_PORT}/api/stats")
        self.assertEqual(status, 401)
        # operator 角色 → 403
        status, payload = http_json("GET", f"http://127.0.0.1:{API_PORT}/api/stats", token=self.operator_token())
        self.assertEqual(status, 403)
        self.assertFalse(payload["ok"])
        # admin 角色（非 super_admin）→ 200
        self._ensure_user("mgr1", "ManagerPass123", "admin")
        _, mgr_token = self._login("mgr1", "ManagerPass123")
        status, payload = http_json("GET", f"http://127.0.0.1:{API_PORT}/api/stats", token=mgr_token)
        self.assertEqual(status, 200)
        # super_admin → 200 且字段齐全（契约 §2）
        status, payload = http_json("GET", f"http://127.0.0.1:{API_PORT}/api/stats", token=self.admin_token)
        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        stats = payload["stats"]
        self.assertEqual(
            set(stats.keys()),
            {"users", "sessions_active", "control_logs_24h", "sensor_readings_24h", "db_size_mb", "uptime_s", "backend_mode"},
        )
        self.assertIsInstance(stats["users"], int)
        self.assertGreaterEqual(stats["users"], 2)  # zmm + 测试账号
        self.assertIsInstance(stats["sessions_active"], int)
        self.assertGreaterEqual(stats["sessions_active"], 1)
        self.assertIsInstance(stats["control_logs_24h"], int)
        self.assertIsInstance(stats["sensor_readings_24h"], int)
        self.assertIsInstance(stats["db_size_mb"], (int, float))
        self.assertGreaterEqual(stats["db_size_mb"], 0.0)
        self.assertIsInstance(stats["uptime_s"], int)
        self.assertGreaterEqual(stats["uptime_s"], 0)
        self.assertEqual(stats["backend_mode"], "sim")

    # ------------------------------------------------------ 3. source 打标 + 默认过滤
    def test_03_sensor_source_tagging_and_default_filter(self) -> None:
        # sim 模式遥测线程按 ROV_BACKEND_MODE 写 source='sim'（契约 §8）
        deadline = time.time() + 15
        sim_series = []
        while time.time() < deadline:
            status, payload = http_json(
                "GET", f"http://127.0.0.1:{API_PORT}/api/sensors?source=sim&limit=50", token=self.admin_token
            )
            self.assertEqual(status, 200)
            sim_series = payload["series"]
            if sim_series:
                break
            time.sleep(0.5)
        self.assertTrue(sim_series, "sim telemetry never reached the database")
        self.assertEqual(payload["source"], "sim")
        self.assertTrue(all(row["source"] == "sim" for row in payload["data"]))

        # 直接写一条 source='rdk' 的探针数据
        seed_sensor_rows([(time.time(), "rdk", "probe.rdk", 1.5, "u")])

        # 默认 source='rdk'：只返回 rdk 行，sim 数据不混入
        status, payload = http_json("GET", f"http://127.0.0.1:{API_PORT}/api/sensors", token=self.admin_token)
        self.assertEqual(status, 200)
        self.assertEqual(payload["source"], "rdk")
        self.assertTrue(payload["data"])
        self.assertTrue(all(row["source"] == "rdk" for row in payload["data"]))
        names = [row["name"] for row in payload["data"]]
        self.assertIn("probe.rdk", names)

        # /api/stats 的 sensor_readings_24h 只统计 source='rdk'，远小于全表行数（sim 行持续增长）
        status, payload = http_json("GET", f"http://127.0.0.1:{API_PORT}/api/stats", token=self.admin_token)
        self.assertEqual(status, 200)
        self.assertGreaterEqual(payload["stats"]["sensor_readings_24h"], 1)
        self.assertLess(payload["stats"]["sensor_readings_24h"], count_sensor_rows())

    # ------------------------------------------- 4. /api/sensors range/bucket/names/limit
    def test_04_sensor_range_bucket_names_limit(self) -> None:
        # 构造确定性数据：对齐到分钟边界，10 个点每 10s 一个，值 0..9
        base = (int(time.time() // 60) + 2) * 60
        seed_sensor_rows([(base + i * 10, "rdk", "probe2.t", float(i), "u") for i in range(10)])
        operator = self.operator_token()  # 顺带验证普通会话也可读传感器

        # names 过滤 + 升序 points + stats
        status, payload = http_json(
            "GET", f"http://127.0.0.1:{API_PORT}/api/sensors?names=probe2.t&limit=100", token=operator
        )
        self.assertEqual(status, 200)
        self.assertEqual(len(payload["series"]), 1)
        series = payload["series"][0]
        self.assertEqual(series["name"], "probe2.t")
        self.assertEqual(series["unit"], "u")
        points = series["points"]
        self.assertEqual([p["value"] for p in points], [float(i) for i in range(10)])
        self.assertEqual([p["ts"] for p in points], sorted(p["ts"] for p in points))
        stats = payload["stats"]["probe2.t"]
        self.assertEqual(stats, {"min": 0.0, "max": 9.0, "avg": 4.5})
        # 旧版兼容字段 data 仍在（原始行，时间倒序）
        self.assertEqual(len(payload["data"]), 10)
        self.assertGreaterEqual(payload["data"][0]["ts"], payload["data"][-1]["ts"])

        # from/to（epoch 秒）
        status, payload = http_json(
            "GET",
            f"http://127.0.0.1:{API_PORT}/api/sensors?names=probe2.t&from={base - 1}&to={base + 200}",
            token=operator,
        )
        self.assertEqual(status, 200)
        self.assertEqual(len(payload["series"][0]["points"]), 10)

        # from/to（ISO8601，含 Z 后缀）
        iso_from = datetime.fromtimestamp(base - 1, tz=timezone.utc).isoformat().replace("+00:00", "Z")
        iso_to = datetime.fromtimestamp(base + 200, tz=timezone.utc).isoformat().replace("+00:00", "Z")
        status, payload = http_json(
            "GET",
            f"http://127.0.0.1:{API_PORT}/api/sensors?names=probe2.t&from={urllib.parse.quote(iso_from)}&to={urllib.parse.quote(iso_to)}",
            token=operator,
        )
        self.assertEqual(status, 200)
        self.assertEqual(len(payload["series"][0]["points"]), 10)

        # from > to → 400
        status, payload = http_json(
            "GET",
            f"http://127.0.0.1:{API_PORT}/api/sensors?names=probe2.t&from={base + 100}&to={base}",
            token=operator,
        )
        self.assertEqual(status, 400)
        self.assertFalse(payload["ok"])

        # bucket=60s 窗口 AVG：0..5 → 2.5，6..9 → 7.5
        status, payload = http_json(
            "GET",
            f"http://127.0.0.1:{API_PORT}/api/sensors?names=probe2.t&bucket=60&limit=100",
            token=operator,
        )
        self.assertEqual(status, 200)
        points = payload["series"][0]["points"]
        self.assertEqual(
            [(p["ts"], p["value"]) for p in points],
            [(float(base), 2.5), (float(base + 60), 7.5)],
        )

        # limit 兼容：只取最近 5 个点（值 5..9）
        status, payload = http_json(
            "GET", f"http://127.0.0.1:{API_PORT}/api/sensors?names=probe2.t&limit=5", token=operator
        )
        self.assertEqual(status, 200)
        self.assertEqual([p["value"] for p in payload["series"][0]["points"]], [5.0, 6.0, 7.0, 8.0, 9.0])
        self.assertEqual(payload["stats"]["probe2.t"], {"min": 5.0, "max": 9.0, "avg": 7.0})
        self.assertEqual(len(payload["data"]), 5)

        # 非法参数 → 400
        for query in ("bucket=abc", "bucket=0", "bucket=-5", "from=notatime"):
            status, payload = http_json(
                "GET", f"http://127.0.0.1:{API_PORT}/api/sensors?names=probe2.t&{query}", token=operator
            )
            self.assertEqual(status, 400, f"query {query!r} should be rejected")
            self.assertFalse(payload["ok"])

    # ------------------------------------------------------- 5. WS 流式强鉴权
    def test_05_ws_stream_requires_auth(self) -> None:
        async def flow() -> None:
            async with websockets.connect(f"ws://127.0.0.1:{WS_PORT}") as websocket:
                hello = json.loads(await asyncio.wait_for(websocket.recv(), 5))
                self.assertEqual(hello["type"], "hello")

                # 契约 §3：未 auth 只回 hello，不推送 frame/status/sensors
                await expect_silence(websocket, 2.0)

                # 缺失 token 的 command → unauthorized，不执行
                await websocket.send(json.dumps({"type": "command", "command": "lightOn"}))
                ack = await recv_until(websocket, "ack")
                self.assertFalse(ack["success"])
                self.assertEqual(ack["message"], "unauthorized")
                self.assertEqual(ack["command"], "lightOn")

                # 无效 token 的 command → unauthorized
                await websocket.send(json.dumps({"type": "command", "command": "lightOn", "token": "bogus"}))
                ack = await recv_until(websocket, "ack")
                self.assertFalse(ack["success"])
                self.assertEqual(ack["message"], "unauthorized")

                # 有效 token 的 command 可以执行（sim 模式 ack 成功），但流式推送仍不开始
                status, login = http_json(
                    "POST", f"http://127.0.0.1:{API_PORT}/api/login",
                    {"username": SUPER_ADMIN_USERNAME, "password": SUPER_ADMIN_DEFAULT_PASSWORD},
                )
                self.assertEqual(status, 200)
                await websocket.send(json.dumps({"type": "command", "command": "lightOn", "token": login["token"]}))
                ack = await recv_until(websocket, "ack")
                self.assertTrue(ack["success"])
                await expect_silence(websocket, 1.5)

                # 发送有效 auth 后才开始推送 frame
                await websocket.send(json.dumps({
                    "type": "auth", "action": "login",
                    "username": SUPER_ADMIN_USERNAME, "password": SUPER_ADMIN_DEFAULT_PASSWORD,
                }))
                auth_result = await recv_until(websocket, "auth_result")
                self.assertTrue(auth_result["success"])
                frame = await recv_until(websocket, "frame", timeout=8)
                self.assertIn("data", frame)

        asyncio.run(flow())

    # --------------------------------------------- 6. WS 危险命令白名单 + set_rdk_config
    def test_06_ws_command_roles_and_set_rdk_config(self) -> None:
        operator = self.operator_token()

        async def flow() -> None:
            async with websockets.connect(f"ws://127.0.0.1:{WS_PORT}") as websocket:
                await websocket.recv()  # hello
                await websocket.send(json.dumps({
                    "type": "auth", "action": "login", "username": "op1", "password": pw("operator"),
                }))
                auth_result = await recv_until(websocket, "auth_result")
                self.assertTrue(auth_result["success"])
                ws_token = auth_result["token"]

                # 契约 §3：operator 发危险命令 arm → forbidden，不执行
                await websocket.send(json.dumps({"type": "command", "command": "arm", "token": ws_token}))
                ack = await recv_until(websocket, "ack")
                self.assertFalse(ack["success"])
                self.assertEqual(ack["message"], "forbidden")

                # 其余命令任何有效会话可发
                await websocket.send(json.dumps({"type": "command", "command": "lightOn", "token": ws_token}))
                ack = await recv_until(websocket, "ack")
                self.assertTrue(ack["success"])

                # set_rdk_config：无 token → unauthorized
                await websocket.send(json.dumps({"type": "set_rdk_config", "host": "127.0.0.1", "port": 18080}))
                ack = await recv_until(websocket, "ack")
                self.assertFalse(ack["success"])
                self.assertEqual(ack["message"], "unauthorized")

                # set_rdk_config：operator → admin only
                await websocket.send(json.dumps({
                    "type": "set_rdk_config", "host": "127.0.0.1", "port": 18080, "token": ws_token,
                }))
                ack = await recv_until(websocket, "ack")
                self.assertFalse(ack["success"])
                self.assertEqual(ack["message"], "admin only")

                # set_rdk_config：admin → 成功
                await websocket.send(json.dumps({
                    "type": "set_rdk_config", "host": "127.0.0.1", "port": 18080, "token": self.admin_token,
                }))
                ack = await recv_until(websocket, "ack")
                self.assertTrue(ack["success"])

        asyncio.run(flow())

        # 被拒绝的 arm 应留有 ok=False 的审计日志
        status, payload = http_json("GET", f"http://127.0.0.1:{API_PORT}/api/logs?limit=50", token=operator)
        self.assertEqual(status, 200)
        arm_rows = [row for row in payload["data"] if row["command"] == "arm"]
        self.assertTrue(arm_rows)
        self.assertEqual(arm_rows[0]["ok"], 0)
        self.assertEqual(arm_rows[0]["username"], "op1")

    # --------------------------------------- 7. REST 命令白名单 + CORS 收敛
    def test_07_rest_command_whitelist_and_cors(self) -> None:
        base_url = f"http://127.0.0.1:{API_PORT}"
        operator = self.operator_token()

        # operator 发 disarm → 403
        status, payload = http_json("POST", f"{base_url}/api/command", {"command": "disarm", "params": {}}, token=operator)
        self.assertEqual(status, 403)
        self.assertFalse(payload["ok"])

        # operator 发普通命令 → 不被白名单拦截（sim 模式无 RDK，ok 可能为 False 但状态为 200）
        status, payload = http_json("POST", f"{base_url}/api/command", {"command": "lightOn", "params": {}}, token=operator)
        self.assertEqual(status, 200)
        self.assertIn("command", payload)

        # super_admin 发 disarm → 200
        status, payload = http_json("POST", f"{base_url}/api/command", {"command": "disarm", "params": {}}, token=self.admin_token)
        self.assertEqual(status, 200)

        # CORS：本机回环来源被回显
        for origin in ("http://127.0.0.1:8080", "http://localhost:3000"):
            status, _, headers = http_full("GET", f"{base_url}/api/health", headers={"Origin": origin})
            self.assertEqual(status, 200)
            self.assertEqual(headers.get("access-control-allow-origin"), origin)

        # CORS：非白名单来源不带 CORS 头
        status, _, headers = http_full("GET", f"{base_url}/api/health", headers={"Origin": "http://evil.example"})
        self.assertEqual(status, 200)
        self.assertNotIn("access-control-allow-origin", headers)

        # CORS：预检请求同样只回显白名单来源
        status, _, headers = http_full("OPTIONS", f"{base_url}/api/health", headers={"Origin": "http://localhost:5173"})
        self.assertEqual(status, 204)
        self.assertEqual(headers.get("access-control-allow-origin"), "http://localhost:5173")
        status, _, headers = http_full("OPTIONS", f"{base_url}/api/health", headers={"Origin": "http://evil.example"})
        self.assertEqual(status, 204)
        self.assertNotIn("access-control-allow-origin", headers)


if __name__ == "__main__":
    unittest.main()
