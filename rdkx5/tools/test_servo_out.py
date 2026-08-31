#!/usr/bin/env python3
"""Test: Does DO_SET_SERVO actually change MAIN5-8 output? Also test RCPassThrough."""
import time
from pymavlink import mavutil

conn = mavutil.mavlink_connection("/dev/ttyACM0", baud=115200)
conn.wait_heartbeat(timeout=5)
print("Heartbeat OK")

def read_motors(timeout=1.0):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        msg = conn.recv_match(type="SERVO_OUTPUT_RAW", blocking=True, timeout=0.2)
        if msg:
            last = [int(getattr(msg, f"servo{i}_raw", 0)) for i in range(1, 17)]
    return last

def set_servo(channel, pwm):
    conn.mav.command_long_send(
        conn.target_system, conn.target_component,
        mavutil.mavlink.MAV_CMD_DO_SET_SERVO, 0,
        channel, pwm, 0, 0, 0, 0, 0,
    )
    ack = conn.recv_match(type="COMMAND_ACK", blocking=True, timeout=2)
    return ack.result if ack else None

def send_rc_override(channels):
    ch = list(channels) + [65535] * max(0, 16 - len(channels))
    try:
        conn.mav.rc_channels_override_send(
            conn.target_system, conn.target_component,
            ch[0], ch[1], ch[2], ch[3], ch[4], ch[5], ch[6], ch[7],
            ch[8], ch[9], ch[10], ch[11], ch[12], ch[13], ch[14], ch[15],
        )
    except TypeError:
        conn.mav.rc_channels_override_send(
            conn.target_system, conn.target_component,
            ch[0], ch[1], ch[2], ch[3], ch[4], ch[5], ch[6], ch[7],
        )

def send_heartbeat():
    conn.mav.heartbeat_send(mavutil.mavlink.MAV_TYPE_GCS, mavutil.mavlink.MAV_AUTOPILOT_INVALID, 0, 0, 0)

def arm(force=True):
    conn.mav.command_long_send(
        conn.target_system, conn.target_component,
        mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM, 0,
        1, 21196 if force else 0, 0, 0, 0, 0, 0,
    )
    ack = conn.recv_match(type="COMMAND_ACK", blocking=True, timeout=3)
    print(f"  ARM result={ack.result if ack else None}")

def disarm(force=True):
    conn.mav.command_long_send(
        conn.target_system, conn.target_component,
        mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM, 0,
        0, 21196 if force else 0, 0, 0, 0, 0, 0,
    )

def set_param(name, value):
    conn.mav.param_set_send(
        conn.target_system, conn.target_component,
        name.encode(), float(value), mavutil.mavlink.MAV_PARAM_TYPE_REAL32,
    )
    msg = conn.recv_match(type="PARAM_VALUE", blocking=True, timeout=3)
    if msg:
        print(f"  {name} = {msg.param_value}")

# ---- Test 1: DO_SET_SERVO with FUNCTION=0 ----
print("\n=== TEST 1: DO_SET_SERVO with FUNCTION=0 ===")
send_heartbeat()
for _ in range(5):
    send_rc_override([1500] * 16)
    time.sleep(0.1)
arm(force=True)
time.sleep(0.5)

motors = read_motors(0.5)
print(f"  Baseline: {motors[:8] if motors else None}")

for pwm_val in [1700, 1100, 1900, 1500]:
    result = set_servo(5, pwm_val)
    for _ in range(5):
        send_rc_override([1500] * 16)
        send_heartbeat()
        time.sleep(0.1)
    motors = read_motors(0.5)
    print(f"  SET(5,{pwm_val}) ack={result} motors={motors[:8] if motors else None}")

# All 4 channels
for ch in [5, 6, 7, 8]:
    set_servo(ch, 1700)
    time.sleep(0.05)
for _ in range(5):
    send_rc_override([1500] * 16)
    send_heartbeat()
    time.sleep(0.1)
motors = read_motors(0.5)
print(f"  SET(5-8,1700) motors={motors[:8] if motors else None}")

for ch in [5, 6, 7, 8]:
    set_servo(ch, 1500)
    time.sleep(0.05)
for _ in range(3):
    send_rc_override([1500] * 16)
    send_heartbeat()
    time.sleep(0.1)

disarm(force=True)
time.sleep(1)

# ---- Test 2: RCPassThrough with RC_OVERRIDE ----
print("\n=== TEST 2: RCPassThrough with RC_OVERRIDE ===")
for i in range(5, 9):
    set_param(f"SERVO{i}_FUNCTION", 1.0)
time.sleep(1)

send_heartbeat()
for _ in range(5):
    send_rc_override([1500] * 16)
    time.sleep(0.1)
arm(force=True)
time.sleep(0.5)

motors = read_motors(0.5)
print(f"  Baseline: {motors[:8] if motors else None}")

for rc_val in [1700, 1100, 1900, 1500]:
    chans = [1500] * 16
    for i in range(4, 8):
        chans[i] = rc_val
    for _ in range(10):
        send_rc_override(chans)
        send_heartbeat()
        time.sleep(0.1)
    motors = read_motors(0.5)
    print(f"  RC5-8={rc_val} motors={motors[:8] if motors else None}")

disarm(force=True)
time.sleep(1)

# ---- Restore to FUNCTION=0 ----
print("\n=== Restoring FUNCTION=0 ===")
for i in range(5, 9):
    set_param(f"SERVO{i}_FUNCTION", 0.0)

print("\n=== DONE ===")
conn.close()
