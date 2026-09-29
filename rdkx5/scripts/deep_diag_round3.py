#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""第三轮：现场恢复 + 取证 + 对照诊断（本地跑，SSH 到板卡）。

顺序（先恢复现场，再取证诊断）：
[1] 取证：dmesg 尾部 / gpio 占用 / w1-gpio 驱动目录 / class/gpio 残留
[2] 恢复 w1：清残留 export -> 重绑 onewire-0/1（带 stderr）-> master 存在性 + 搜索计数自增
[3] 网关健康：进程 + WS 快照（15s 超时）；失败则按正规方式重启再快照
[4] 声纳对照：被动监听 vs 触发（sonar_mode_probe.py，两端口）
[5] 1-Wire 存在脉冲（w1_presence_probe.py 带完整 traceback）

用法：python rdkx5/scripts/deep_diag_round3.py
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

    print("== [1] 取证：上一轮遗留状态 ==")
    _, o, _ = run(client, "dmesg | tail -25")
    print("-- dmesg tail --\n" + o.strip())
    _, o, _ = run(client, "ls /sys/bus/platform/drivers/w1-gpio/ 2>&1")
    print("-- w1-gpio 驱动目录 --\n" + o.strip())
    _, o, _ = run(client, "ls /sys/class/gpio/ 2>&1")
    print("-- class/gpio --\n" + o.strip())
    _, o, _ = run(client, "command -v gpioinfo >/dev/null && gpioinfo gpiochip4 2>/dev/null "
                          "| grep -E 'line (9|22):' || echo gpioinfo-不可用")
    print("-- gpiochip4 line 9/22 占用 --\n" + o.strip())

    print("\n== [2] 恢复 w1 双 master ==")
    run(client, "for g in 401 388; do echo $g > /sys/class/gpio/unexport 2>/dev/null; done; true")
    for dev in ("onewire-0", "onewire-1"):
        code, o, e = run(client, f"echo {dev} > /sys/bus/platform/drivers/w1-gpio/bind 2>&1; "
                                 f"echo rc=$?", timeout=15)
        print(f"bind {dev}: {(o + e).strip()}")
    time.sleep(2.0)
    _, o, _ = run(client, "ls -d /sys/devices/w1_bus_master* 2>&1; "
                          "for m in /sys/devices/w1_bus_master*; do "
                          "a1=$(cat $m/w1_master_attempts 2>/dev/null); sleep 3; "
                          "a2=$(cat $m/w1_master_attempts 2>/dev/null); "
                          "echo \"$m: slaves=[$(cat $m/w1_master_slaves 2>/dev/null)] "
                          "attempts $a1->$a2\"; done", timeout=30)
    print(o.strip())

    print("\n== [3] 网关健康检查 ==")
    _, o, _ = run(client, "pgrep -af '[g]ateway' || echo (无网关进程)")
    print("进程: " + o.strip())
    code, o, e = run(client, f"cd {REMOTE_DIR} && timeout 15 python3 scripts/telemetry_snapshot.py 2>&1",
                     timeout=30)
    snap = (o + e).strip()
    print("快照: " + (snap[:600] if snap else "(15s 无响应)"))
    if not snap:
        print("-- 网关无响应，按正规方式重启 --")
        run(client, "pkill -f '[g]ateway' ; sleep 2")
        run(client, f"cd {REMOTE_DIR} && nohup python3 -m gateway >/tmp/gateway_restart.log 2>&1 & "
                    f"sleep 8", timeout=30)
        _, o, e = run(client, f"cd {REMOTE_DIR} && timeout 15 python3 scripts/telemetry_snapshot.py 2>&1",
                      timeout=30)
        snap2 = (o + e).strip()
        print("重启后快照: " + (snap2[:600] if snap2 else "(15s 仍无响应)"))
        _, o, _ = run(client, "tail -20 /tmp/gateway_restart.log 2>/dev/null; "
                              "pgrep -af '[g]ateway' || echo (仍无进程)")
        print("网关日志/进程:\n" + o.strip())

    print("\n== [4] 声纳被动 vs 触发对照 ==")
    sftp = client.open_sftp()
    for f in ("sonar_mode_probe.py", "w1_presence_probe.py"):
        sftp.put(os.path.join(HERE, f), f"{REMOTE_DIR}/scripts/{f}")
    sftp.close()
    for port in ("/dev/ttyS7", "/dev/ttyS1"):
        code, o, e = run(client, f"cd {REMOTE_DIR} && timeout 30 python3 scripts/sonar_mode_probe.py {port}",
                         timeout=45)
        print((o + e).strip())

    print("\n== [5] 1-Wire 存在脉冲（traceback 版） ==")
    for name, dev, gpio in (("总线1(37脚)", "onewire-0", 401),
                            ("总线2(15脚)", "onewire-1", 388)):
        run(client, f"echo {dev} > /sys/bus/platform/drivers/w1-gpio/unbind ; sleep 0.5")
        code, o, e = run(client, f"cd {REMOTE_DIR} && timeout 30 python3 scripts/w1_presence_probe.py {gpio}",
                         timeout=45)
        print(f"{name}:\n{(o + e).strip()}")
        run(client, f"echo {dev} > /sys/bus/platform/drivers/w1-gpio/bind ; sleep 1.5")
    code, o, e = run(client, "ls -d /sys/devices/w1_bus_master* 2>&1; "
                             "cat /sys/devices/w1_bus_master*/w1_master_slaves 2>&1")
    print("收尾核验:\n" + (o + e).strip())

    client.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
