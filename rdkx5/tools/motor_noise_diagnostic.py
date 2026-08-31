#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# [RDK X5 side] motor noise root-cause diagnostic
from __future__ import annotations
import argparse, sys, time
from pathlib import Path

def resolve_connection(configured):
    if Path(configured).exists(): return configured
    by_id = Path("/dev/serial/by-id")
    if by_id.exists():
        for c in sorted(by_id.glob("usb-*")):
            if "pixhawk" in c.name.lower() or "ardupilot" in c.name.lower(): return str(c)
    acm = sorted(Path("/dev").glob("ttyACM*"))
    if acm: return str(acm[0])
    return configured

def read_param(master, s, c, name, timeout=2.0):
    master.mav.param_request_read_send(s, c, name.encode(), -1)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        msg = master.recv_match(type="PARAM_VALUE", blocking=True, timeout=0.25)
        if msg is not None and msg.param_id.rstrip("\x00") == name: return float(msg.param_value)
    return None

def collect(master, seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        msg = master.recv_match(blocking=True, timeout=0.25)
        if msg is not None: yield msg

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--connection", default="/dev/ttyACM0")
    parser.add_argument("--baud", type=int, default=115200)
    args = parser.parse_args()
    try:
        from pymavlink import mavutil
    except ImportError:
        print("ERROR: pip3 install pymavlink"); return 1
    conn = resolve_connection(args.connection)
    print("[1/8] Connecting " + conn)
    master = mavutil.mavlink_connection(conn, baud=args.baud)
    try: master.wait_heartbeat(timeout=8.0)
    except Exception: print("FAIL: No heartbeat"); return 1
    s, c = master.target_system, master.target_component
    print("      OK sys=" + str(s) + " comp=" + str(c))
    print("\n[2/8] Reading critical parameters...")
    checks = [
        ("MOT_PWM_TYPE", 0, "ESC protocol 0=PWM"),
        ("BRD_PWM_COUNT", 4, "IO MAIN OUT count 0=no output"),
        ("BRD_SAFETYENABLE", 0, "Safety switch 1=blocked"),
        ("FRAME_CLASS", 2, "2=ROV"),
        ("DISARM_DELAY", 0, "Auto-disarm timer"),
        ("FS_PILOT_INPUT", 0, "Pilot failsafe kills outputs without RC"),
        ("FS_THR_ENABLE", 0, "Throttle failsafe"),
        ("FS_GCS_ENABL", 0, "GCS failsafe"),
        ("RC3_TRIM", 1500, "Must be 1500 bidirectional"),
    ]
    for i in range(1, 9):
        checks.append(("SERVO" + str(i) + "_FUNCTION", 32 + i, "Motor" + str(i)))
    issues = []
    for name, exp, desc in checks:
        val = read_param(master, s, c, name)
        st = "OK" if val == exp else "MISMATCH"
        if val is None: st = "TIMEOUT"
        elif val != exp: issues.append("  " + name + "=" + str(val) + " want " + str(exp) + " " + desc)
        print("      " + name + "=" + str(val) + " want=" + str(exp) + " [" + st + "]")
    print("\n[3/8] SYS_STATUS health...")
    sys_msg = None
    for msg in collect(master, 2.0):
        if msg.get_type() == "SYS_STATUS": sys_msg = msg; break
    if sys_msg:
        h = sys_msg.onboard_control_sensors_health
        for nm, bit in [("RC", 4), ("Output", 7), ("IO", 10)]:
            ok = bool(h & (1 << bit))
            if not ok: issues.append("  SYS_STATUS " + nm + "=FAIL")
            print("      " + nm + ": " + ("OK" if ok else "FAIL"))
    print("\n[4/8] Flight mode...")
    fm = getattr(master, "flightmode", "") or "?"
    armed = bool(master.motors_armed())
    print("      mode=" + fm + " armed=" + str(armed))
    if fm.upper() not in ("MANUAL", "STABILIZE", "ACRO"): issues.append("  mode=" + fm + " not MANUAL")
    print("\n[5/8] Arm + MANUAL_CONTROL + RC keepalive 3s...")
    if not armed:
        master.mav.command_long_send(s, c, 183, 0, 1, 0, 0, 0, 0, 0, 0)
        time.sleep(1.0)
        armed = bool(master.motors_armed())
        print("      armed=" + str(armed))
    else:
        print("      already armed")
    for _ in collect(master, 1.0): pass
    servo = None
    texts = []
    t0 = time.monotonic()
    while time.monotonic() - t0 < 3.0:
        master.mav.rc_channels_override_send(s, c, 1500, 1500, 1500, 1500, 1500, 1500, 1500, 1500, 1500, 1500, 1500, 1500, 1500, 1500, 1500)
        master.mav.manual_control_send(s, 0, 0, 500, 0, 0)
        for msg in collect(master, 0.1):
            mt = msg.get_type()
            if mt == "SERVO_OUTPUT_RAW" and servo is None:
                servo = [int(getattr(msg, "servo" + str(i) + "_raw", 0)) for i in range(1, 9)]
            elif mt == "STATUSTEXT":
                texts.append(msg.text.rstrip("\x00"))
        time.sleep(0.04)
    if servo:
        print("      SERVO_OUTPUT_RAW=" + str(servo))
        if not all(v == 1500 for v in servo): issues.append("  SERVO_OUTPUT_RAW not 1500")
    else:
        print("      No SERVO_OUTPUT_RAW")
    print("\n[6/8] DO_SET_SERVO MAIN1 vs AUX1...")
    master.mav.command_long_send(s, c, 176, 0, 1, 1500, 0, 0, 0, 0, 0)
    ack1 = None
    for msg in collect(master, 2.0):
        if msg.get_type() == "COMMAND_ACK" and msg.command == 176: ack1 = msg.result; break
    print("      MAIN1 result=" + str(ack1))
    master.mav.command_long_send(s, c, 176, 0, 9, 1500, 0, 0, 0, 0, 0)
    ack9 = None
    for msg in collect(master, 2.0):
        if msg.get_type() == "COMMAND_ACK" and msg.command == 176: ack9 = msg.result; break
    print("      AUX1  result=" + str(ack9))
    print("\n[7/8] STATUSTEXT 5s...")
    for t in texts: print("      " + repr(t))
    for msg in collect(master, 5.0):
        if msg.get_type() == "STATUSTEXT":
            t = msg.text.rstrip("\x00")
            print("      " + repr(t))
            if any(w in t.lower() for w in ["prearm", "fail", "denied"]): issues.append("  " + repr(t))
    print("\n[8/8] Disarm...")
    master.mav.command_long_send(s, c, 183, 0, 0, 0, 0, 0, 0, 0, 0)
    time.sleep(0.5)
    print("      armed=" + str(bool(master.motors_armed())))
    print("\n" + "=" * 60)
    print("DIAGNOSIS")
    print("=" * 60)
    if not issues:
        print("\nAll software checks PASS.")
        print("If ESCs STILL beep, problem is HARDWARE:")
        print("  1. ESC wire in RC INPUT row not MAIN OUT")
        print("  2. ESC ground not common with Pixhawk")
        print("  3. MAIN OUT rail no 5V power needs BEC")
        print("  4. Safety switch faulty press it")
        print("  5. ESC one-way type 1000 stop not 1500")
        print("  6. IO coprocessor dead reflash firmware")
    else:
        print("\nISSUES:")
        for i in issues: print(i)
        print("\nFIXES:")
        if any("FS_PILOT_INPUT" in i for i in issues): print("  pixhawk_arm_probe.py --param-set FS_PILOT_INPUT 0")
        if any("FS_THR_ENABLE" in i for i in issues): print("  pixhawk_arm_probe.py --param-set FS_THR_ENABLE 0")
        if any("RC3_TRIM" in i for i in issues): print("  pixhawk_arm_probe.py --param-set RC3_TRIM 1500")
        if any("DISARM_DELAY" in i for i in issues): print("  pixhawk_arm_probe.py --param-set DISARM_DELAY 0")
        if any("BRD_PWM_COUNT" in i for i in issues): print("  pixhawk_arm_probe.py --param-set BRD_PWM_COUNT 4")
        print("  Then reboot Pixhawk and re-run this script.")
    print("\n" + "=" * 60)
    master.close()
    return 0 if not issues else 1

if __name__ == "__main__":
    sys.exit(main())