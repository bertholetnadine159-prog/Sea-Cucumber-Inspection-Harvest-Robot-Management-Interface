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
        if msg is not None and msg.param_id.rstrip("\x00") == name:
            return float(msg.param_value)
    return None

print("=== SERVO params for MAIN1-8 ===", flush=True)
for i in range(1, 9):
    fn = read_param("SERVO" + str(i) + "_FUNCTION")
    tr = read_param("SERVO" + str(i) + "_TRIM")
    mn = read_param("SERVO" + str(i) + "_MIN")
    mx = read_param("SERVO" + str(i) + "_MAX")
    rv = read_param("SERVO" + str(i) + "_REVERSED")
    print("  SERVO" + str(i) + ": FUNC=" + str(fn) + " TRIM=" + str(tr) + " MIN=" + str(mn) + " MAX=" + str(mx) + " REV=" + str(rv), flush=True)

print("", flush=True)
print("=== Frame and motor params ===", flush=True)
for name in ["FRAME_CONFIG", "FRAME_CLASS", "MOT_PWM_TYPE", "MOT_PWM_MIN", "MOT_PWM_MAX",
             "MOT_THST_HOVER", "MOT_SPIN_ARM", "MOT_SPOOL_TIME",
             "PILOT_THR_BK", "PILOT_THR_FWD", "PILOT_SPEED_UP", "PILOT_SPEED_DN",
             " THR_DZ", "THR_DZ"]:
    val = read_param(name)
    if val is not None:
        print("  " + name + " = " + str(val), flush=True)

master.close()
print("", flush=True)
print("DONE", flush=True)