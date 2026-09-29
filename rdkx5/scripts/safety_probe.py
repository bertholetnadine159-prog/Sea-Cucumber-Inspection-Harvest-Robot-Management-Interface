#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""安全开关参数探针（只读，无电机动作）。

在 RDK X5 上运行（网关已停、串口独占）：
    python3 /tmp/safety_probe.py

读 BRD_SAFETYENABLE / BRD_SAFETY_MASK / BRD_SAFETY_OPTION / BRD_IO_SAFETY。
"""

from __future__ import annotations

from pymavlink import mavutil


def main() -> int:
    m = mavutil.mavlink_connection("/dev/ttyACM0", baud=115200)
    if m.wait_heartbeat(timeout=6) is None:
        print("NO_HEARTBEAT")
        return 1

    def read_param(name: str, tries: int = 3) -> float | None:
        for _ in range(tries):
            m.mav.param_request_read_send(
                m.target_system, m.target_component, name.encode(), -1,
            )
            value = m.recv_match(type="PARAM_VALUE", blocking=True, timeout=1.2)
            if value is not None and value.param_id.rstrip("\x00") == name:
                return value.param_value
        return None

    for name in ("BRD_SAFETYENABLE", "BRD_SAFETY_MASK", "BRD_SAFETY_OPTION", "BRD_IO_SAFETY"):
        print(f"{name} = {read_param(name)}")
    m.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
