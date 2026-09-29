#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""D 段实验：RC override 保活状态下 AUX 是否复活（判定 FS_PILOT_INPUT 假说）。

板上运行（网关已停）：python3 /tmp/aux_fs_probe.py

流程：连接 → 先裸听 4s（基线：应无 AUX 字段）→ 以 10Hz 发
RC_CHANNELS_OVERRIDE（全 1500）+ 1Hz GCS 心跳持续 8s，期间持续听
SERVO_OUTPUT_RAW → 停发再听 4s。AUX 字段在保活期间出现 = FS 失控保护
一直在门控 FMU 侧输出（"硬件死亡"定案为假象）。
"""

from __future__ import annotations

import time

from pymavlink import mavutil

PORT = "/dev/ttyACM0"


def listen(m, seconds: float, pumper=None) -> dict:
    stats = {"packets": 0, "with_aux": 0, "s9": set(), "s11": set()}
    start = time.monotonic()
    next_ovr = 0.0
    next_hb = 0.0
    while time.monotonic() - start < seconds:
        now = time.monotonic()
        if pumper is not None:
            if now >= next_ovr:
                pumper()
                next_ovr = now + 0.1
            if now >= next_hb:
                m.mav.heartbeat_send(6, 8, 0, 0, 0)
                next_hb = now + 1.0
        msg = m.recv_match(type="SERVO_OUTPUT_RAW", blocking=True, timeout=0.15)
        if msg is None:
            continue
        stats["packets"] += 1
        if hasattr(msg, "servo9_raw"):
            stats["with_aux"] += 1
            stats["s9"].add(int(getattr(msg, "servo9_raw", 0) or 0))
            stats["s11"].add(int(getattr(msg, "servo11_raw", 0) or 0))
    return stats


def report(label: str, stats: dict) -> None:
    print(f"[{label}] {stats['packets']} 包, 含 AUX {stats['with_aux']}, "
          f"s9={sorted(stats['s9']) or '∅'} s11={sorted(stats['s11']) or '∅'}")


def main() -> int:
    m = mavutil.mavlink_connection(PORT, baud=115200)
    if m.wait_heartbeat(timeout=10) is None:
        print("NO_HEARTBEAT")
        return 1
    hb = m.messages.get("HEARTBEAT")
    print(f"armed={bool(hb is not None and hb.base_mode & 1)}")

    def pump_override():
        m.mav.rc_channels_override_send(
            m.target_system, m.target_component,
            65535, 65535, 65535, 65535, 65535, 65535, 65535, 65535,
        )

    report("裸听基线", listen(m, 4.0))
    report("RC保活中", listen(m, 8.0, pumper=pump_override))
    report("保活停止后", listen(m, 4.0))
    m.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
