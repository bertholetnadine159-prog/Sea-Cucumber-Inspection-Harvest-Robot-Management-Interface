#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""板卡传感器超级查询（SSH 远程执行版，供 CI/门禁调用）。

用法：python3 rdkx5/scripts/board_super_query.py
环境变量：RDK_HOST（默认 192.168.5.127）、RDK_USER（root）、RDK_SSH_PASSWORD（root）。

在板卡上执行 scripts/super_query.sh + scripts/w1_line_diag.py，打印全输出。
退出码：0=声纳双路应答；1=有声纳缺失；2=SSH 不可达。
"""

import os
import sys
import time

import paramiko

HOST = os.environ.get("RDK_HOST", "192.168.5.127")
USER = os.environ.get("RDK_USER", "root")
PASSWORD = os.environ.get("RDK_SSH_PASSWORD", "root")


def main() -> int:
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(HOST, username=USER, password=PASSWORD,
                       timeout=12, look_for_keys=False, allow_agent=False)
    except Exception as exc:
        print(f"SSH_FAIL {HOST}: {exc}")
        return 2

    _, out, _ = client.exec_command(
        "cd /home/sunrise/seaUI_rdk && bash scripts/super_query.sh 2>&1", timeout=180)
    query = out.read().decode(errors="replace")
    print(query)

    _, out2, _ = client.exec_command(
        "cd /home/sunrise/seaUI_rdk && python3 scripts/telemetry_snapshot.py 2>&1", timeout=90)
    diag = out2.read().decode(errors="replace")
    print(diag)

    # 1-Wire 总线电平诊断（解绑 w1-gpio -> 读引脚电平 -> 重绑）
    def run(cmd, t=15):
        _, o, _e = client.exec_command(cmd, timeout=t)
        return o.read().decode(errors="replace").strip()

    def unbind_bind(dev, action):
        run("echo %s > /sys/bus/platform/drivers/w1-gpio/%s" % (dev, action))

    def level(gpio):
        run("echo %d > /sys/class/gpio/export" % gpio)
        run("echo in > /sys/class/gpio/gpio%d/direction" % gpio)
        time.sleep(0.05)
        v1 = run("cat /sys/class/gpio/gpio%d/value" % gpio)
        time.sleep(0.3)
        v2 = run("cat /sys/class/gpio/gpio%d/value" % gpio)
        run("echo %d > /sys/class/gpio/unexport" % gpio)
        return v1, v2

    for name, dev, gpio in (("总线1（37脚）", "onewire-0", 401),
                            ("总线2（15脚）", "onewire-1", 388)):
        unbind_bind(dev, "unbind")
        time.sleep(0.3)
        v1, v2 = level(gpio)
        if v1 == v2 == "1":
            verdict = "稳定高电平（上拉在线）"
        elif v1 == v2 == "0":
            verdict = "稳定低电平（无上拉/对地）"
        else:
            verdict = "电平波动（浮空）"
        print(f"1-WIRE_LEVEL {name}: {v1}->{v2} {verdict}")
        unbind_bind(dev, "bind")
        time.sleep(0.3)

    client.close()

    l08_count = query.count("L08_OK")
    l08_fail = query.count("L08_SILENT")
    w1_probes = 0
    for line in query.splitlines():
        if line.startswith("DS18B20"):
            try:
                w1_probes = int(line.split(":")[1].strip().split("（")[0])
            except Exception:
                pass
    print(f"MARKER: L08_OK={l08_count} L08_SILENT={l08_fail} W1_PROBES={w1_probes}")
    if l08_count >= 2 and w1_probes >= 2:
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
