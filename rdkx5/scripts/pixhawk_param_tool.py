#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""板上参数核查/修复/重启工具（配合 246 重启持久化验证）。

模式：
  --mode read     只读：打印关键参数当前值
  --mode fix      写：SERVO5-8_FUNCTION=0、SERVO9-16_FUNCTION=0、
                  DISARM_DELAY=0、FRAME_CLASS=2、BRD_PWM_COUNT=6，
                  逐条回读确认，然后发 MAVLink 246 重启

在 RDK X5 上运行（网关已停、串口独占）。绝不发任何电机转动指令。
"""

from __future__ import annotations

import argparse
import time

READ_PARAMS = [
    "SERVO5_FUNCTION", "SERVO6_FUNCTION", "SERVO7_FUNCTION", "SERVO8_FUNCTION",
    "SERVO9_FUNCTION", "SERVO11_FUNCTION", "SERVO12_FUNCTION",
    "DISARM_DELAY", "FRAME_CLASS", "BRD_PWM_COUNT",
]
WRITE_PLAN = [
    ("SERVO5_FUNCTION", 0), ("SERVO6_FUNCTION", 0),
    ("SERVO7_FUNCTION", 0), ("SERVO8_FUNCTION", 0),
    # 2026-09-30 重接线：泵=AUX1/2（ch9/10）、舵机=AUX3（ch11）直控
    ("SERVO9_FUNCTION", 0), ("SERVO10_FUNCTION", 0),
    ("SERVO11_FUNCTION", 0),
    # SERVO12 保持 11 (Lights1, ArduSub 默认)：AUX 组需要一个非 None 功能位，
    # 否则 SERVO_OUTPUT_RAW 的 AUX 字段整组被截断、泵通道值不可见（实测）。
    # 锚点原在 SERVO9，泵改接 AUX1/ch9 后挪到未接外设的 SERVO12（AUX4）
    ("SERVO12_FUNCTION", 11),
    ("SERVO13_FUNCTION", 0),
    ("SERVO14_FUNCTION", 0),
    ("SERVO15_FUNCTION", 0), ("SERVO16_FUNCTION", 0),
    ("DISARM_DELAY", 0), ("FRAME_CLASS", 2), ("BRD_PWM_COUNT", 6),
]


def main() -> int:
    parser = argparse.ArgumentParser(description="参数核查/修复/重启")
    parser.add_argument("--port", default="/dev/ttyACM0")
    parser.add_argument("--mode", choices=("read", "fix"), default="read")
    parser.add_argument(
        "--brd-count", type=int, default=None,
        help="fix 模式下覆盖 BRD_PWM_COUNT 写入值（默认 6；存储失步时改值可强制落盘）",
    )
    parser.add_argument(
        "--no-reboot", action="store_true",
        help="fix 模式只写参数不发重启（配合外部延迟重启验证慢落盘）",
    )
    parser.add_argument(
        "--mode-reboot", action="store_true",
        help="只发 MAVLink 246 重启，不写任何参数",
    )
    args = parser.parse_args()

    from pymavlink import mavutil

    master = mavutil.mavlink_connection(args.port, baud=115200)
    if master.wait_heartbeat(timeout=5.0) is None:
        print("[param] NO_HEARTBEAT")
        return 1

    def read_param(name: str, timeout: float = 1.5) -> float | None:
        for _ in range(3):  # 忙链路重试
            master.mav.param_request_read_send(
                master.target_system, master.target_component, name.encode(), -1,
            )
            msg = master.recv_match(type="PARAM_VALUE", blocking=True, timeout=timeout)
            if msg is not None and msg.param_id.rstrip("\x00") == name:
                return float(msg.param_value)
        return None

    if args.mode_reboot:
        print("发送 MAVLink 246 重启 ...")
        master.mav.command_long_send(
            master.target_system, master.target_component, 246, 0, 1, 0, 0, 0, 0, 0, 0,
        )
        time.sleep(1.0)
        master.close()
        return 0

    if args.mode == "read":
        for name in READ_PARAMS:
            value = read_param(name)
            print(f"  {name} = {value}")
        master.close()
        return 0

    # fix 模式
    brd_count = args.brd_count if args.brd_count is not None else 6
    write_plan = [(name, value) for name, value in WRITE_PLAN if name != "BRD_PWM_COUNT"]
    write_plan.append(("BRD_PWM_COUNT", brd_count))
    failures = []
    for name, value in write_plan:
        master.mav.param_set_send(
            master.target_system, master.target_component,
            name.encode(), float(value), 7,  # MAV_PARAM_TYPE_REAL32
        )
        got = None
        deadline = time.monotonic() + 2.0
        while time.monotonic() < deadline:
            msg = master.recv_match(type="PARAM_VALUE", blocking=True, timeout=0.4)
            if msg is not None and msg.param_id.rstrip("\x00") == name:
                got = float(msg.param_value)
                break
        ok = got is not None and abs(got - value) < 1e-6
        if not ok:
            failures.append(name)
        print(f"  {name}={value} readback={got} {'OK' if ok else 'FAIL'}")
    time.sleep(2.0)  # 给参数存储落盘留窗口

    readback = {name: read_param(name) for name in READ_PARAMS}
    print("----- 写后回读 -----")
    for name, value in readback.items():
        print(f"  {name} = {value}")

    if args.no_reboot:
        master.close()
        print("[param] fix done (no reboot); failures:", failures or "none")
        return 0 if not failures else 2

    print("发送 MAVLink 246 重启 ...")
    master.mav.command_long_send(
        master.target_system, master.target_component, 246, 0, 1, 0, 0, 0, 0, 0, 0,
    )
    time.sleep(1.0)
    master.close()
    print("[param] fix done; failures:", failures or "none")
    return 0 if not failures else 2


if __name__ == "__main__":
    raise SystemExit(main())
