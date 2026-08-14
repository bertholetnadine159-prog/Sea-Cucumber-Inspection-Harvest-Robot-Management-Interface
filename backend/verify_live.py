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
import json
import sys
import urllib.request

import websockets


async def main() -> int:
    parser = argparse.ArgumentParser(description="SeaUI live link acceptance (read-only)")
    parser.add_argument("--ws", default="ws://127.0.0.1:8765")
    parser.add_argument("--api", default="http://127.0.0.1:5000")
    parser.add_argument("--timeout", type=float, default=40.0)
    args = parser.parse_args()

    checks = {"health": False, "hello": False, "frame": False, "rdk_connected": False, "telemetry": False, "pixhawk": False}

    try:
        with urllib.request.urlopen(args.api + "/api/health", timeout=5) as response:
            health = json.loads(response.read().decode())
            checks["health"] = bool(health.get("ok"))
            print(f"[health] {health}")
    except Exception as exc:  # noqa: BLE001
        print(f"[health] FAIL {exc}")

    async with websockets.connect(args.ws) as websocket:
        message = json.loads(await asyncio.wait_for(websocket.recv(), 10))
        checks["hello"] = message.get("type") == "hello"
        print(f"[ws hello] {message}")

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
                print(f"[frame] seq via backend, size={len(message.get('data', ''))}")
            elif mtype == "status":
                status = message.get("data", {})
                if status.get("rdk", {}).get("connected"):
                    checks["rdk_connected"] = True
                    print(f"[status] rdk connected {status['rdk']}")
            elif mtype == "sensors":
                checks["telemetry"] = True
                pixhawk = message.get("pixhawk", {})
                checks["pixhawk"] = bool(pixhawk.get("connected"))
                print(f"[sensors] {len(message.get('data', {}))} sensors, pixhawk={pixhawk}")
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
