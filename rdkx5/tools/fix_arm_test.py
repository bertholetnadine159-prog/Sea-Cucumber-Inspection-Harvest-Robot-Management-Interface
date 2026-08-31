import sys, time, os
from pymavlink import mavutil

ARM_DISARM = 400
REBOOT = 246

def connect():
    for attempt in range(10):
        try:
            m = mavutil.mavlink_connection("/dev/ttyACM0", baud=115200)
            m.wait_heartbeat(timeout=8.0)
            return m
        except Exception as ex:
            print("  retry " + str(attempt+1) + ": " + str(ex), flush=True)
            time.sleep(2)
    return None

master = connect()
if master is None:
    print("FAIL: cannot connect", flush=True)
    sys.exit(1)

s, c = master.target_system, master.target_component
print("connected", flush=True)

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

print("=== Set ARMING_CHECK=0 ===", flush=True)
print("  result=" + str(set_param("ARMING_CHECK", 0)), flush=True)

print("", flush=True)
print("=== Reboot Pixhawk ===", flush=True)
master.mav.command_long_send(s, c, REBOOT, 0, 1, 0, 0,0,0,0,0)
master.close()
print("  waiting 15s for reboot...", flush=True)
time.sleep(15)

master = connect()
if master is None:
    print("FAIL: cannot reconnect after reboot", flush=True)
    sys.exit(1)
s, c = master.target_system, master.target_component
print("  reconnected", flush=True)

print("", flush=True)
print("=== Try arm (cmd=400) ===", flush=True)
master.mav.command_long_send(s, c, ARM_DISARM, 0, 1, 0, 0,0,0,0,0)
drain(4.0)
armed = bool(master.motors_armed())
print("  armed = " + str(armed), flush=True)

if armed:
    print("", flush=True)
    print("=== ARMED! MANUAL_CONTROL neutral 5s ===", flush=True)
    print("  LISTEN: are ESCs beeping?", flush=True)
    t0 = time.monotonic()
    while time.monotonic() - t0 < 5.0:
        master.mav.manual_control_send(s, 0, 0, 500, 0, 0)
        msg = master.recv_match(blocking=True, timeout=0.1)
        if msg is not None:
            mt = msg.get_type()
            if mt == "SERVO_OUTPUT_RAW":
                pwm = [int(getattr(msg, "servo" + str(i) + "_raw", 0)) for i in range(1, 9)]
                print("  MAIN1-8 = " + str(pwm), flush=True)
            elif mt == "STATUSTEXT":
                print("  TXT: " + repr(msg.text.rstrip("\x00")), flush=True)
        time.sleep(0.04)

    print("", flush=True)
    print("=== Disarm ===", flush=True)
    master.mav.command_long_send(s, c, ARM_DISARM, 0, 0, 0, 0,0,0,0,0)
    drain(2.0)
    print("  armed = " + str(bool(master.motors_armed())), flush=True)
else:
    print("", flush=True)
    print("=== PreArm checks ===", flush=True)
    master.mav.command_long_send(s, c, 401, 0, 0, 0, 0,0,0,0,0)
    drain(5.0)

master.close()
print("", flush=True)
print("DONE", flush=True)