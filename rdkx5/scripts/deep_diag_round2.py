#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""第二轮深度诊断（本地跑，SSH 到板卡执行）：

[A] SIGSTOP 网关 -> 独立重测双声纳（排除串口争用抢帧）-> SIGCONT 恢复
[B] 1-Wire 手动"复位-存在脉冲"（DQ 电气通路判定，区别于内核搜索失败）
[C] 重绑触发重搜后的 w1 master 状态
[D] I2C 总线 5 / 2 全地址原始网格（定性卡死总线）
[E] 网关恢复确认

用法：python rdkx5/scripts/deep_diag_round2.py
"""
import os
import sys

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
    return o, e


def main() -> int:
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, username=USER, password=PASSWORD, timeout=12,
                   look_for_keys=False, allow_agent=False)

    print("== 网关进程 ==")
    o, _ = run(client, "pgrep -af '[g]ateway' || true")
    print(o.strip() or "(未找到网关进程)")

    print("\n== [A] 冻结网关 -> 独立重测声纳 -> 恢复 ==")
    run(client, "pkill -STOP -f '[g]ateway' ; sleep 1")
    for port in ("/dev/ttyS7", "/dev/ttyS1"):
        o, e = run(client, f"cd {REMOTE_DIR} && timeout 60 python3 scripts/l08_probe.py "
                           f"--port {port} --rounds 4", timeout=90)
        print((o + e).strip())
    run(client, "pkill -CONT -f '[g]ateway'")
    print("(网关已 SIGCONT 恢复)")

    print("\n== [B] 1-Wire 手动复位-存在脉冲 ==")
    sftp = client.open_sftp()
    sftp.put(os.path.join(HERE, "w1_presence_probe.py"),
             f"{REMOTE_DIR}/scripts/w1_presence_probe.py")
    sftp.close()
    for name, dev, gpio in (("总线1(37脚)", "onewire-0", 401),
                            ("总线2(15脚)", "onewire-1", 388)):
        run(client, f"echo {dev} > /sys/bus/platform/drivers/w1-gpio/unbind ; sleep 0.3")
        o, e = run(client, f"cd {REMOTE_DIR} && timeout 30 python3 scripts/w1_presence_probe.py {gpio}",
                   timeout=45)
        print(f"{name}: {(o + e).strip()}")
        run(client, f"echo {dev} > /sys/bus/platform/drivers/w1-gpio/bind ; sleep 1.5")

    print("\n== [C] 重搜后的 w1 master 状态 ==")
    o, _ = run(client, "for m in /sys/devices/w1_bus_master*; do "
                       "echo \"$m: slaves=[$(cat $m/w1_master_slaves 2>/dev/null)] "
                       "count=$(cat $m/w1_master_slave_count 2>/dev/null) "
                       "attempts=$(cat $m/w1_master_attempts 2>/dev/null)\"; done")
    print(o.strip())

    print("\n== [D] I2C 总线 5 / 2 全地址原始网格 ==")
    for bus in (5, 2):
        o, e = run(client, f"timeout 25 i2cdetect -y -r {bus} 2>&1 || true", timeout=40)
        print(f"-- bus {bus} --\n{o.strip() or e.strip()}")

    print("\n== [E] 网关恢复确认 ==")
    o, e = run(client, f"cd {REMOTE_DIR} && timeout 40 python3 scripts/telemetry_snapshot.py 2>&1",
               timeout=60)
    print((o + e).strip())

    client.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
