#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""实机电机脉冲验收 CLI（陆地干式、桨叶已拆除时才可运行）。

完整链路：PC REST -> backend -> RDK X5 gateway -> MAVLink -> Pixhawk -> ESC。
流程：arm -> 低油门 pulse 一小段时间 -> stop（回中）。

安全约束：
  * 必须显式传 --i-confirm-propellers-removed 才会发送任何电机命令；
  * 任何异常都会在 finally 中先 stop 回中；
  * 默认结束后保持 armed（让 ESC 持续收到中性 PWM，避免“无信号”报警），
    需要解锁时加 --disarm；
  * 绝不在本脚本内使用 force 上锁，只做正常 arm。

用法：
  python backend/verify_motor_pulse.py --i-confirm-propellers-removed
  python backend/verify_motor_pulse.py --i-confirm-propellers-removed --axis surge --pulse 0.08 --duration 1.0
  python backend/verify_motor_pulse.py --i-confirm-propellers-removed --disarm
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request


ALLOWED_AXES = {"surge", "sway", "heave", "roll", "pitch", "yaw"}


def http_json(api: str, path: str, body: dict | None = None, token: str | None = None) -> dict:
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode("utf-8") if body is not None else None
    request = urllib.request.Request(api + path, data=data, headers=headers)
    with urllib.request.urlopen(request, timeout=6) as response:
        return json.loads(response.read().decode("utf-8"))


def health(api: str) -> dict:
    return http_json(api, "/api/health")


def command(api: str, token: str, name: str, params: dict | None = None) -> bool:
    payload = {"command": name, "params": params or {}}
    try:
        result = http_json(api, "/api/command", payload, token)
        print(f"[command] {name} -> {result}")
        return bool(result.get("ok"))
    except Exception as exc:  # noqa: BLE001
        print(f"[command] {name} FAILED: {exc}")
        return False


def wait_for(api: str, predicate, timeout: float, label: str) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            state = predicate(health(api))
            if state:
                print(f"[wait] {label} OK")
                return True
        except Exception as exc:  # noqa: BLE001
            print(f"[wait] {label} poll error: {exc}")
        time.sleep(0.5)
    print(f"[wait] {label} TIMEOUT")
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description="SeaUI live motor pulse acceptance")
    parser.add_argument("--api", default="http://127.0.0.1:5000")
    parser.add_argument("--username", default="zmm")
    parser.add_argument("--password", default=os.getenv("ROV_ADMIN_PASSWORD", "Zmm771023"))
    parser.add_argument(
        "--i-confirm-propellers-removed",
        action="store_true",
        required=True,
        help="propellers must be physically removed before sending motor commands",
    )
    parser.add_argument("--axis", default="surge", choices=sorted(ALLOWED_AXES))
    parser.add_argument("--pulse", type=float, default=0.08, help="axis command -1..1 (default gentle 0.08)")
    parser.add_argument("--duration", type=float, default=1.0)
    parser.add_argument("--disarm", action="store_true", help="disarm at the end (default: stay armed, neutral PWM)")
    parser.add_argument("--arm-timeout", type=float, default=15.0)
    args = parser.parse_args()

    checks = {"login": False, "connected": False, "arm": False, "move": False, "stop": False, "disarm": True}
    token: str | None = None
    armed_at_start = False

    try:
        login = http_json(args.api, "/api/login", {"username": args.username, "password": args.password})
        checks["login"] = bool(login.get("ok"))
        token = str(login.get("token", ""))
        print(f"[login] ok={checks['login']} user={login.get('user', {}).get('username')}")
        if not token:
            print("[login] no token returned; abort")
            return 1

        state = health(args.api)
        pixhawk = state.get("pixhawk", {})
        checks["connected"] = bool(pixhawk.get("connected"))
        armed_at_start = bool(pixhawk.get("armed"))
        print(f"[pre] pixhawk={pixhawk}")
        if not checks["connected"]:
            print("[pre] Pixhawk not connected; abort before sending anything")
            return 1

        if not armed_at_start:
            checks["arm"] = command(args.api, token, "arm")
            if checks["arm"]:
                checks["arm"] = wait_for(
                    args.api,
                    lambda h: bool(h.get("pixhawk", {}).get("armed")),
                    args.arm_timeout,
                    "armed=true",
                )
        else:
            checks["arm"] = True
            print("[pre] already armed; skip arm")

        if not checks["arm"]:
            print("[arm] arming failed; aborting before throttle pulse")
            return 1

        pulse = max(-0.3, min(0.3, float(args.pulse)))
        payload = {"axes": {args.axis: pulse}, "deadman_ms": max(800, int(args.duration * 1000) + 500)}
        checks["move"] = command(args.api, token, "move", payload)
        print(f"[pulse] {args.axis}={pulse:+.3f} for {args.duration:.1f}s")
        time.sleep(args.duration)
        checks["stop"] = command(args.api, token, "stop")
        print("[stop] neutral axes sent")

        if args.disarm:
            checks["disarm"] = command(args.api, token, "disarm")
            if checks["disarm"]:
                checks["disarm"] = wait_for(
                    args.api,
                    lambda h: not bool(h.get("pixhawk", {}).get("armed")),
                    10.0,
                    "armed=false",
                )
    except KeyboardInterrupt:
        print("[abort] Ctrl+C; ensuring stop")
    except Exception as exc:  # noqa: BLE001
        print(f"[error] {exc}")
    finally:
        if token:
            try:
                command(args.api, token, "stop")
                if args.disarm:
                    command(args.api, token, "disarm")
            except Exception as exc:  # noqa: BLE001
                print(f"[finally] safety commands failed: {exc}")

    final = {}
    try:
        final = health(args.api).get("pixhawk", {})
    except Exception as exc:  # noqa: BLE001
        print(f"[final] health failed: {exc}")
    print(f"[final] pixhawk={final}")
    if not args.disarm:
        print("[note] kept armed so ESCs keep receiving neutral PWM; send 'disarm' when done.")
        checks.pop("disarm", None)

    failed = [name for name, ok in checks.items() if not ok]
    print("=" * 44)
    for name, ok in checks.items():
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
    print("=" * 44)
    if failed:
        print("FAILED:", ", ".join(failed))
        return 1
    print("MOTOR PULSE ACCEPTANCE OK (confirm physical rotation visually)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
