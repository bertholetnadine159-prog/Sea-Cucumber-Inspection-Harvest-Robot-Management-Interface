#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""远程重启 RDK X5 板卡上的 SeaUI 网关（SSH + systemd）。

默认目标：root@192.168.5.127（板卡当前实际地址，WLAN 网段）。
可用参数覆盖：--host / --user / --password / --dir

网关已 systemd 化（deploy/seaul-gateway.service，User=root）：
旧 nohup 拉起方式作废（两种进程名并存会杀错/旧代码永驻）。

做三件事：
  1. systemctl restart seaul-gateway
  2. 确认服务 active 且 8080 端口监听
  3. journalctl 回读启动日志（含 AUX 功能位确保/auto-arm 记录）

用法：python rdkx5/scripts/launch_board_gateway.py
"""

from __future__ import annotations

import argparse
import time

from paramiko import AutoAddPolicy, SSHClient

DEFAULT_HOST = "192.168.5.127"
DEFAULT_USER = "root"
DEFAULT_PASSWORD = "root"
DEFAULT_DIR = "/home/sunrise/seaUI_rdk"

RESTART = "systemctl restart seaul-gateway"
STATUS = "systemctl is-active seaul-gateway"
# 回读启动日志：AUX 功能位确保 / auto-arm / 监听端口都打在 journal
TAIL_LOG = "sleep 5; journalctl -u seaul-gateway -n 25 --no-pager -o cat"
CHECK_PORT = (
    "python3 -c \"import socket;s=socket.socket();s.settimeout(2);"
    "s.connect(('127.0.0.1',8080));print('port 8080 OPEN');s.close()\""
)


def main() -> int:
    parser = argparse.ArgumentParser(description="远程重启 SeaUI 网关（systemd）")
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--user", default=DEFAULT_USER)
    parser.add_argument("--password", default=DEFAULT_PASSWORD)
    parser.add_argument("--dir", default=DEFAULT_DIR, help="兼容保留；systemd 单元已固定工作目录")
    args = parser.parse_args()

    client = SSHClient()
    client.set_missing_host_key_policy(AutoAddPolicy())
    client.connect(
        args.host, username=args.user, password=args.password,
        timeout=10, look_for_keys=False, allow_agent=False,
    )

    def run(cmd: str, timeout: int = 120) -> str:
        _, out, err = client.exec_command(cmd, timeout=timeout)
        text = out.read().decode(errors="replace").strip()
        err_text = err.read().decode(errors="replace").strip()
        return text + (f"\n[stderr] {err_text}" if err_text else "")

    print("[1/3] systemctl restart seaul-gateway ...")
    print("      " + run(RESTART))
    time.sleep(2)

    print("[2/3] 服务状态与端口 ...")
    status = run(STATUS)
    print(f"      is-active: {status}")
    print("      " + run(CHECK_PORT))

    print("[3/3] 启动日志（journalctl）...")
    print(run(TAIL_LOG, timeout=60))

    client.close()
    return 0 if status == "active" else 1


if __name__ == "__main__":
    raise SystemExit(main())
