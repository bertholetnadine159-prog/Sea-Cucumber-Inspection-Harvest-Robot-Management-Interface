#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""AUX 掩码假设验证探针（无旋转：灯光=1100 熄灭档、ch13=1000 停止档）。

假设：ArduPilot 的 SERVO_OUTPUT_RAW 只携带"有非 None 功能位的通道"；
AUX 组全 None 时整组被截断，DO_SET_SERVO 的值也不可见。
验证：恢复 SERVO9_FUNCTION=11（Lights1，ArduSub 默认）后，
包内是否长出 AUX 字段、ch13 的 1000 是否可见。

在 RDK X5 上运行（网关已停）：
    python3 /tmp/aux_mask_probe.py
"""

from __future__ import annotations

import time

from pymavlink import mavutil


def main() -> int:
    m = mavutil.mavlink_connection("/dev/ttyACM0", baud=115200)
    if m.wait_heartbeat(timeout=5) is None:
        print("NO_HEARTBEAT")
        return 1
    m.mav.param_set_send(
        m.target_system, m.target_component, b"SERVO9_FUNCTION", 11.0, 7,
    )
    time.sleep(0.5)
    print("SERVO9_FUNCTION=11 (Lights1) 已写入 RAM")

    stat: list[tuple[int, bool, bool, int, int]] = []
    start = time.monotonic()
    next_send = 0.0
    while time.monotonic() - start < 6:
        if time.monotonic() >= next_send:
            m.mav.command_long_send(
                m.target_system, m.target_component,
                183, 0, 13.0, 1000.0, 0, 0, 0, 0, 0,
            )
            next_send = time.monotonic() + 0.5
        msg = m.recv_match(type="SERVO_OUTPUT_RAW", blocking=True, timeout=0.2)
        if msg is not None:
            stat.append((
                int(msg.port or 0),
                hasattr(msg, "servo9_raw"),
                hasattr(msg, "servo13_raw"),
                int(getattr(msg, "servo9_raw", 0) or 0),
                int(getattr(msg, "servo13_raw", 0) or 0),
            ))
    m.close()

    print("samples (port, has9, has13, s9, s13):", stat[:8])
    aux_packets = [s for s in stat if s[1] or s[2]]
    print(f"AUX 字段出现率: {len(aux_packets)}/{len(stat)}")
    if aux_packets:
        print("s9 值:", sorted({s[3] for s in aux_packets}),
              " s13 值:", sorted({s[4] for s in aux_packets}))
        print("verdict: AUX_MASK_REVIVED（掩码假设成立）")
        return 0
    print("verdict: STILL_TRUNCATED（掩码假设不成立，AUX 组仍被截断）")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
