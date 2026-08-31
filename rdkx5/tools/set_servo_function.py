#!/usr/bin/env python3
"""Set SERVO5-8_FUNCTION=0 (None) to bypass broken ArduSub 4.1 vertical motor mixer."""
import time
from pymavlink import mavutil

conn = mavutil.mavlink_connection("/dev/ttyACM0", baud=115200)
conn.wait_heartbeat(timeout=5)
print(f"Heartbeat OK, sys={conn.target_system}")

def set_param(name, value):
    conn.mav.param_set_send(
        conn.target_system, conn.target_component,
        name.encode(), float(value), mavutil.mavlink.MAV_PARAM_TYPE_REAL32,
    )
    msg = conn.recv_match(type="PARAM_VALUE", blocking=True, timeout=3)
    if msg:
        print(f"  {name} = {msg.param_value}")
        return float(msg.param_value)
    print(f"  {name}: no ack!")
    return None

def read_param(name, timeout=3.0):
    conn.mav.param_request_read_send(conn.target_system, conn.target_component, name.encode(), -1)
    msg = conn.recv_match(type="PARAM_VALUE", blocking=True, timeout=timeout)
    if msg and msg.param_id.rstrip("\x00") == name:
        return float(msg.param_value)
    return None

# Verify current state
print("\n=== CURRENT SERVO5-8 FUNCTIONS ===")
for i in range(5, 9):
    v = read_param(f"SERVO{i}_FUNCTION")
    print(f"  SERVO{i}_FUNCTION = {v}")

# Set to 0 (None)
print("\n=== SETTING SERVO5-8_FUNCTION = 0 (None) ===")
for i in range(5, 9):
    set_param(f"SERVO{i}_FUNCTION", 0.0)
    time.sleep(0.2)

# Verify
print("\n=== VERIFIED ===")
for i in range(5, 9):
    v = read_param(f"SERVO{i}_FUNCTION")
    print(f"  SERVO{i}_FUNCTION = {v}")

# Also verify SERVO1-4 still have Motor functions
print("\n=== SERVO1-4 (should still be Motor1-4) ===")
for i in range(1, 5):
    v = read_param(f"SERVO{i}_FUNCTION")
    print(f"  SERVO{i}_FUNCTION = {v}")

print("\n=== DONE ===")
conn.close()
