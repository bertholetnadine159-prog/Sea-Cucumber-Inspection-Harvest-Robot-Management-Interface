#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# [RDK X5 side] Pixhawk arm 诊断工具
#
# 用途：在不动网关的情况下直接连接 Pixhawk，读取 PreArm/STATUSTEXT/COMMAND_ACK，
#       定位上锁被拒的原因；可选做一次“正常 arm -> 立即 disarm”的实机验证。
#
# 安全约束：
#   * 默认只读诊断，不发送任何 arm 命令；
#   * 只有同时显式传入 --arm 和 --i-confirm-propellers-removed 才会尝试 arm；
#   * arm 后立刻 disarm，任何异常也会走 finally 兜底 disarm；
#   * 绝不使用 force bypass 上锁，只读原因，由人决定下一步。
#
# 用法：
#   python3 tools/pixhawk_arm_probe.py                       # 只读诊断
#   python3 tools/pixhawk_arm_probe.py --arm --i-confirm-propellers-removed
# ============================================================================
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path


ARM_FORCE_MAGIC = 21196


def resolve_connection(configured: str) -> str:
    if Path(configured).exists():
        return configured
    by_id = Path("/dev/serial/by-id")
    if by_id.exists():
        for candidate in sorted(by_id.glob("usb-*")):
            lowered = candidate.name.lower()
            if "pixhawk" in lowered or "ardupilot" in lowered:
                return str(candidate)
    acm = sorted(Path("/dev").glob("ttyACM*"))
    if acm:
        return str(acm[0])
    return configured


def enum_name(mavlink: object, group: str, value: int) -> str:
    mapping = getattr(mavlink, "enums", {}).get(group, {})
    entry = mapping.get(value)
    if entry is not None:
        name = getattr(entry, "name", None)
        if isinstance(name, str) and name:
            return f"{name} ({value})"
    try:
        enum_cls = getattr(mavlink, group)
        member = enum_cls(value)
        name = getattr(member, "name", None)
        if isinstance(name, str) and name:
            return f"{name} ({value})"
        return f"{member} ({value})"
    except Exception:
        return f"UNKNOWN ({value})"


def collect_messages(master: object, seconds: float):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        message = master.recv_match(blocking=True, timeout=0.25)
        if message is None:
            continue
        yield message


def read_param(master: object, system: int, component: int, name: str, timeout: float = 3.0):
    master.mav.param_request_read_send(system, component, name.encode("ascii"), -1)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        message = master.recv_match(type="PARAM_VALUE", blocking=True, timeout=0.25)
        if message is None:
            continue
        if message.param_id.rstrip("\x00") == name:
            return float(message.param_value)
    return None


