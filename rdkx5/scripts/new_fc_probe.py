#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""新飞控 AUX 输出解剖探针（全程停止值，不转动任何电机）。

在 RDK X5 上运行（网关已停、串口独占）：
    python3 /tmp/new_fc_probe.py

五步：
  1. 心跳与固件类型（mode / MAVLink 版本 / 车型线索）
  2. 参数回读：SERVO9/10/12_FUNCTION、BRD_PWM_COUNT、FRAME_CLASS
  3. 对 ch9 发 DO_SET_SERVO(1000=泵停止档)@2Hz×6s，抓 COMMAND_ACK
  4. 全程抓 SERVO_OUTPUT_RAW：包里是否出现 servo9 字段、值是多少
  5. 对照：对 ch5（MAIN5 垂推，1500 中性）发 DO_SET_SERVO，看 MAIN 侧是否正常
"""

from __future__ import annotations

import time

from pymavlink import mavutil


def read_param(m, name: str, tries: int = 3) -> float | None:
    for _ in range(tries):
        m.mav.param_request_read_send(
            m.target_system, m.target_component, name.encode(), -1,
        )
        value = m.recv_match(type="PARAM_VALUE", blocking=True, timeout=1.2)
        if value is not None and value.param_id.rstrip("\x00") == name:
            return value.param_value
    return None


def send_doset(m, channel: int, pwm: int) -> None:
    m.mav.command_long_send(
        m.target_system, m.target_component,
        183, 0, float(channel), float(pwm), 0, 0, 0, 0, 0,
    )


def main() -> int:
    m = mavutil.mavlink_connection("/dev/ttyACM0", baud=115200)
    if m.wait_heartbeat(timeout=6) is None:
        print("NO_HEARTBEAT")
        return 1
    hb = m.messages.get("HEARTBEAT")
    print(
        f"① 心跳: sysid={m.target_system} compid={m.target_component} "
        f"mode={getattr(m, 'flightmode', '?')} "
        f"armed={bool(hb.base_mode & 1) if hb is not None else '?'} "
        f"mavlink_version={getattr(hb, 'mavlink_version', '?')}"
    )

    print("② 参数回读：")
    for name in ("SERVO9_FUNCTION", "SERVO10_FUNCTION", "SERVO12_FUNCTION",
                 "BRD_PWM_COUNT", "FRAME_CLASS", "SERVO5_FUNCTION"):
        print(f"   {name} = {read_param(m, name)}")

    print("③ DO_SET_SERVO(ch9, 1000=泵停止档) @2Hz×6s：")
    acks: list[tuple[int, int]] = []
    raw_stats = {"packets": 0, "with_servo9": 0, "servo9_values": set()}
    texts: list[str] = []
    start = time.monotonic()
    next_send = 0.0
    while time.monotonic() - start < 6:
        now = time.monotonic()
        if now >= next_send:
            send_doset(m, 9, 1000)
            next_send = now + 0.5
        msg = m.recv_match(blocking=True, timeout=0.2)
        if msg is None:
            continue
        mtype = msg.get_type()
        if mtype == "COMMAND_ACK":
            acks.append((int(msg.command), int(msg.result)))
        elif mtype == "SERVO_OUTPUT_RAW":
            raw_stats["packets"] += 1
            has9 = hasattr(msg, "servo9_raw")
            if has9:
                raw_stats["with_servo9"] += 1
                raw_stats["servo9_values"].add(int(msg.servo9_raw or 0))
        elif mtype == "STATUSTEXT":
            texts.append(f"sev={msg.severity}: {msg.text}")
    in_use = sum(1 for c, r in acks if c == 183 and r == 4)
    ok = sum(1 for c, r in acks if c == 183 and r == 0)
    print(f"   ACK: result=0 ×{ok}, result=4(已被占用) ×{in_use}, 其它 {len(acks)-ok-in_use}")
    print(f"   SERVO_OUTPUT_RAW: {raw_stats['packets']} 包，含 servo9 字段 {raw_stats['with_servo9']}，"
          f"值集合 {sorted(raw_stats['servo9_values']) or '∅'}")
    for t in texts[:6]:
        print(f"   STATUSTEXT {t}")

    print("⑤ 对照组 DO_SET_SERVO(ch5=MAIN5, 1500 中性) ×3：")
    for _ in range(3):
        send_doset(m, 5, 1500)
        time.sleep(0.2)
    main_seen = set()
    t0 = time.monotonic()
    while time.monotonic() - t0 < 3:
        msg = m.recv_match(type="SERVO_OUTPUT_RAW", blocking=True, timeout=0.2)
        if msg is not None:
            main_seen.add(int(getattr(msg, "servo5_raw", 0) or 0))
    print(f"   ch5(MAIN5) 出现过的值: {sorted(main_seen)}")
    m.close()
    print("probe done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
