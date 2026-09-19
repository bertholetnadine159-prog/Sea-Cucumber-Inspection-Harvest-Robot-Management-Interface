#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""远程拉起 RDK X5 板卡上的 SeaUI 网关（SSH）。

默认目标：root@192.168.5.127（板卡当前实际地址，WLAN 网段）。
可用参数覆盖：--host / --user / --password / --dir

做三件事：
  1. 确认 pymavlink 依赖（缺则用清华镜像安装）
  2. nohup 拉起网关（日志 /tmp/seaul_gw.log 与板卡本地 gateway.log）
  3. 回读启动日志确认监听端口

用法：python rdkx5/scripts/launch_board_gateway.py
"""

from __future__ import annotations

import argparse

from paramiko import AutoAddPolicy, SSHClient

DEFAULT_HOST = "192.168.5.127"
DEFAULT_USER = "root"
DEFAULT_PASSWORD = "root"
DEFAULT_DIR = "/home/sunrise/seaUI_rdk"

# 远程命令（拆成常量仅为了可读性；不含任何本地文件写入）
CHECK_DEP = (
    "python3 -c \"import importlib,sys;sys.exit(0 if importlib.util.find_spec('pymavlink') else 1)\""
)
INSTALL_DEP = "pip3 install -q -i https://pypi.tuna.tsinghua.edu.cn/simple pymavlink"
LAUNCH = (
    "cd {dir} && (nohup python3 -m gateway 1>/tmp/seaul_gw.log 2>&1 &) ; echo launched"
)
TAIL_LOG = "sleep 5; tail -n 20 /tmp/seaul_gw.log"


def main() -> int:
    parser = argparse.ArgumentParser(description="远程拉起 SeaUI 网关")
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

    def run(cmd: str, timeout: int = 120) -> str:
        _, out, err = client.exec_command(cmd, timeout=timeout)
        text = out.read().decode(errors="replace").strip()
        err_text = err.read().decode(errors="replace").strip()
        return text + (f"\n[stderr] {err_text}" if err_text else "")

    print("[1/3] 依赖检查 ...")
    if client.exec_command(CHECK_DEP)[1].channel.recv_exit_status() != 0:
        print("      安装 pymavlink（清华镜像）...")
        print("      " + run(INSTALL_DEP, timeout=180))
    else:
        print("      pymavlink 已就绪")

    print("[2/3] 拉起网关 ...")
    print("      " + run(LAUNCH.format(dir=args.dir)))

    print("[3/3] 启动日志 ...")
    print(run(TAIL_LOG, timeout=60))

    client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
