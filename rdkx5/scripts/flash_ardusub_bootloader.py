#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""通过 PX4 Bootloader 重刷 ArduSub 4.1.0（Pixhawk1）并重启网关验证。

背景：Pixhawk 2.4.8 USB 描述符为 "PX4_BL_FMU_v3.x"（bootloader 态，序列号 0），
裸串口 15 秒 0 字节——飞控未运行任何固件，这是"SeaUI 不能控制机器"的根因。

流程（PC 编排，板端执行）：
  1. 停网关（释放串口）
  2. 推送 uploader.py + ardusub_410_pixhawk1.apj 到板卡 /tmp
  3. uploader 经 Bootloader 协议刷写（erase/program/verify）
  4. 等待飞控重启枚举，核对 udevadm 身份（应变为 ArduPilot 固件态）
  5. 拉起网关，观察 20 秒日志：期望 srcSystem=1、auto-arm 一次、无超时循环

安全：刷写过程电机通道无输出（bootloader 态），不会转动任何电机。
"""

from __future__ import annotations

import argparse
from pathlib import Path

from paramiko import AutoAddPolicy, SSHClient

DEFAULT_HOST = "192.168.5.127"
DEFAULT_USER = "root"
DEFAULT_PASSWORD = "root"
DEFAULT_DIR = "/home/sunrise/seaUI_rdk"
FW_DIR = Path(__file__).resolve().parent.parent / "firmware"
UPLOADER_LOCAL = FW_DIR / "uploader.py"
# 默认固件：完整版（2MB FMUv3 用）；FMUv2/1MB 板用 --firmware 切换 1M 版
FIRMWARE_LOCAL = FW_DIR / "ardusub_410_pixhawk1.apj"
FIRMWARE_1M_LOCAL = FW_DIR / "ardusub_410_pixhawk1_1m.apj"


def main() -> int:
    parser = argparse.ArgumentParser(description="Bootloader 重刷 ArduSub")
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--user", default=DEFAULT_USER)
    parser.add_argument("--password", default=DEFAULT_PASSWORD)
    parser.add_argument("--dir", default=DEFAULT_DIR)
    parser.add_argument(
        "--board", choices=("v3", "v2"), default="v3",
        help="目标飞控闪存版本：v3=2MB 用完整版固件；v2=1MB 用 Pixhawk1-1M 固件",
    )
    args = parser.parse_args()
    firmware_local = FIRMWARE_1M_LOCAL if args.board == "v2" else FIRMWARE_LOCAL

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

    print("===== [1/5] stop gateway =====")
    print(run("pkill -9 -f '[g]ateway' ; sleep 1 ; pgrep -af '[g]ateway' || echo GATEWAY_STOPPED"))

    print("===== [2/5] push files =====")
    sftp = client.open_sftp()
    sftp.put(str(UPLOADER_LOCAL), "/tmp/uploader.py")
    sftp.put(str(firmware_local), "/tmp/ardusub_410_target.apj")
    sftp.close()
    print(run("ls -la /tmp/uploader.py /tmp/ardusub_410_target.apj"))

    print("===== [3/5] flash via bootloader (耐心等待 erase/program/verify) =====")
    print(run(
        "cd /tmp && timeout 300 python3 uploader.py --port /dev/ttyACM0 "
        "ardusub_410_target.apj ; echo EXIT=$?",
        timeout=330,
    ))

    print("===== [4/5] post-flash device identity =====")
    print(run("sleep 8 ; dmesg | grep -E 'cdc_acm|usb 1-1' | tail -n 5"))
    print(run("udevadm info -q property -n /dev/ttyACM0 2>/dev/null | grep -E 'ID_VENDOR=|ID_MODEL=|ID_SERIAL=' || echo NO_TTYACM0"))

    print("===== [5/5] relaunch gateway & watch =====")
    print(run(
        f"cd {args.dir} && (nohup python3 -m gateway >/tmp/gateway_restart.log 2>&1 </dev/null &) ; "
        "sleep 25 ; ss -tlnp | grep 8080 || echo NOT_LISTENING ; "
        "echo '--- gateway log ---' ; tail -n 25 /tmp/gateway_restart.log"
    ))

    client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
