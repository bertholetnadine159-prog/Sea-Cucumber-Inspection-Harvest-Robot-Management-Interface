#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""清除 AUX 引脚占用（RELAY/串口复用）→ 重启 → 判定 AUX PWM 是否复活。

板上运行（网关已停）：python3 /tmp/aux_unclaim.py

依据：全量参数转储发现 RELAY_PIN=54 / RELAY_PIN2=55（PX4 上 GPIO 50-55
=AUX1-6，被 RELAY 以 GPIO 方式占用的引脚不再输出 PWM）。清除后重启，
若 SERVO_OUTPUT_RAW 出现 servo9 字段 = 引脚归还 PWM，问题解决。
"""

from __future__ import annotations

import time

from pymavlink import mavutil

PORT = "/dev/ttyACM0"

CLEANUP = [
    ("RELAY_PIN", -1.0),
    ("RELAY_PIN2", -1.0),
    ("RELAY_PIN3", -1.0),
    ("RELAY_PIN4", -1.0),
    ("RELAY_PIN5", -1.0),
    ("RELAY_PIN6", -1.0),
    ("SERIAL4_PROTOCOL", -1.0),
    ("SERIAL5_PROTOCOL", -1.0),
    ("BRD_OPTIONS", 0.0),
]


def connect(timeout: float = 12.0):
    m = mavutil.mavlink_connection(PORT, baud=115200)
    if m.wait_heartbeat(timeout=timeout) is None:
        raise RuntimeError("NO_HEARTBEAT")
    return m


def read_param(m, name, tries=3):
    for _ in range(tries):
        m.mav.param_request_read_send(m.target_system, m.target_component, name.encode(), -1)
        v = m.recv_match(type="PARAM_VALUE", blocking=True, timeout=1.5)
        if v is not None and v.param_id.rstrip("\x00") == name:
            return float(v.param_value)
    return None


def write_param(m, name, value):
    m.mav.param_set_send(m.target_system, m.target_component, name.encode(), value, 7)
    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline:
        v = m.recv_match(type="PARAM_VALUE", blocking=True, timeout=0.5)
        if v is not None and v.param_id.rstrip("\x00") == name:
            return float(v.param_value)
    return None


def listen_aux(m, seconds: float) -> dict:
    stats = {"packets": 0, "with_aux": 0, "s9": set()}
    start = time.monotonic()
    while time.monotonic() - start < seconds:
        msg = m.recv_match(type="SERVO_OUTPUT_RAW", blocking=True, timeout=0.3)
        if msg is None:
            continue
        stats["packets"] += 1
        if hasattr(msg, "servo9_raw"):
            stats["with_aux"] += 1
            stats["s9"].add(int(getattr(msg, "servo9_raw", 0) or 0))
    return stats


def main() -> int:
    m = connect()
    print("清理前：RELAY_PIN=%s RELAY_PIN2=%s BRD_OPTIONS=%s" % (
        read_param(m, "RELAY_PIN"), read_param(m, "RELAY_PIN2"), read_param(m, "BRD_OPTIONS")))
    for name, value in CLEANUP:
        got = write_param(m, name, value)
        print(f"  {name} -> {value} (回读 {got})")
    m.mav.command_long_send(m.target_system, m.target_component, 400, 0, 0.0, 21196.0, 0, 0, 0, 0, 0)
    m.recv_match(type="COMMAND_ACK", blocking=True, timeout=3.0)
    m.mav.command_long_send(m.target_system, m.target_component, 246, 0, 1, 0, 0, 0, 0, 0, 0)
    time.sleep(1.0)
    m.close()
    print("已重启，等待 28 秒 ...")
    time.sleep(28)

    m = connect()
    print("重启后：RELAY_PIN=%s RELAY_PIN2=%s BRD_PWM_COUNT=%s" % (
        read_param(m, "RELAY_PIN"), read_param(m, "RELAY_PIN2"), read_param(m, "BRD_PWM_COUNT")))
    stats = listen_aux(m, 8.0)
    print(f"RAW: {stats['packets']} 包, 含 AUX 字段 {stats['with_aux']}, s9={sorted(stats['s9']) or '∅'}")
    if stats["with_aux"] > 0:
        print("VERDICT: AUX_REVIVED_BY_UNCLAIM —— 引脚占用清除后 AUX PWM 复活！")
        m.close()
        return 0
    print("VERDICT: STILL_DEAD —— 清除占用无效，硬件定案维持")
    m.close()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
