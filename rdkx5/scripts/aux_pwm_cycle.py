#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""AUX PWM 模式判定与复活实验（网关必须已停，全程无电机动作）。

回答用户问题："AUX 是不是根本没切换成 PWM？"

三段式：
  A. 干净重启（disarm + 246）→ 读开机真实参数 + 听 SERVO_OUTPUT_RAW 是否带 AUX 字段
     ——这是"开机时刻 PWM 是否激活"的纯净判据（此前读数都被网关运行时写污染）
  B. 写 BRD_PWM_COUNT=0（强制存储翻转）→ 重启 → 复读（应=0）+ 听字段
  C. 写 BRD_PWM_COUNT=6 → 重启 → 复读（应=6，持久化铁证）+ 听字段
     ——C 段字段出现 = AUX 复活（用户的猜测正确，0→6 循环重建了定时器初始化）

用法（板上）：python3 /tmp/aux_pwm_cycle.py
"""

from __future__ import annotations

import time

from pymavlink import mavutil

PORT = "/dev/ttyACM0"
LISTEN_S = 6.0


def connect(timeout: float = 12.0):
    m = mavutil.mavlink_connection(PORT, baud=115200)
    hb = m.wait_heartbeat(timeout=timeout)
    if hb is None:
        raise RuntimeError("NO_HEARTBEAT")
    return m


def disarm(m) -> bool:
    m.mav.command_long_send(
        m.target_system, m.target_component, 400, 0, 0.0, 21196.0, 0, 0, 0, 0, 0,
    )
    ack = m.recv_match(type="COMMAND_ACK", blocking=True, timeout=3.0)
    return ack is not None and int(ack.result) == 0


def reboot_fc(m) -> None:
    m.mav.command_long_send(
        m.target_system, m.target_component, 246, 0, 1, 0, 0, 0, 0, 0, 0,
    )
    time.sleep(1.0)


def read_param(m, name: str, tries: int = 3):
    for _ in range(tries):
        m.mav.param_request_read_send(m.target_system, m.target_component, name.encode(), -1)
        v = m.recv_match(type="PARAM_VALUE", blocking=True, timeout=1.5)
        if v is not None and v.param_id.rstrip("\x00") == name:
            return float(v.param_value)
    return None


def write_param(m, name: str, value: float) -> None:
    m.mav.param_set_send(m.target_system, m.target_component, name.encode(), value, 7)
    deadline = time.monotonic() + 2.0
    while time.monotonic() < deadline:
        v = m.recv_match(type="PARAM_VALUE", blocking=True, timeout=0.5)
        if v is not None and v.param_id.rstrip("\x00") == name:
            return


def listen_aux(m, seconds: float) -> dict:
    stats = {"packets": 0, "with_aux": 0, "values": set()}
    start = time.monotonic()
    while time.monotonic() - start < seconds:
        msg = m.recv_match(type="SERVO_OUTPUT_RAW", blocking=True, timeout=0.3)
        if msg is None:
            continue
        stats["packets"] += 1
        if hasattr(msg, "servo9_raw"):
            stats["with_aux"] += 1
            stats["values"].add(int(getattr(msg, "servo9_raw", 0) or 0))
    return stats


def stage(label: str, expect_count: float | None) -> dict:
    m = connect()
    armed_hb = m.messages.get("HEARTBEAT")
    armed = bool(armed_hb is not None and (armed_hb.base_mode & 1))
    count = read_param(m, "BRD_PWM_COUNT")
    f9 = read_param(m, "SERVO9_FUNCTION")
    f10 = read_param(m, "SERVO10_FUNCTION")
    f11 = read_param(m, "SERVO11_FUNCTION")
    t9 = read_param(m, "SERVO9_TRIM")
    stats = listen_aux(m, LISTEN_S)
    print(f"[{label}] armed={armed} BRD_PWM_COUNT={count} (期望 {expect_count}) "
          f"F9={f9} F10={f10} F11={f11} T9={t9}")
    print(f"[{label}] RAW: {stats['packets']} 包, 含 AUX 字段 {stats['with_aux']}, "
          f"servo9 值 {sorted(stats['values']) or '∅'}")
    verdict = "PWM 激活" if stats["with_aux"] > 0 else "AUX 无输出"
    print(f"[{label}] 判定: {verdict}")
    return {"m": m, "count": count, "aux_active": stats["with_aux"] > 0}


def main() -> int:
    print("===== A. 干净重启后读开机真实状态 =====")
    m = connect()
    ok = disarm(m)
    print(f"disarm: {ok}")
    reboot_fc(m)
    m.close()
    time.sleep(28)
    a = stage("A", None)
    a["m"].close()

    print("\n===== B. 写 BRD_PWM_COUNT=0 → 重启 =====")
    m = connect()
    write_param(m, "BRD_PWM_COUNT", 0.0)
    print("已写 0")
    disarm(m)
    reboot_fc(m)
    m.close()
    time.sleep(28)
    b = stage("B", 0.0)
    b["m"].close()

    print("\n===== C. 写 BRD_PWM_COUNT=6 → 重启 =====")
    m = connect()
    write_param(m, "BRD_PWM_COUNT", 6.0)
    print("已写 6")
    disarm(m)
    reboot_fc(m)
    m.close()
    time.sleep(28)
    c = stage("C", 6.0)
    c["m"].close()

    print("\n===== 总结 =====")
    print(f"A(重启后原值): count={a['count']} aux={'活' if a['aux_active'] else '死'}")
    print(f"B(=0 重启):    count={b['count']} aux={'活' if b['aux_active'] else '死'}")
    print(f"C(=6 重启):    count={c['count']} aux={'活' if c['aux_active'] else '死'}")
    if c["aux_active"]:
        print("VERDICT: AUX_PWM_REVIVED —— 用户猜测正确（0→6 循环重建定时器初始化）")
        return 0
    if a["count"] != 6.0:
        print("VERDICT: BOOT_PARAM_NOT_PERSISTED —— 开机值未生效（存储问题实锤）")
    else:
        print("VERDICT: PWM_PARAM_IGNORED —— 开机 count=6 仍无 AUX（固件/板级拒绝）")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
