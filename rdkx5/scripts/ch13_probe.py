#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""板上 ch13 单通道无旋转判定探针（泵停止值 1000us，不会转动任何电机）。

在 RDK X5 上运行（网关已停、串口独占）：
    python3 /tmp/ch13_probe.py

流程：打印解锁状态 → 读 SERVO13_FUNCTION / BRD_PWM_COUNT → 以 2Hz 直发
DO_SET_SERVO(13, 1000) 共 6 秒，同时记录 SERVO_OUTPUT_RAW 的 s13/s14。
s13 变 1000 = 引脚 PWM 正常（此前 0 是值未锁存）；恒 0 = 引脚无输出。
"""

from __future__ import annotations

import time

from pymavlink import mavutil


def main() -> int:
    m = mavutil.mavlink_connection("/dev/ttyACM0", baud=115200)
    if m.wait_heartbeat(timeout=5) is None:
        print("NO_HEARTBEAT")
        return 1
    hb = m.messages.get("HEARTBEAT")
    print("armed:", bool(hb is not None and (hb.base_mode & 1)))

    def read_param(name: str) -> float | None:
        for _ in range(3):
            m.mav.param_request_read_send(
                m.target_system, m.target_component, name.encode(), -1,
            )
            value = m.recv_match(type="PARAM_VALUE", blocking=True, timeout=1.2)
            if value is not None and value.param_id.rstrip("\x00") == name:
                return value.param_value
        return None

    print("SERVO13_FUNCTION:", read_param("SERVO13_FUNCTION"))
    print("BRD_PWM_COUNT:", read_param("BRD_PWM_COUNT"))

    samples: list[tuple[int, bool, int]] = []
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
            has_aux = hasattr(msg, "servo13_raw")
            samples.append((int(msg.port or 0), has_aux, int(getattr(msg, "servo13_raw", 0) or 0)))
    ports = sorted({s[0] for s in samples})
    with_aux = sum(1 for s in samples if s[1])
    s13_values = sorted({s[2] for s in samples if s[1]})
    print("ports seen:", ports, f" samples={len(samples)} with_aux_fields={with_aux}")
    print("s13 values (when present):", s13_values)
    verdict = "AUX_ALIVE（包含 AUX 字段且有值）" if with_aux > 0 and s13_values else "AUX_FIELDS_ABSENT（包被截断，AUX 未激活）"
    print("verdict:", verdict)
    m.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
