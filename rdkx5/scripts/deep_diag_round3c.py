#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""第三轮 c：恢复 1-Wire 现场 -> 网关遥测双快照判定声纳帧新鲜度 -> 收尾核验。

用法：python rdkx5/scripts/deep_diag_round3c.py
"""
import os
import sys
import time

import paramiko

HOST = os.environ.get("RDK_HOST", "192.168.5.127")
USER = os.environ.get("RDK_USER", "root")
PASSWORD = os.environ.get("RDK_SSH_PASSWORD", "root")
REMOTE_DIR = "/home/sunrise/seaUI_rdk"
HERE = os.path.dirname(os.path.abspath(__file__))


def run(client, cmd, timeout=60):
    _, out, err = client.exec_command(cmd, timeout=timeout)
    o = out.read().decode(errors="replace")
    e = err.read().decode(errors="replace")
    return code_ret(out, o, e)


def code_ret(out, o, e):
    return (o + e).strip()


def main() -> int:
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, username=USER, password=PASSWORD, timeout=12,
                   look_for_keys=False, allow_agent=False)

    # ---- [1] 恢复 1-Wire 现场 ----
    print("== [1] 恢复 1-Wire 双 master ==")
    run(client, "for g in 401 388; do echo $g > /sys/class/gpio/unexport 2>/dev/null; done; true")
    sftp = client.open_sftp()
    sftp.put(os.path.join(HERE, "w1_presence_probe.py"), f"{REMOTE_DIR}/scripts/w1_presence_probe.py")
    sftp.close()
    for dev in ("onewire-0", "onewire-1"):
        _, out, err = client.exec_command(
            f"echo {dev} > /sys/bus/platform/drivers/w1-gpio/bind 2>&1; echo rc=$?", timeout=15)
        print(f"bind {dev}: {(out.read() + err.read()).decode(errors='replace').strip()}")
    time.sleep(1.5)
    _, out, err = client.exec_command(
        "ls -d /sys/devices/w1_bus_master* 2>&1; "
        "for m in /sys/devices/w1_bus_master*; do "
        "a1=$(cat $m/w1_master_attempts 2>/dev/null); sleep 11; "
        "a2=$(cat $m/w1_master_attempts 2>/dev/null); "
        "echo \"$m slaves=[$(cat $m/w1_master_slaves 2>/dev/null)] attempts $a1->$a2\"; done",
        timeout=40)
    print("master 核验（11s 窗口搜索计数）:\n" + (out.read() + err.read()).decode(errors="replace").strip())

    # ---- [2] 网关状态 ----
    print("\n== [2] 网关状态 ==")
    _, out, err = client.exec_command("pgrep -af '[g]ateway' || echo NOGW", timeout=15)
    print("进程: " + (out.read() + err.read()).decode(errors="replace").strip())

    # ---- [3] 遥测双快照（间隔 12s，判定声纳帧是否实时刷新） ----
    print("\n== [3] 遥测双快照对比 ==")
    snaps = []
    for i in (1, 2):
        _, out, err = client.exec_command(
            f"cd {REMOTE_DIR} && timeout 15 python3 scripts/telemetry_snapshot.py 2>&1", timeout=30)
        snaps.append((out.read() + err.read()).decode(errors="replace").strip())
        if i == 1:
            time.sleep(12)
    for i, s in enumerate(snaps, 1):
        print(f"-- 快照{i} --")
        print(s[:900] if s else "(无响应)")
    # 只抽声纳两行对比
    def sonar_lines(s):
        return [ln for ln in s.splitlines() if "ultrasonic" in ln]
    if snaps[0] and snaps[1]:
        a, b = sonar_lines(snaps[0]), sonar_lines(snaps[1])
        print("\n声纳两快照逐行一致？" + ("一致（信息量相同，需看下面结论）" if a == b else "不一致（内容在刷新）"))
        print("快照1声纳: " + (" | ".join(a) if a else "(无)"))
        print("快照2声纳: " + (" | ".join(b) if b else "(无)"))

    # ---- [4] 网关日志里传感器线程健康 ----
    print("\n== [4] 网关日志扫描（hub/传感器异常） ==")
    _, out, err = client.exec_command(
        "grep -iE 'sensor|hub|sonar|ultrasonic|serial' /tmp/gateway_restart.log 2>/dev/null | tail -15",
        timeout=15)
    print((out.read() + err.read()).decode(errors="replace").strip() or "(日志无传感器相关行)")

    client.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
