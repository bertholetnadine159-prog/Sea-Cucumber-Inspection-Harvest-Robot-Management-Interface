#!/usr/bin/env python3
"""实机链路验收 CLI（不发任何电机/解锁命令，只做只读检查）。

检查项：
  1. REST /api/health 可达
  2. UI WebSocket 收到 hello
  3. 收到视频帧（来自 RDK X5 网关）
  4. status 中 rdk.connected == true
  5. 收到 sensors 遥测，且 pixhawk.connected == true

用法：
  python verify_live.py --ws ws://127.0.0.1:8765 --api http://127.0.0.1:5000
"""

from __future__ import annotations

import argparse
import asyncio
import ipaddress
import json
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request

import websockets

# 验收脚本只访问本机后端或板卡固定地址，不允许把 URL 指向其它主机
_ALLOWED_HOSTS = {"127.0.0.1", "localhost", "::1", "192.168.127.10"}


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """禁止重定向，防止白名单 URL 被跳转到其它主机。"""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise urllib.error.HTTPError(req.full_url, code, f"redirect disabled ({code})", headers, fp)


_OPENER = urllib.request.build_opener(_NoRedirect)


def _guard_url(url: str) -> str:
    """仅允许 http(s)、白名单主机，且解析出的 IP 必须是回环或私网地址。"""
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise ValueError(f"refusing non-http url: {url!r}")
    host = parsed.hostname or ""
    if host not in _ALLOWED_HOSTS:
        raise ValueError(f"refusing disallowed host: {url!r}")
    for info in socket.getaddrinfo(host, None):
        ip = ipaddress.ip_address(info[4][0])
        if not (ip.is_loopback or ip.is_private):
            raise ValueError(f"host resolved outside LAN: {host} -> {ip}")
    return url


async def main() -> int:
    parser = argparse.ArgumentParser(description="SeaUI live link acceptance (read-only)")
    parser.add_argument("--ws", default="ws://127.0.0.1:8765")
    parser.add_argument("--api", default="http://127.0.0.1:5000")
    parser.add_argument("--timeout", type=float, default=40.0)
    parser.add_argument("--verbose", action="store_true", help="print every incoming message")
    args = parser.parse_args()

    checks = {"health": False, "hello": False, "frame": False, "rdk_connected": False, "telemetry": False, "pixhawk": False}

    try:
        with _OPENER.open(_guard_url(args.api + "/api/health"), timeout=5) as response:
            health = json.loads(response.read().decode())
            checks["health"] = bool(health.get("ok"))
            print(f"[health] {health}")
    except Exception as exc:  # noqa: BLE001
        print(f"[health] FAIL {exc}")

    async with websockets.connect(args.ws) as websocket:
        message = json.loads(await asyncio.wait_for(websocket.recv(), 10))
        checks["hello"] = message.get("type") == "hello"
        print(f"[ws hello] {message}")

        printed = {"status": False, "sensors": False, "frame": False}
        deadline = asyncio.get_running_loop().time() + args.timeout
        while True:
            remaining = deadline - asyncio.get_running_loop().time()
            if remaining <= 0:
                break
            try:
                message = json.loads(await asyncio.wait_for(websocket.recv(), remaining))
            except asyncio.TimeoutError:
                break
            mtype = message.get("type")
            if mtype == "frame":
                checks["frame"] = True
                if args.verbose or not printed["frame"]:
                    print(f"[frame] seq via backend, size={len(message.get('data', ''))}")
                    printed["frame"] = True
            elif mtype == "status":
                status = message.get("data", {})
                if status.get("rdk", {}).get("connected"):
                    checks["rdk_connected"] = True
                    if args.verbose or not printed["status"]:
                        print(f"[status] rdk connected {status['rdk']}")
                        printed["status"] = True
            elif mtype == "sensors":
                checks["telemetry"] = True
                pixhawk = message.get("pixhawk", {})
                checks["pixhawk"] = bool(pixhawk.get("connected"))
                if args.verbose or not printed["sensors"]:
                    print(f"[sensors] {len(message.get('data', {}))} sensors, pixhawk={pixhawk}")
                    printed["sensors"] = True
            if all(checks.values()):
                break

    failed = [name for name, ok in checks.items() if not ok]
    print("=" * 44)
    for name, ok in checks.items():
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
    print("=" * 44)
    if failed:
        print("FAILED:", ", ".join(failed))
        return 1
    print("LIVE LINK ACCEPTANCE OK")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
