#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""第三轮 b：声纳干净对照 -> 网关恢复 -> 1-Wire 复验 -> I2C5 卡死总线 9-clock 恢复。

用法：python rdkx5/scripts/deep_diag_round3b.py
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
    code = out.channel.recv_exit_status()
    return code, o, e


def main() -> int:
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, username=USER, password=PASSWORD, timeout=12,
                   look_for_keys=False, allow_agent=False)

    # ---- [1] 声纳对照（趁网关不在，串口独占） ----
    print("== [1] 声纳 被动 vs 触发 对照 ==")
    _, o, _ = run(client, "pgrep -af '[g]ateway' || echo no-gateway")
    print("网关进程: " + (o.strip() or "(空)"))
    sftp = client.open_sftp()
    sftp.put(os.path.join(HERE, "sonar_mode_probe.py"), f"{REMOTE_DIR}/scripts/sonar_mode_probe.py")
    sftp.close()
    for port in ("/dev/ttyS7", "/dev/ttyS1"):
        code, o, e = run(client, f"cd {REMOTE_DIR} && timeout 30 python3 scripts/sonar_mode_probe.py {port}",
                         timeout=45)
        print((o + e).strip())

    # ---- [2] 网关恢复 ----
    print("\n== [2] 网关恢复 ==")
    code, o, _ = run(client, "pgrep -af '[g]ateway' || echo NOGW")
    if "NOGW" in o:
        print("网关未运行 -> 重启（stdin 断开版）")
        run(client, f"cd {REMOTE_DIR} && nohup python3 -m gateway "
                    f">/tmp/gateway_restart.log 2>&1 </dev/null & disown", timeout=15)
        time.sleep(8)
    code, o, _ = run(client, "pgrep -af '[g]ateway' || echo NOGW")
    print("进程: " + o.strip())
    _, o, _ = run(client, "tail -5 /tmp/gateway_restart.log 2>/dev/null")
    print("日志尾: " + (o.strip() or "(无)"))
    code, o, e = run(client, f"cd {REMOTE_DIR} && timeout 15 python3 scripts/telemetry_snapshot.py 2>&1",
                     timeout=30)
    print("快照: " + ((o + e).strip()[:800] or "(无响应)"))

    # ---- [3] 1-Wire 存在脉冲复验 ----
    print("\n== [3] 1-Wire 存在脉冲（修复版，含清理与 stderr） ==")
    _, o, _ = run(client, "ls -d /sys/devices/w1_bus_master* 2>&1")
    print("master 现状: " + o.strip())
    for name, dev, gpio in (("总线1(37脚)", "onewire-0", 401),
                            ("总线2(15脚)", "onewire-1", 388)):
        run(client, f"echo {gpio} > /sys/class/gpio/unexport 2>/dev/null; true")
        code, o, e = run(client, f"echo {dev} > /sys/bus/platform/drivers/w1-gpio/unbind 2>&1; "
                                 f"echo unbind_rc=$?", timeout=15)
        print(f"{name} unbind: {(o + e).strip()}")
        code, o, e = run(client, f"cd {REMOTE_DIR} && timeout 30 python3 scripts/w1_presence_probe.py {gpio}",
                         timeout=45)
        print(f"{name} probe:\n{(o + e).strip()}")
        code, o, e = run(client, f"echo {dev} > /sys/bus/platform/drivers/w1-gpio/bind 2>&1; "
                                 f"echo bind_rc=$?", timeout=15)
        print(f"{name} bind: {(o + e).strip()}")
    time.sleep(1)
    _, o, e = run(client, "ls -d /sys/devices/w1_bus_master* 2>&1 && "
                          "cat /sys/devices/w1_bus_master*/w1_master_slaves 2>&1")
    print("收尾核验: " + (o + e).strip())

    # ---- [4] I2C5 卡死总线 9-clock 恢复尝试 ----
    print("\n== [4] I2C5（3/5脚）卡死总线恢复 ==")
    _, o, _ = run(client, "dmesg -c >/dev/null 2>&1; echo cleared")
    code, o, e = run(client, "timeout 20 i2cdetect -y -r 5 2>&1 | tail -3; echo rc=$?", timeout=30)
    print("恢复前 bus5 局部扫描: " + (o + e).strip())
    _, o, _ = run(client, "dmesg | head -6")
    print("dmesg 新增: " + o.strip())

    sftp = client.open_sftp()
    sftp.put(os.path.join(HERE, "i2c_bus_recover.py"), f"{REMOTE_DIR}/scripts/i2c_bus_recover.py")
    sftp.close()
    code, o, e = run(client, f"cd {REMOTE_DIR} && timeout 30 python3 scripts/i2c_bus_recover.py 5 390 389",
                     timeout=45)
    print((o + e).strip())

    print("-- 恢复后再扫 --")
    for bus in (5,):
        code, o, e = run(client, f"timeout 25 i2cdetect -y -r {bus} 2>&1 || true", timeout=40)
        print(f"-- bus {bus} --\n{o.strip() or e.strip()}")

    client.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
