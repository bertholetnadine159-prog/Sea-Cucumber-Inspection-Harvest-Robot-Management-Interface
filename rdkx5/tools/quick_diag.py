import sys, time
from pymavlink import mavutil

master = mavutil.mavlink_connection("/dev/ttyACM0", baud=115200)
master.wait_heartbeat(timeout=8.0)
s, c = master.target_system, master.target_component
print("connected sys=" + str(s) + " comp=" + str(c))

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

def set_pwm(channel, pwm):
    master.mav.command_long_send(s, c, 176, 0, float(channel), float(pwm), 0,0,0,0,0)

def drain(seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        msg = master.recv_match(blocking=True, timeout=0.25)
        if msg is not None:
            mt = msg.get_type()
            if mt == "STATUSTEXT":
                print("  STATUSTEXT: " + repr(msg.text.rstrip("\x00")))
            elif mt == "COMMAND_ACK":
                print("  ACK cmd=" + str(msg.command) + " result=" + str(msg.result))

print("\n=== STEP 1: Current params ===")
for name in ["RC3_TRIM", "RC3_MIN", "RC3_MAX", "MOT_PWM_TYPE", "BRD_PWM_COUNT",
             "FRAME_CLASS", "FRAME_CONFIG", "DISARM_DELAY", "FS_PILOT_INPUT",
             "FS_THR_ENABLE", "FS_GCS_ENABL", "ARMING_CHECK", "BATT_MONITOR"]:
    val = read_param(name)
    print("  " + name + " = " + str(val))

print("\n=== STEP 2: Fix RC3_TRIM to 1500 ===")
result = set_param("RC3_TRIM", 1500)
print("  RC3_TRIM = " + str(result))

print("\n=== STEP 3: SYS_STATUS ===")
for i in range(20):
    msg = master.recv_match(blocking=True, timeout=0.5)
    if msg is not None and msg.get_type() == "SYS_STATUS":
        h = msg.onboard_control_sensors_health
        print("  health = 0x" + format(h, "08x"))
        print("  bit15 motor_outputs = " + str(bool(h & (1<<15))))
        print("  bit16 rc_receiver = " + str(bool(h & (1<<16))))
        break

print("\n=== STEP 4: Try arm ===")
master.mav.command_long_send(s, c, 183, 0, 1, 0, 0,0,0,0,0)
drain(3.0)
armed = bool(master.motors_armed())
print("  armed = " + str(armed))

if armed:
    print("\n=== STEP 5: Send 1500 to MAIN1-8 ===")
    for ch in range(1, 9):
        set_pwm(ch, 1500)
    drain(3.0)
    print("  LISTEN: are ESCs still beeping with 1500?")

    print("\n=== STEP 6: Send 1000 to MAIN1-8 ===")
    for ch in range(1, 9):
        set_pwm(ch, 1000)
    drain(3.0)
    print("  LISTEN: are ESCs still beeping with 1000?")

    print("\n=== STEP 7: SERVO_OUTPUT_RAW ===")
    for i in range(20):
        msg = master.recv_match(blocking=True, timeout=0.5)
        if msg is not None and msg.get_type() == "SERVO_OUTPUT_RAW":
            pwm = [int(getattr(msg, "servo" + str(i) + "_raw", 0)) for i in range(1, 9)]
            print("  MAIN1-8 = " + str(pwm))
            break

    print("\n=== Disarm ===")
    master.mav.command_long_send(s, c, 183, 0, 0, 0, 0,0,0,0,0)
    drain(2.0)
    print("  armed = " + str(bool(master.motors_armed())))

master.close()
print("\nDONE")