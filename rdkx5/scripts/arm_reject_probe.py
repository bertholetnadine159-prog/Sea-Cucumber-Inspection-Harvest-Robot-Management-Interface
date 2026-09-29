#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""板上解锁拒绝原因探针（无旋转：中性输出，与网关 auto-arm 行为一致）。

在 RDK X5 上运行（网关已停、串口独占）：
    python3 /tmp/arm_reject_probe.py

发一次 force-arm(400, 21196)，随后 10 秒捕获 STATUSTEXT 与 COMMAND_ACK，
打印飞控给出的拒绝原因。
"""

from __future__ import annotations

import time

from pymavlink import mavutil


def main() -> int:
    m = mavutil.mavlink_connection("/dev/ttyACM0", baud=115200)
    if m.wait_heartbeat(timeout=6) is None:
        print("NO_HEARTBEAT")
        return 1
    hb = m.messages.get("HEARTBEAT")
    print(
        f"heartbeat: sysid={m.target_system} mode={getattr(m, 'flightmode', '?')} "
        f"armed={bool(hb.base_mode & 1) if hb is not None else '?'}"
    )
    m.mav.command_long_send(
        m.target_system, m.target_component,
        400, 0,
        1.0, 21196.0, 0, 0, 0, 0, 0,
    )
    print("force-arm 已发送，捕获回应 10 秒 ...")
    start = time.monotonic()
    while time.monotonic() - start < 10:
        msg = m.recv_match(blocking=True, timeout=0.5)
        if msg is None:
            continue
        mtype = msg.get_type()
        if mtype == "STATUSTEXT":
            print(f"  STATUSTEXT sev={msg.severity}: {msg.text}")
        elif mtype == "COMMAND_ACK":
            print(f"  COMMAND_ACK cmd={msg.command} result={msg.result}")
        elif mtype == "HEARTBEAT":
            print(f"  HEARTBEAT armed={bool(msg.base_mode & 1)}")
    m.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
