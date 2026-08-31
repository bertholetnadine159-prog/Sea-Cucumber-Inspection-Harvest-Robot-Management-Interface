import paramiko
c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("192.168.127.10", username="sunrise", password="sunrise", timeout=12, look_for_keys=False, allow_agent=False)

# Kill gateway to free the serial port
i, o, e = c.exec_command("pkill -f gateway.py 2>/dev/null; sleep 2; echo killed", timeout=10)
print(o.read().decode(errors="replace"))

# Run a script to fix params and test arm
diag = """
import sys, time
from pymavlink import mavutil
master = mavutil.mavlink_connection("/dev/ttyACM0", baud=115200)
master.wait_heartbeat(timeout=8.0)
s, c = master.target_system, master.target_component

def read_param(name, timeout=3.0):
    master.mav.param_request_read_send(s, c, name.encode(), -1)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        msg = master.recv_match(type="PARAM_VALUE", blocking=True, timeout=0.5)
        if msg is not None and msg.param_id.rstrip("\\x00") == name:
            return float(msg.param_value)
    return None

def set_param(name, value):
    master.mav.param_set_send(s, c, name.encode(), float(value), mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
    deadline = time.monotonic() + 3.0
    while time.monotonic() < deadline:
        msg = master.recv_match(type="PARAM_VALUE", blocking=True, timeout=0.5)
        if msg is not None and msg.param_id.rstrip("\\x00") == name:
            return float(msg.param_value)
    return None

def drain(seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        msg = master.recv_match(blocking=True, timeout=0.25)
        if msg is not None:
            mt = msg.get_type()
            if mt == "STATUSTEXT":
                print("  TXT: " + repr(msg.text.rstrip("\\x00")))
            elif mt == "COMMAND_ACK":
                print("  ACK cmd=" + str(msg.command) + " result=" + str(msg.result))
            elif mt == "HEARTBEAT":
                print("  HB armed=" + str(bool(msg.base_mode & mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED)))

print("=== Fix ARMING_CHECK 448 -> 0 ===")
result = set_param("ARMING_CHECK", 0)
print("  ARMING_CHECK = " + str(result))

print("")
print("=== Try arm ===")
master.mav.command_long_send(s, c, 183, 0, 1, 0, 0,0,0,0,0)
drain(3.0)
armed = bool(master.motors_armed())
print("  armed = " + str(armed))

if armed:
    print("")
    print("=== ARMED! Sending MANUAL_CONTROL neutral for 5s ===")
    print("  LISTEN TO ESCS: are they still beeping?")
    t0 = time.monotonic()
    while time.monotonic() - t0 < 5.0:
        master.mav.manual_control_send(s, 0, 0, 500, 0, 0)
        # Read any messages
        msg = master.recv_match(blocking=True, timeout=0.1)
        if msg is not None:
            mt = msg.get_type()
            if mt == "SERVO_OUTPUT_RAW":
                pwm = [int(getattr(msg, "servo" + str(i) + "_raw", 0)) for i in range(1, 9)]
                print("  SERVO_OUTPUT_RAW MAIN1-8 = " + str(pwm))
            elif mt == "STATUSTEXT":
                print("  TXT: " + repr(msg.text.rstrip("\\x00")))
        time.sleep(0.04)

    print("")
    print("=== Disarm ===")
    master.mav.command_long_send(s, c, 183, 0, 0, 0, 0,0,0,0,0)
    drain(2.0)
    print("  armed = " + str(bool(master.motors_armed())))
else:
    print("")
    print("=== ARM FAILED, collecting PreArm messages ===")
    master.mav.command_long_send(s, c, 401, 0, 0, 0, 0,0,0,0,0)
    drain(5.0)

master.close()
print("")
print("DONE")
"""

i, o, e = c.exec_command("cd /home/sunrise/seaUI_rdk && python3 -c \"" + diag + "\" 2>&1", timeout=30)
out = o.read().decode(errors="replace")
err = e.read().decode(errors="replace")
print(out)
if err:
    print("STDERR:", err[:500])
c.close()
