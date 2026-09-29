#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""板端控制链路只读诊断：网关进程 / Pixhawk 设备 / auto-arm 日志 / 代码版本。

用法：python rdkx5/scripts/board_control_diag.py
"""

from __future__ import annotations

import argparse

from paramiko import AutoAddPolicy, SSHClient

DEFAULT_HOST = "192.168.5.127"
DEFAULT_USER = "root"
DEFAULT_PASSWORD = "root"
DEFAULT_DIR = "/home/sunrise/seaUI_rdk"

# 全部只读；pkill 类危险操作绝不放在这里
CHECKS = [
    ("gateway process", "pgrep -af '[g]ateway' || echo NOT_RUNNING"),
    ("port 8080", "ss -tlnp | grep 8080 || echo NOT_LISTENING"),
    ("pixhawk device", "ls -l /dev/ttyACM* /dev/ttyUSB* 2>/dev/null || echo NO_DEVICE"),
    ("gw log tail", "tail -n 40 /tmp/gateway_restart.log 2>/dev/null || echo NO_LOG"),
    ("auto-arm history", "grep -c 'auto-arm done' /tmp/gateway_restart.log 2>/dev/null; "
                          "grep 'auto-arm' /tmp/gateway_restart.log 2>/dev/null | tail -n 5"),
    ("armed/ack recent", "grep -E 'COMMAND_ACK|STATUSTEXT|reconnect|heartbeat timeout' "
                          "/tmp/gateway_restart.log 2>/dev/null | tail -n 15"),
    ("board date/uptime", "date '+%F %T'; uptime"),
    ("code freshness", "cd {dir} && grep -c 'start_polling' sensors.py 2>/dev/null; "
                        "grep -c '_maybe_retry_auto_arm' pixhawk_link.py 2>/dev/null; "
                        "ls -l --time-style=+%F_%T gateway.py sensors.py pixhawk_link.py stream_server.py"),
    ("board code version", "cd {dir} && git log --oneline -3 2>/dev/null || echo NO_GIT"),
    ("board config pixhawk", "cd {dir} && sed -n '/^pixhawk:/,/^[a-z_]*:/p' config.yaml | head -30"),
    ("gateway uptime", "ps -o pid,etime,args -C python3 2>/dev/null | grep -i gate || true"),
    ("usb reenum recent", "dmesg 2>/dev/null | grep -iE 'ttyACM|usb .* disconnect' | tail -n 6 || true"),
    ("acm holders", "fuser -v /dev/ttyACM0 2>&1; "
                     "PIDS=$(fuser /dev/ttyACM0 2>/dev/null | tr -d ' '); "
                     "[ -n \"$PIDS\" ] && ps -o pid,etime,args -p $PIDS || echo NO_HOLDER"),
    ("all python3 procs", "ps -o pid,etime,args -C python3"),
]


def main() -> int:
    parser = argparse.ArgumentParser(description="板端控制链路诊断（只读）")
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--user", default=DEFAULT_USER)
    parser.add_argument("--password", default=DEFAULT_PASSWORD)
    parser.add_argument("--dir", default=DEFAULT_DIR)
    args = parser.parse_args()

    client = SSHClient()
    client.set_missing_host_key_policy(AutoAddPolicy())
    client.connect(
        args.host, username=args.user, password=args.password,
        timeout=10, look_for_keys=False, allow_agent=False,
    )

    def run(cmd: str, timeout: int = 30) -> str:
        _, out, err = client.exec_command(cmd, timeout=timeout)
        text = out.read().decode(errors="replace").strip()
        err_text = err.read().decode(errors="replace").strip()
        return text + (f"\n[stderr] {err_text}" if err_text else "")

    for title, template in CHECKS:
        print(f"===== {title} =====")
        try:
            print(run(template.format(dir=args.dir)) or "(empty)")
        except Exception as exc:  # noqa: BLE001
            print(f"ERROR: {exc}")
        print()
    client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
