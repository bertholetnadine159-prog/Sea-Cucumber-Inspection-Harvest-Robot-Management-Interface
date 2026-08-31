import sys, time
from pymavlink import mavutil

master = mavutil.mavlink_connection("/dev/ttyACM0", baud=115200)
master.wait_heartbeat(timeout=8.0)
s, c = master.target_system, master.target_component
print("connected", flush=True)

def read_param(name, timeout=3.0):
    master.mav.param_request_read_send(s, c, name.encode(), -1)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        msg = master.recv_match(type="PARAM_VALUE", blocking=True, timeout=0.5)
        if msg is not None and msg.param_id.rstrip("\x00") == name:
            return float(msg.param_value)
    return None

def set_param(name, value):
    master.mav.param_set_send(s, c, name.encode(), float(value), mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
    deadline = time.monotonic() + 3.0
    while time.monotonic() < deadline:
        msg = master.recv_match(type="PARAM_VALUE", blocking=True, timeout=0.5)
        if msg is not None and msg.param_id.rstrip("\x00") == name:
            return float(msg.param_value)
    return None

def drain(seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        msg = master.recv_match(blocking=True, timeout=0.25)
        if msg is not None:
            mt = msg.get_type()
            if mt == "STATUSTEXT":
                print("  TXT: " + repr(msg.text.rstrip("\x00")), flush=True)
            elif mt == "COMMAND_ACK":
                print("  ACK cmd=" + str(msg.command) + " result=" + str(msg.result), flush=True)

def read_servo():
    for _ in range(30):
        msg = master.recv_match(blocking=True, timeout=0.3)
        if msg is not None and msg.get_type() == "SERVO_OUTPUT_RAW":
            return [int(getattr(msg, "servo" + str(i) + "_raw", 0)) for i in range(1, 9)]
    return None

# Check current RC3_TRIM
rc3 = read_param("RC3_TRIM")
print("RC3_TRIM = " + str(rc3), flush=True)

# Fix RC3_TRIM
if rc3 != 1500:
    print("Fixing RC3_TRIM -> 1500", flush=True)
    set_param("RC3_TRIM", 1500)
    print("  RC3_TRIM = " + str(read_param("RC3_TRIM")), flush=True)

# Also check RC3_MIN/MAX
print("RC3_MIN = " + str(read_param("RC3_MIN")), flush=True)
print("RC3_MAX = " + str(read_param("RC3_MAX")), flush=True)

# Arm
print("", flush=True)
print("=== Arm ===", flush=True)
master.mav.command_long_send(s, c, 400, 0, 1, 0, 0,0,0,0,0)
drain(3.0)
print("  armed = " + str(bool(master.motors_armed())), flush=True)

# Sweep z values to find neutral
print("", flush=True)
print("=== Sweep MANUAL_CONTROL z to find neutral for MAIN5-8 ===", flush=True)
for z in [0, 250, 375, 475, 500, 525, 625, 750, 1000]:
    master.mav.manual_control_send(s, 0, 0, z, 0, 0)
    time.sleep(0.3)
    pwm = read_servo()
    if pwm:
        print("  z=" + str(z) + " -> MAIN1-4=" + str(pwm[:4]) + " MAIN5-8=" + str(pwm[4:]), flush=True)
    else:
        print("  z=" + str(z) + " -> no SERVO_OUTPUT_RAW", flush=True)

# Disarm
print("", flush=True)
print("=== Disarm ===", flush=True)
master.mav.command_long_send(s, c, 400, 0, 0, 0, 0,0,0,0,0)
drain(2.0)
print("  armed = " + str(bool(master.motors_armed())), flush=True)

master.close()
print("", flush=True)
print("DONE", flush=True)