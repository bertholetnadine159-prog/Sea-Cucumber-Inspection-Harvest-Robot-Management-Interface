#!/usr/bin/env python3
"""Deep diagnostic v2."""
import sys, time
from pymavlink import mavutil

conn = mavutil.mavlink_connection("/dev/ttyACM0", baud=115200)
hb = conn.wait_heartbeat(timeout=5)
print(f"Heartbeat: sys={conn.target_system} comp={conn.target_component}")
print(f"  type={hb.type} (8=Submarine) autopilot={hb.autopilot} (3=ArduPilot)")

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

def read_motors(timeout=1.0):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        msg = conn.recv_match(type="SERVO_OUTPUT_RAW", blocking=True, timeout=0.2)
        if msg:
            last = [int(getattr(msg, f"servo{i}_raw", 0)) for i in range(1, 17)]
    return last

def read_rc_channels(timeout=1.0):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        msg = conn.recv_match(type="RC_CHANNELS", blocking=True, timeout=0.2)
        if msg:
            chans = []
            for i in range(1, 17):
                v = getattr(msg, f"chan{i}_raw", 0)
                chans.append(int(v) if v else 0)
            last = chans
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

# ---- Firmware version ----
print("\n=== FIRMWARE VERSION ===")
conn.mav.autopilot_version_request_send(conn.target_system, conn.target_component)
msg = conn.recv_match(type="AUTOPILOT_VERSION", blocking=True, timeout=5)
if msg:
    flight_sw = msg.flight_sw_version
    fw_str = f"{(flight_sw >> 24) & 0xFF}.{(flight_sw >> 16) & 0xFF}.{(flight_sw >> 8) & 0xFF}"
    print(f"  flight_sw_version={flight_sw} -> {fw_str}")
    print(f"  board_version={msg.board_version}")
    print(f"  capabilities={msg.capabilities:#x}")
else:
    print("  TIMEOUT")

try:
    mode_map = conn.mode_mapping()
    print(f"  modes: {sorted(mode_map.keys())}")
except Exception as e:
    print(f"  mode_mapping error: {e}")

# ---- Read params ----
print("\n=== PARAMETERS ===")
extra_params = [
    "FRAME_CLASS", "FRAME_CONFIG", "FRAME_TYPE",
    "MOT_SPIN_ARM", "MOT_SPIN_MIN", "MOT_SPIN_MAX",
    "THR_DEFAULT", "FS_THR_VALUE", "FS_THR_ENABLE",
    "PILOT_THR_BHVR", "RC3_OPTION", "RC3_REV",
    "FS_GCS_ENABLE", "FS_PILOT_INPUT",
    "DISARM_DELAY", "ARMING_CHECK",
    "RC_FS_TIMEOUT", "FS_EF_ENABLE",
    "MOT_SPOOL_TIME", "THR_DAMP",
    "PILOT_THR_LAND_MIN", "PILOT_THR_CLIMB_MAX",
]
for p in extra_params:
    v = read_param(p)
    if v is not None:
        print(f"  {p} = {v}")

# ---- Actual RC channels while sending override ----
print("\n=== ACTUAL RC CHANNELS (while sending RC_OVERRIDE 1500x16) ===")
send_heartbeat()
for _ in range(10):
    send_rc_override([1500] * 16)
    time.sleep(0.05)
rc = read_rc_channels(1.0)
if rc:
    print(f"  RC channels: {rc[:8]}")
    print(f"  RC3 (throttle) = {rc[2]}")
else:
    print("  No RC_CHANNELS message received")

# ---- Test MOT_SPIN_ARM=0 ----
print("\n=== TEST: MOT_SPIN_ARM=0 ===")
set_param("MOT_SPIN_ARM", 0.0)
time.sleep(0.5)
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
rc = read_rc_channels(0.5)
if rc:
    print(f"  RC3 (armed) = {rc[2]}")
disarm(force=True)
time.sleep(1)

# ---- Restore ----
set_param("MOT_SPIN_ARM", 0.1)

# ---- Try DO_SET_SERVO on MAIN5 ----
print("\n=== TEST: DO_SET_SERVO on MAIN5 while armed ===")
send_heartbeat()
for _ in range(5):
    send_rc_override([1500] * 16)
    time.sleep(0.1)
arm(force=True)
time.sleep(0.5)
conn.mav.command_long_send(
    conn.target_system, conn.target_component,
    mavutil.mavlink.MAV_CMD_DO_SET_SERVO, 0,
    5, 1500, 0, 0, 0, 0, 0,
)
ack = conn.recv_match(type="COMMAND_ACK", blocking=True, timeout=3)
if ack:
    print(f"  DO_SET_SERVO MAIN5 ack: result={ack.result}")
for _ in range(5):
    send_rc_override([1500] * 16)
    send_heartbeat()
    time.sleep(0.1)
motors = read_motors(1.0)
print(f"  Motors: {motors[:8] if motors else 'None'}")
disarm(force=True)
time.sleep(1)

print("\n=== DONE ===")
conn.close()
