import sys, time
from pymavlink import mavutil

def connect():
    for attempt in range(10):
        try:
            m = mavutil.mavlink_connection("/dev/ttyACM0", baud=115200)
            m.wait_heartbeat(timeout=8.0)
            return m
        except Exception:
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

def read_param(name):
    master.mav.param_request_read_send(s, c, name.encode(), -1)
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

# Ensure params are correct
print("ARMING_CHECK=" + str(read_param("ARMING_CHECK")), flush=True)
print("RC3_TRIM=" + str(read_param("RC3_TRIM")), flush=True)
set_param("ARMING_CHECK", 0)
set_param("RC3_TRIM", 1500)

# Reboot
print("", flush=True)
print("=== Reboot Pixhawk ===", flush=True)
master.mav.command_long_send(s, c, 246, 0, 1, 0, 0,0,0,0,0)
master.close()
print("  waiting 15s...", flush=True)
time.sleep(15)

master = connect()
if master is None:
    print("FAIL: cannot reconnect", flush=True)
    sys.exit(1)
s, c = master.target_system, master.target_component
print("  reconnected", flush=True)

# Wait for boot
print("  waiting 5s for boot...", flush=True)
time.sleep(5)

# Arm
print("", flush=True)
print("=== Arm ===", flush=True)
master.mav.command_long_send(s, c, 400, 0, 1, 0, 0,0,0,0,0)
drain(5.0)
armed = bool(master.motors_armed())
print("  armed = " + str(armed), flush=True)

if armed:
    print("", flush=True)
    print("=== Sweep z values ===", flush=True)
    for z in [0, 250, 375, 475, 500, 525, 625, 750, 1000]:
        # Send a few times to ensure it takes effect
        for _ in range(3):
            master.mav.manual_control_send(s, 0, 0, z, 0, 0)
            time.sleep(0.05)
        time.sleep(0.2)
        pwm = read_servo()
        if pwm:
            print("  z=" + str(z) + " MAIN=" + str(pwm), flush=True)

    print("", flush=True)
    print("=== Disarm ===", flush=True)
    master.mav.command_long_send(s, c, 400, 0, 0, 0, 0,0,0,0,0)
    drain(2.0)
else:
    print("", flush=True)
    print("=== PreArm checks ===", flush=True)
    master.mav.command_long_send(s, c, 401, 0, 0, 0, 0,0,0,0,0)
    drain(5.0)

master.close()
print("", flush=True)
print("DONE", flush=True)