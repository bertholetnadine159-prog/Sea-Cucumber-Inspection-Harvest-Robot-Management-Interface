#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""板上泵信号闭环探针：直发 DO_SET_SERVO 并记录 SERVO_OUTPUT_RAW 实际输出。

在 RDK X5 上运行（先停网关独占串口）：
    python3 /tmp/pump_signal_probe.py

流程：连接 → 内置 10 秒倒计时（铁则）→ 3 秒内 4Hz 直发
DO_SET_SERVO(13/14, 1200us) → 统计 s13/s14 实际输出 min/max → 收回 1000。
1200us = 泵量程（1000-2000）的 20%（用户约束）。
"""

from __future__ import annotations

import argparse
import time

DEFAULT_PORT = "/dev/ttyACM0"
PUMP_PWM = 1200
STOP_PWM = 1000
CHANNELS = (13, 14)


def main() -> int:
    parser = argparse.ArgumentParser(description="泵信号闭环探针")
    parser.add_argument("--port", default=DEFAULT_PORT)
    parser.add_argument("--seconds", type=float, default=3.0)
    args = parser.parse_args()

    from pymavlink import mavutil

    master = mavutil.mavlink_connection(args.port, baud=115200)
    hb = master.wait_heartbeat(timeout=5.0)
    if hb is None:
        print("[probe] NO_HEARTBEAT")
        return 1
    print(f"[probe] heartbeat srcSystem={master.target_system}")

    print("即将转动：泵1(ch13)、泵2(ch14)，1200us（20%），持续 3 秒")
    for remain in range(10, 0, -1):
        print(f"  倒计时 {remain} ...")
        time.sleep(1.0)
    print(">>> 开始 <<<")

    stats = {ch: [None, None] for ch in CHANNELS}
    deadline = time.monotonic() + args.seconds
    next_send = 0.0
    while time.monotonic() < deadline:
        now = time.monotonic()
        if now >= next_send:
            for ch in CHANNELS:
                master.mav.command_long_send(
                    master.target_system, master.target_component,
                    183, 0, float(ch), float(PUMP_PWM), 0, 0, 0, 0, 0,
                )
            next_send = now + 0.25
        msg = master.recv_match(type="SERVO_OUTPUT_RAW", blocking=True, timeout=0.1)
        if msg is not None:
            for ch in CHANNELS:
                value = int(getattr(msg, f"servo{ch}_raw", 0) or 0)
                lo, hi = stats[ch]
                stats[ch] = [value if lo is None else min(lo, value),
                             value if hi is None else max(hi, value)]

    for ch in CHANNELS:
        master.mav.command_long_send(
            master.target_system, master.target_component,
            183, 0, float(ch), float(STOP_PWM), 0, 0, 0, 0, 0,
        )
    master.close()

    print("===== 结果（目标 1200us） =====")
    ok = True
    for ch in CHANNELS:
        lo, hi = stats[ch]
        hit = lo is not None and hi >= 1170
        ok = ok and hit
        print(f"  ch{ch}: 实际输出 {lo}..{hi} us  ->  {'已输出' if hit else '未达标'}")
    print("[probe] VERDICT:", "PUMP_PWM_OK" if ok else "PUMP_PWM_FAIL")
    return 0 if ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
