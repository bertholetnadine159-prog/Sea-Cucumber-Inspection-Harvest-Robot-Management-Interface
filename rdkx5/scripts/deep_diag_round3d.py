#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""第三轮 d：网关 WS 诊断 -> 停网关独占串口 -> 声纳定论 -> 重启网关验证。

用法：python rdkx5/scripts/deep_diag_round3d.py
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
    return (out.read() + err.read()).decode(errors="replace").strip()


def main() -> int:
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, username=USER, password=PASSWORD, timeout=12,
                   look_for_keys=False, allow_agent=False)

    print("== [1] 网关 WS 诊断 ==")
    print("日志头:\n" + run(client, "head -25 /tmp/gateway_restart.log 2>/dev/null"))
    print("8080 监听: " + (run(client, "ss -ltnp 2>/dev/null | grep -E '8080|8765' || echo 无监听") or "(空)"))
    print("WS 端口连通: " + run(client,
        "timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/8080' 2>&1 && echo 8080-open || echo 8080-closed"))

    print("\n== [2] 停网关 -> 独占串口复测声纳 ==")
    run(client, "pkill -TERM -f '[g]ateway' ; sleep 3 ; pkill -KILL -f '[g]ateway' 2>/dev/null ; sleep 1")
    print("残留进程: " + (run(client, "pgrep -af '[g]ateway' || echo 无") or "(空)"))
    print("串口占用: " + (run(client, "fuser /dev/ttyS7 /dev/ttyS1 2>&1 || echo 无占用") or "(空)"))
    for port in ("/dev/ttyS7", "/dev/ttyS1"):
        out = run(client, f"cd {REMOTE_DIR} && timeout 30 python3 scripts/sonar_mode_probe.py {port}",
                  timeout=45)
        print(out)

    print("\n== [3] 重启网关并验证 ==")
    run(client, f"cd {REMOTE_DIR} && nohup python3 -m gateway "
                f">/tmp/gateway_restart.log 2>&1 </dev/null & disown", timeout=15)
    time.sleep(10)
    print("进程: " + run(client, "pgrep -af '[g]ateway' | head -3 || echo 无"))
    print("启动日志:\n" + run(client, "grep -E 'sensor opened|server|WS|listen|start' "
                                    "/tmp/gateway_restart.log | head -12"))
    for i in (1, 2):
        out = run(client, f"cd {REMOTE_DIR} && timeout 15 python3 scripts/telemetry_snapshot.py 2>&1",
                  timeout=30)
        print(f"-- 快照{i} --\n" + (out[:900] or "(无响应)"))
        if i == 1:
            time.sleep(10)

    client.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