def request_context(master: object, system: int, component: int, mavutil: object) -> None:
    """仅做一次性请求（固件版本/能力）。不要请求周期数据流：旧 ArduSub 会崩溃重启。"""
    try:
        master.mav.command_long_send(
            system,
            component,
            mavutil.mavlink.MAV_CMD_REQUEST_MESSAGE,
            0,
            mavutil.mavlink.MAVLINK_MSG_ID_AUTOPILOT_VERSION,
            0,
            0,
            0,
            0,
            0,
            0,
        )
        master.mav.command_long_send(
            system,
            component,
            mavutil.mavlink.MAV_CMD_REQUEST_AUTOPILOT_CAPABILITIES,
            0,
            1,
            0,
            0,
            0,
            0,
            0,
            0,
        )
    except Exception as exc:
        print(f"[probe] request_context failed: {exc}", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Pixhawk arm probe (RDK X5 side)")
    parser.add_argument("--connection", default="/dev/ttyACM0")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--arm", action="store_true", help="attempt one normal arm (then disarm)")
    parser.add_argument(
        "--i-confirm-propellers-removed",
        action="store_true",
        help="required together with --arm; confirms propellers are physically removed",
    )
    parser.add_argument(
        "--sweep-z",
        action="store_true",
        help="arm, then sweep MANUAL_CONTROL z values and print SERVO_OUTPUT_RAW (props must be removed)",
    )
    parser.add_argument(
        "--watch",
        type=float,
        default=0.0,
        help="read-only: after baseline, keep printing STATUSTEXT/HEARTBEAT for N seconds",
    )
    args = parser.parse_args()

    if (args.arm or args.sweep_z) and not args.i_confirm_propellers_removed:
        print("[probe] refusing to arm: --i-confirm-propellers-removed is required", file=sys.stderr)
        return 2

    try:
        from pymavlink import mavutil
    except Exception as exc:
        print(f"[probe] pymavlink unavailable: {exc}", file=sys.stderr)
        return 2

    connection = resolve_connection(args.connection)
    print(f"[probe] connecting {connection} @ {args.baud}", flush=True)
    master = mavutil.mavlink_connection(connection, baud=args.baud)
    master.wait_heartbeat(timeout=8.0)
    system = master.target_system
    component = master.target_component
    print(f"[probe] heartbeat OK system={system} component={component}", flush=True)

    def hb_snapshot() -> str:
        flightmode = getattr(master, "flightmode", "") or "?"
        return f"mode={flightmode} armed={bool(master.motors_armed())}"

    print(f"[baseline] {hb_snapshot()}", flush=True)
    request_context(master, system, component, mavutil)

    for name in (
        "ARMING_CHECK",
        "BATT_MONITOR",
        "RC1_MIN",
        "RC1_MAX",
        "RC1_TRIM",
        "RC2_TRIM",
        "RC3_TRIM",
        "RC4_TRIM",
        "RC5_TRIM",
        "RC6_TRIM",
        "RC7_TRIM",
        "RC8_TRIM",
        "FRAME_CONFIG",
        "MOT_PWM_MIN",
        "MOT_PWM_MAX",
        "FS_THR_ENABLE",
        "FS_GCS_ENABL",
        "BRD_VBUS_MIN",
        "BRD_SAFETYENABLE",
        "SERVO1_FUNCTION",
        "SERVO2_FUNCTION",
        "SERVO3_FUNCTION",
        "SERVO4_FUNCTION",
        "SERVO5_FUNCTION",
        "SERVO6_FUNCTION",
        "SERVO7_FUNCTION",
        "SERVO8_FUNCTION",
        "SERVO9_FUNCTION",
        "SERVO10_FUNCTION",
        "SERVO11_FUNCTION",
    ):
        value = read_param(master, system, component, name)
        if value is None:
            print(f"[param] {name} read timed out", flush=True)
        else:
            print(f"[param] {name}={value}", flush=True)

    # 排空现有消息，避免把历史消息误当成本次 arm 的原因。
    print("[baseline] draining 6s of backlog", flush=True)
    for message in collect_messages(master, 6.0):
        mtype = message.get_type()
        if mtype == "STATUSTEXT":
            print(
                f"[baseline-status] sev={enum_name(mavutil.mavlink, 'MAV_SEVERITY', message.severity)} "
                f"text={message.text!r}",
                flush=True,
            )
        elif mtype == "AUTOPILOT_VERSION":
            print(
                f"[autopilot] flight_sw={message.flight_sw_version} "
                f"middleware={message.middleware_sw_version} "
                f"os={message.os_sw_version} board={message.board_version}",
                flush=True,
            )

    if not args.arm and not args.sweep_z:
        if args.watch > 0:
            print(f"[watch] listening {args.watch:.0f}s without sending traffic", flush=True)
            for message in collect_messages(master, args.watch):
                mtype = message.get_type()
                if mtype == "STATUSTEXT":
                    print(
                        f"[watch-status] sev={enum_name(mavutil.mavlink, 'MAV_SEVERITY', message.severity)} "
                        f"text={message.text!r}",
                        flush=True,
                    )
                elif mtype == "HEARTBEAT":
                    print(f"[watch-hb] {hb_snapshot()}", flush=True)
        print("[probe] read-only mode: not sending arm. Add --arm --i-confirm-propellers-removed to test.")
        master.close()
        return 0

    attempt_armed = False
    try:
        if args.sweep_z:
            if not bool(master.motors_armed()):
                print("[sweep] arming first", flush=True)
                master.mav.command_long_send(
                    system,
                    component,
                    mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM,
                    0,
                    1,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                )
                time.sleep(1.0)
            print(f"[sweep] armed={bool(master.motors_armed())}", flush=True)
            for z_value in (-1000, -500, 0, 250, 500, 750, 1000):
                master.mav.manual_control_send(system, 0, 0, int(z_value), 0, 0)
                servo = None
                for message in collect_messages(master, 1.0):
                    if message.get_type() == "SERVO_OUTPUT_RAW":
                        servo = [int(getattr(message, f"servo{i}_raw", 0) or 0) for i in range(1, 9)]
                print(f"[sweep] z={z_value} pwm={servo}", flush=True)
        else:
            if bool(master.motors_armed()):
                print("[probe] already armed; will disarm at the end", flush=True)
            else:
                print("[arm] sending normal arm (force=0)", flush=True)
                master.mav.command_long_send(
                    system,
                    component,
                    mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM,
                    0,
                    1,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                )
            print("[arm] collecting ACK/STATUSTEXT/SYS_STATUS for 8s", flush=True)
            saw_ack = False
            for message in collect_messages(master, 8.0):
                mtype = message.get_type()
                if mtype == "COMMAND_ACK":
                    saw_ack = True
                    print(
                        f"[ack] command={enum_name(mavutil.mavlink, 'MAV_CMD', message.command)} "
                        f"result={enum_name(mavutil.mavlink, 'MAV_RESULT', message.result)}",
                        flush=True,
                    )
                elif mtype == "STATUSTEXT":
                    print(
                        f"[status] sev={enum_name(mavutil.mavlink, 'MAV_SEVERITY', message.severity)} "
                        f"text={message.text!r}",
                        flush=True,
                    )
                elif mtype == "SYS_STATUS":
                    print(
                        f"[sys] sensors_health=0x{message.onboard_control_sensors_health:x} "
                        f"battery={message.voltage_battery / 1000.0:.2f}V",
                        flush=True,
                    )
                elif mtype == "HEARTBEAT":
                    print(f"[hb] {hb_snapshot()}", flush=True)
            if not saw_ack:
                print("[ack] no COMMAND_ACK within 8s (link may have dropped)", flush=True)
            attempt_armed = bool(master.motors_armed())
            print(f"[arm-result] armed={attempt_armed}", flush=True)

        if not args.sweep_z and not attempt_armed:
            print("[prearm] sending MAV_CMD_RUN_PREARM_CHECKS", flush=True)
            master.mav.command_long_send(
                system,
                component,
                mavutil.mavlink.MAV_CMD_RUN_PREARM_CHECKS,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
            )
            print("[prearm] collecting 8s", flush=True)
            for message in collect_messages(master, 8.0):
                mtype = message.get_type()
                if mtype == "COMMAND_ACK":
                    print(
                        f"[ack] command={enum_name(mavutil.mavlink, 'MAV_CMD', message.command)} "
                        f"result={enum_name(mavutil.mavlink, 'MAV_RESULT', message.result)}",
                        flush=True,
                    )
                elif mtype == "STATUSTEXT":
                    print(
                        f"[status] sev={enum_name(mavutil.mavlink, 'MAV_SEVERITY', message.severity)} "
                        f"text={message.text!r}",
                        flush=True,
                    )
                elif mtype == "SYS_STATUS":
                    print(
                        f"[sys] sensors_health=0x{message.onboard_control_sensors_health:x} "
                        f"battery={message.voltage_battery / 1000.0:.2f}V",
                        flush=True,
                    )
    finally:
        disarm_and_report(master, system, component, mavutil)

    master.close()
    return 0


def disarm_and_report(master: object, system: int, component: int, mavutil: object) -> None:
    try:
        # 先刷新 HEARTBEAT，避免用上一次 arm 命令前的陈旧状态做判断。
        for _ in collect_messages(master, 1.5):
            pass
        if not bool(master.motors_armed()):
            print("[disarm] not armed, nothing to disarm", flush=True)
            return
        print("[disarm] sending normal disarm", flush=True)
        master.mav.command_long_send(
            system,
            component,
            mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
        )
        for message in collect_messages(master, 2.0):
            if message.get_type() == "COMMAND_ACK":
                print(
                    f"[ack] command={enum_name(mavutil.mavlink, 'MAV_CMD', message.command)} "
                    f"result={enum_name(mavutil.mavlink, 'MAV_RESULT', message.result)}",
                    flush=True,
                )
        if not bool(master.motors_armed()):
            print("[disarm-result] armed=false", flush=True)
            return
        print("[disarm] still armed; sending force disarm (magic=21196)", flush=True)
        master.mav.command_long_send(
            system,
            component,
            mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM,
            0,
            0,
            ARM_FORCE_MAGIC,
            0,
            0,
            0,
            0,
            0,
        )
        for message in collect_messages(master, 2.0):
            if message.get_type() == "COMMAND_ACK":
                print(
                    f"[ack] command={enum_name(mavutil.mavlink, 'MAV_CMD', message.command)} "
                    f"result={enum_name(mavutil.mavlink, 'MAV_RESULT', message.result)}",
                    flush=True,
                )
        print(f"[disarm-result] armed={bool(master.motors_armed())}", flush=True)
    except Exception as exc:
        print(f"[disarm] ERROR while disarming: {exc}", file=sys.stderr, flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
