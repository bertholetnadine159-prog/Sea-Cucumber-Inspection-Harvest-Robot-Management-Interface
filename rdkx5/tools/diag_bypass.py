#!/usr/bin/env python3
"""Test: bypass motor mixer by changing SERVO5-8_FUNCTION."""
import sys, time
from pymavlink import mavutil

conn = mavutil.mavlink_connection("/dev/ttyACM0", baud=115200)
conn.wait_heartbeat(timeout=5)
print(f"Heartbeat OK")

def read_param(name, timeout=3.0):
    conn.mav.param_request_read_send(conn.target_system, conn.target_component, name.encode(), -1)
    msg = conn.recv_match(type="PARAM_VALUE", blocking=True, timeout=timeout)
    if msg and msg.param_id.rstrip("\x00") == name:
        return float(msg.param_value)
    return None

def set_param(name, value):
    conn.mav.param_set_send(
        conn.target_system, conn.target_component,
        name.encode(), float(value), mavutil.mavlink.MAV_PARAM_TYPE_REAL32,
    )
    msg = conn.recv_match(type="PARAM_VALUE", blocking=True, timeout=3)
    if msg:
        print(f"  Set {name} = {msg.param_value}")
        return float(msg.param_value)
    return None

def read_motors(timeout=1.0):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        msg = conn.recv_match(type="SERVO_OUTPUT_RAW", blocking=True, timeout=0.2)
        if msg:
            last = [int(getattr(msg, f"servo{i}_raw", 0)) for i in range(1, 17)]
    return last

def read_statustext(duration=2.0):
    texts = []
    deadline = time.time() + duration
    while time.time() < deadline:
        msg = conn.recv_match(type="STATUSTEXT", blocking=True, timeout=0.2)
        if msg:
            texts.append(f"  [{msg.severity}] {msg.text}")
    return texts

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
    if ack:
        print(f"  ARM ack: result={ack.result}")

def disarm(force=True):
    conn.mav.command_long_send(
        conn.target_system, conn.target_component,
        mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM, 0,
        0, 21196 if force else 0, 0, 0, 0, 0, 0,
    )

def set_servo(channel, pwm):
    conn.mav.command_long_send(
        conn.target_system, conn.target_component,
        mavutil.mavlink.MAV_CMD_DO_SET_SERVO, 0,
        channel, pwm, 0, 0, 0, 0, 0,
    )
    ack = conn.recv_match(type="COMMAND_ACK", blocking=True, timeout=2)
    return ack.result if ack else None

# ---- Save original functions ----
print("\n=== SAVING ORIGINAL SERVO FUNCTIONS ===")
orig_funcs = {}
for i in range(5, 9):
    v = read_param(f"SERVO{i}_FUNCTION")
    orig_funcs[i] = v
    print(f"  SERVO{i}_FUNCTION = {v}")

# ---- Test 1: Try different RC3 values while armed ----
print("\n=== TEST: Throttle sweep (RC3=1100,1300,1500,1700,1900) ===")
send_heartbeat()
for _ in range(5):
    send_rc_override([1500] * 16)
    time.sleep(0.1)
arm(force=True)
time.sleep(0.5)

for rc3_val in [1100, 1300, 1500, 1700, 1900]:
    chans = [1500] * 16
    chans[2] = rc3_val  # RC3
    for _ in range(5):
        send_rc_override(chans)
        send_heartbeat()
        time.sleep(0.1)
    motors = read_motors(0.5)
    if motors:
        print(f"  RC3={rc3_val}: MAIN1-8 = {motors[:8]}")

disarm(force=True)
time.sleep(1)

# ---- Test 2: Change SERVO5-8_FUNCTION to 1 (RCPassThrough) ----
print("\n=== TEST: SERVO5-8_FUNCTION = 1 (RCPassThrough) ===")
for i in range(5, 9):
    set_param(f"SERVO{i}_FUNCTION", 1.0)  # RCPassThrough
time.sleep(1)

send_heartbeat()
for _ in range(5):
    send_rc_override([1500] * 16)
    time.sleep(0.1)
arm(force=True)
time.sleep(0.5)

# With RCPassThrough, MAIN5 should follow RC5, MAIN6 follows RC6, etc.
# Send RC5-8 = 1500
for _ in range(10):
    send_rc_override([1500] * 16)
    send_heartbeat()
    time.sleep(0.1)
motors = read_motors(1.0)
print(f"  Motors (RCPassThrough, RC5-8=1500): {motors[:8] if motors else 'None'}")

# Try DO_SET_SERVO on MAIN5 with function=1
print("\n  Trying DO_SET_SERVO on MAIN5 (function=1)...")
result = set_servo(5, 1500)
print(f"  DO_SET_SERVO MAIN5 result={result}")
motors = read_motors(0.5)
print(f"  Motors after DO_SET_SERVO: {motors[:8] if motors else 'None'}")

# Read statustext
texts = read_statustext(1.0)
for t in texts:
    print(t)

disarm(force=True)
time.sleep(1)

# ---- Test 3: Change SERVO5-8_FUNCTION to 0 (None) ----
print("\n=== TEST: SERVO5-8_FUNCTION = 0 (None) ===")
for i in range(5, 9):
    set_param(f"SERVO{i}_FUNCTION", 0.0)
time.sleep(1)

send_heartbeat()
for _ in range(5):
    send_rc_override([1500] * 16)
    time.sleep(0.1)
arm(force=True)
time.sleep(0.5)

for _ in range(10):
    send_rc_override([1500] * 16)
    send_heartbeat()
    time.sleep(0.1)
motors = read_motors(1.0)
print(f"  Motors (Function=None): {motors[:8] if motors else 'None'}")

# Try DO_SET_SERVO
result = set_servo(5, 1500)
print(f"  DO_SET_SERVO MAIN5 result={result}")
motors = read_motors(0.5)
print(f"  Motors after DO_SET_SERVO: {motors[:8] if motors else 'None'}")

texts = read_statustext(1.0)
for t in texts:
    print(t)

disarm(force=True)
time.sleep(1)

# ---- Restore original functions ----
print("\n=== RESTORING ORIGINAL FUNCTIONS ===")
for i in range(5, 9):
    if orig_funcs[i] is not None:
        set_param(f"SERVO{i}_FUNCTION", orig_funcs[i])

print("\n=== DONE ===")
conn.close()
