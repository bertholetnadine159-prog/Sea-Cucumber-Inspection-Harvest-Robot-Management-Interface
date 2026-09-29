#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""全量参数转储 + AUX 相关可疑参数筛查（板上运行，网关已停）。

python3 /tmp/param_dump.py [--all]

默认只打印 AUX/PWM/TIMER/BRD/SERIAL/RELAY/GPIO 相关参数；
--all 时打印全部（约 700+ 行）。
"""

from __future__ import annotations

import sys
import time

from pymavlink import mavutil

PORT = "/dev/ttyACM0"
KEYWORDS = ("AUX", "PWM", "TIMER", "BRD_", "SERIAL", "RELAY", "GPIO", "FS_", "DISARM", "FRAME")


def main() -> int:
    show_all = "--all" in sys.argv
    m = mavutil.mavlink_connection(PORT, baud=115200)
    if m.wait_heartbeat(timeout=10) is None:
        print("NO_HEARTBEAT")
        return 1
    m.mav.param_request_list_send(m.target_system, m.target_component)
    params: dict[str, float] = {}
    start = time.monotonic()
    while time.monotonic() - start < 25:
        v = m.recv_match(type="PARAM_VALUE", blocking=True, timeout=1.0)
        if v is None:
            if len(params) > 50:
                break
            continue
        params[v.param_id.rstrip("\x00")] = float(v.param_value)
    m.close()
    print(f"共读到 {len(params)} 个参数")
    interesting = {
        k: val for k, val in sorted(params.items())
        if show_all or any(kw in k for kw in KEYWORDS)
    }
    for k, val in interesting.items():
        print(f"{k} = {val}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
