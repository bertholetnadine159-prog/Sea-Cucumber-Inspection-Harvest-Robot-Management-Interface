#!/usr/bin/env python3
"""Direct diagnostic: test what ArduSub does with different control inputs."""
import sys, time
from pymavlink import mavutil

conn = mavutil.mavlink_connection("/dev/ttyACM0", baud=115200)
conn.wait_heartbeat(timeout=5)
print(f"Heartbeat: sys={conn.target_system} comp={conn.target_component}")

def read_param(name, timeout=2.0):
    conn.mav.param_request_read_send(conn.target_system, conn.target_component, name.encode(), -1)
    msg = conn.recv_match(type="PARAM_VALUE", blocking=True, timeout=timeout)
    if msg and msg.param_id.rstrip("\x00") == name:
        return float(msg.param_value)
    return None

def read_motors(timeout=1.0):
    """Read latest SERVO_OUTPUT_RAW."""
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        msg = conn.recv_match(type="SERVO_OUTPUT_RAW", blocking=True, timeout=0.2)
        if msg:
            last = [int(getattr(msg, f"servo{i}_raw", 0)) for i in range(1, 17)]
    return last

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

def send_manual_control(x, y, z, r):
    conn.mav.manual_control_send(conn.target_system, x, y, z, r, 0)

def send_heartbeat():
    conn.mav.heartbeat_send(mavutil.mavlink.MAV_TYPE_GCS, mavutil.mavlink.MAV_AUTOPILOT_INVALID, 0, 0, 0)

def arm(force=True):
    conn.mav.command_long_send(
        conn.target_system, conn.target_component,
        mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM, 0,
        1, 21196 if force else 0, 0, 0, 0, 0, 0,
    )
    # Wait for COMMAND_ACK
    ack = conn.recv_match(type="COMMAND_ACK", blocking=True, timeout=3)
    if ack:
        print(f"  ARM ack: result={ack.result}")
    else:
        print("  ARM ack: TIMEOUT")

def disarm(force=True):
    conn.mav.command_long_send(
        conn.target_system, conn.target_component,
        mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM, 0,
        0, 21196 if force else 0, 0, 0, 0, 0, 0,
    )

# ---- Read params ----
print("\n=== PARAMETERS ===")
params = ["FRAME_CLASS", "FRAME_CONFIG", "RC3_TRIM", "RC3_MIN", "RC3_MAX",
          "MOT_SPIN_ARM", "MOT_SPIN_MIN", "MOT_PWM_TYPE", "ARMING_CHECK",
          "FS_PILOT_INPUT", "FS_GCS_ENABLE", "SIMPLE"]
for i in range(1, 9):
    params.append(f"SERVO{i}_FUNCTION")
    params.append(f"SERVO{i}_TRIM")
    params.append(f"SERVO{i}_MIN")
    params.append(f"SERVO{i}_MAX")

for p in params:
    v = read_param(p)
    status = "OK" if v is not None else "TIMEOUT"
    print(f"  {p} = {v} [{status}]")

# ---- Test 1: RC_OVERRIDE only (all 1500), no MANUAL_CONTROL ----
print("\n=== TEST 1: RC_OVERRIDE(1500x16) only, no MANUAL_CONTROL ===")
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
print(f"  Motors: {motors[:8] if motors else 'None'}")
if motors:
    for i, v in enumerate(motors[:8]):
        if v != 1500:
            print(f"  MAIN{i+1} = {v} (NOT 1500!)")

disarm(force=True)
time.sleep(1)

# ---- Test 2: MANUAL_CONTROL z=500 (current code behavior) ----
print("\n=== TEST 2: MANUAL_CONTROL(0,0,500,0) + RC_OVERRIDE(1500x16) ===")
send_heartbeat()
for _ in range(5):
    send_rc_override([1500] * 16)
    send_manual_control(0, 0, 500, 0)
    time.sleep(0.1)

arm(force=True)
time.sleep(0.5)
for _ in range(10):
    send_rc_override([1500] * 16)
    send_manual_control(0, 0, 500, 0)
    send_heartbeat()
    time.sleep(0.1)

motors = read_motors(1.0)
print(f"  Motors: {motors[:8] if motors else 'None'}")
if motors:
    for i, v in enumerate(motors[:8]):
        if v != 1500:
            print(f"  MAIN{i+1} = {v} (NOT 1500!)")

disarm(force=True)
time.sleep(1)

# ---- Test 3: MANUAL_CONTROL z=0 ----
print("\n=== TEST 3: MANUAL_CONTROL(0,0,0,0) + RC_OVERRIDE(1500x16) ===")
send_heartbeat()
for _ in range(5):
    send_rc_override([1500] * 16)
    send_manual_control(0, 0, 0, 0)
    time.sleep(0.1)

arm(force=True)
time.sleep(0.5)
for _ in range(10):
    send_rc_override([1500] * 16)
    send_manual_control(0, 0, 0, 0)
    send_heartbeat()
    time.sleep(0.1)

motors = read_motors(1.0)
print(f"  Motors: {motors[:8] if motors else 'None'}")
if motors:
    for i, v in enumerate(motors[:8]):
        if v != 1500:
            print(f"  MAIN{i+1} = {v} (NOT 1500!)")

disarm(force=True)
time.sleep(1)

# ---- Test 4: MANUAL_CONTROL only (no RC_OVERRIDE) ----
print("\n=== TEST 4: MANUAL_CONTROL(0,0,500,0) only, no RC_OVERRIDE ===")
send_heartbeat()
for _ in range(5):
    send_manual_control(0, 0, 500, 0)
    time.sleep(0.1)

arm(force=True)
time.sleep(0.5)
for _ in range(10):
    send_manual_control(0, 0, 500, 0)
    send_heartbeat()
    time.sleep(0.1)

motors = read_motors(1.0)
print(f"  Motors: {motors[:8] if motors else 'None'}")
if motors:
    for i, v in enumerate(motors[:8]):
        if v != 1500:
            print(f"  MAIN{i+1} = {v} (NOT 1500!)")

disarm(force=True)
time.sleep(1)

print("\n=== DONE ===")
conn.close()
