#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""PC 侧编排：停网关 → 板上裸探针独占抓 Pixhawk 出站流 → 重启网关。

用法：python rdkx5/scripts/pixhawk_hang_probe.py
流程：
  1. 记录当前谁占着 /dev/ttyACM0（fuser）
  2. pkill 网关（方括号防自杀技巧），确认停止
  3. sftp 推送 pixhawk_raw_probe.py 到 /tmp，执行 15 秒抓包
  4. dmesg tail（看 USB 重枚举）
  5. 以标准方式拉起网关并验证 8080 监听
"""

from __future__ import annotations

import argparse
from pathlib import Path

from paramiko import AutoAddPolicy, SSHClient

DEFAULT_HOST = "192.168.5.127"
DEFAULT_USER = "root"
DEFAULT_PASSWORD = "root"
DEFAULT_DIR = "/home/sunrise/seaUI_rdk"
PROBE_LOCAL = Path(__file__).resolve().parent / "pixhawk_raw_probe.py"
PROBE_REMOTE = "/tmp/pixhawk_raw_probe.py"


def main() -> int:
    parser = argparse.ArgumentParser(description="Pixhawk 出站流诊断编排")
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--user", default=DEFAULT_USER)
    parser.add_argument("--password", default=DEFAULT_PASSWORD)
    parser.add_argument("--dir", default=DEFAULT_DIR)
    parser.add_argument("--seconds", type=float, default=15.0)
    args = parser.parse_args()

    client = SSHClient()
    client.set_missing_host_key_policy(AutoAddPolicy())
    client.connect(
        args.host, username=args.user, password=args.password,
        timeout=10, look_for_keys=False, allow_agent=False,
    )

    def run(cmd: str, timeout: int = 60) -> str:
        _, out, err = client.exec_command(cmd, timeout=timeout)
        text = out.read().decode(errors="replace").strip()
        err_text = err.read().decode(errors="replace").strip()
        return text + (f"\n[stderr] {err_text}" if err_text else "")

    print("===== [1/5] serial squatters & USB history =====")
    print(run(
        "fuser -v /dev/ttyACM0 2>&1; "
        "pgrep -af 'modem|brltty' || echo NO_MODEM_MANAGER; "
        "systemctl is-active ModemManager 2>&1; "
        "dmesg | grep -iE 'cdc_acm|ttyACM' | tail -n 8"
    ))

    print("===== [2/5] stop gateway =====")
    print(run("pkill -9 -f '[g]ateway' ; sleep 1 ; pgrep -af '[g]ateway' || echo GATEWAY_STOPPED"))
    print(run(
        "LEFT=$(fuser /dev/ttyACM0 2>/dev/null | tr -d ' '); "
        "if [ -n \"$LEFT\" ]; then "
        "  ps -o pid,etime,args -p $LEFT; "
        "  kill -9 $LEFT; sleep 1; "
        "  fuser /dev/ttyACM0 2>&1 || echo PORT_NOW_FREE; "
        "else echo PORT_ALREADY_FREE; fi"
    ))

    print("===== [3/5] raw probe =====")
    sftp = client.open_sftp()
    sftp.put(str(PROBE_LOCAL), PROBE_REMOTE)
    sftp.close()
    print(run(f"python3 {PROBE_REMOTE} --seconds {args.seconds}", timeout=90))

    print("===== [4/5] dmesg tail =====")
    print(run("dmesg | tail -n 12"))

    print("===== [5/5] relaunch gateway & watch stability =====")
    relaunch = (
        f"cd {args.dir} && (nohup python3 -m gateway >/tmp/gateway_restart.log 2>&1 </dev/null &) ; "
        "sleep 20 ; "
        "ss -tlnp | grep 8080 || echo NOT_LISTENING ; "
        "echo '--- last 15 log lines ---' ; tail -n 15 /tmp/gateway_restart.log ; "
        "echo '--- timeout count in last 20s ---' ; "
        "grep -c 'heartbeat timeout' /tmp/gateway_restart.log"
    )
    print(run(relaunch, timeout=90))

    client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
