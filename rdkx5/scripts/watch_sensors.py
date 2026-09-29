#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""RDK X5 传感器实时看板（接线调试用）——0.1 秒快查版。

板上运行：
  python3 /opt/seaui/watch_sensors.py --log     # 每 0.1s 一行，tail -f /tmp/watch_live.log 看
  python3 /opt/seaui/watch_sensors.py           # 全屏 ANSI 模式（本地终端）
  python3 /opt/seaui/watch_sensors.py --once    # 单次快照退出

设计：
  - 超声波两路各开后台线程持续收 FF 帧（每 ~2.2s 更新一次读数），不阻塞主循环；
  - I2C 探测用 /dev/i2c-N 原始 ioctl（纯 stdlib，毫秒级，不需要 smbus2）；
  - DS18B20/Pixhawk 走 sysfs/节点存在性；
  - 任何设备上线/掉线写入事件流（/tmp/sensor_events.log）——找正负极时盯这里。
"""
import fcntl
import glob
import os
import signal
import sys
import threading
import time

try:
    import serial
except ImportError:
    serial = None

CLEAR = "\033[2J\033[H"
GREEN, YELLOW, DIM, BOLD, END = "\033[32m", "\033[33m", "\033[2m", "\033[1m", "\033[0m"
EVENT_LOG = "/tmp/sensor_events.log"
I2C_SLAVE = 0x0703

events = []  # (时间, 文本)
events_lock = threading.Lock()


def log_event(text):
    stamp = time.strftime("%H:%M:%S")
    with events_lock:
        events.append((stamp, text))
        del events[:-60]
    try:
        with open(EVENT_LOG, "a", encoding="utf-8") as fh:
            fh.write("%s %s\n" % (stamp, text))
    except OSError:
        pass


class _ProbeTimeout(Exception):
    pass


def _on_alarm(signum, frame):
    raise _ProbeTimeout()


signal.signal(signal.SIGALRM, _on_alarm)


def i2c_probe(bus, addr, timeout=0.2):
    """原始 I2C 单字节读探测；总线卡死时用 SIGALRM 硬超时兜底（绝不无限阻塞）。"""
    path = "/dev/i2c-%d" % bus
    try:
        fd = os.open(path, os.O_RDWR)
    except OSError:
        return False
    try:
        fcntl.ioctl(fd, I2C_SLAVE, addr)
        signal.setitimer(signal.ITIMER_REAL, timeout)
        try:
            os.read(fd, 1)
            return True
        except _ProbeTimeout:
            return False
        except OSError:
            return False
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        os.close(fd)


def uart_worker(port, state, key):
    """后台线程：持续开串口收 FF 帧，刷新共享状态。"""
    if serial is None:
        return
    while not state.get("stop"):
        if not os.path.exists(port):
            state[key] = {"mm": None, "bytes": 0, "err": "节点缺失"}
            time.sleep(1.0)
            continue
        try:
            ser = serial.Serial(port=port, baudrate=9600, timeout=0.1)
        except Exception as exc:
            state[key] = {"mm": None, "bytes": 0, "err": "打不开: %s" % exc}
            time.sleep(1.0)
            continue
        deadline = time.time() + 2.0
        buf = b""
        while time.time() < deadline and not state.get("stop"):
            buf += ser.read(64)
        ser.close()
        mm = None
        err = None
        for i in range(max(0, len(buf) - 3)):
            if buf[i] == 0xFF:
                h, l, c = buf[i + 1], buf[i + 2], buf[i + 3]
                if (0xFF + h + l) & 0xFF == c:
                    code = h * 256 + l
                    if code >= 30000:
                        # ≥30m 必为状态码非测距（L08 UART 版量程 5~200cm；0xFFFD=无有效回波，
                        # 空气台架为规格预期——见 l08_probe.py 头注）
                        mm, err = None, "状态码 0x%04X（无回波，空气中预期）" % code
                    else:
                        mm = code
                    break
        state[key] = {"mm": mm, "bytes": len(buf), "err": err}


def read_w1_slave(slave):
    try:
        lines = open(slave, encoding="utf-8").read().splitlines()
        ok = bool(lines) and lines[0].strip().endswith("YES")
        for line in lines:
            if "t=" in line:
                return ok, int(line.split("t=", 1)[1]) / 1000.0
        return ok, None
    except Exception:
        return False, None


def fast_snapshot(state):
    """0.1s 级快查：I2C + 1-Wire + Pixhawk（超声波走后台线程状态）。"""
    s = {
        "us_front": state.get("us_front", {"mm": None, "bytes": 0, "err": "线程未就绪"}),
        "us_down": state.get("us_down", {"mm": None, "bytes": 0, "err": "线程未就绪"}),
        "ms5837_76": i2c_probe(5, 0x76),
        "ms5837_77": i2c_probe(5, 0x77),
        "veml_front": i2c_probe(5, 0x10),
        "veml_down": i2c_probe(0, 0x10),
        "pixhawk": os.path.exists("/dev/ttyACM0"),
    }
    probes = []
    for p in sorted(glob.glob("/sys/bus/w1/devices/28-*")):
        crc_ok, temp = read_w1_slave(os.path.join(p, "w1_slave"))
        realpath = os.path.realpath(p)
        bus = "总线1/37脚" if "master1" in realpath else ("总线2/15脚" if "master2" in realpath else "?")
        probes.append({"id": os.path.basename(p), "ok": crc_ok, "temp": temp, "bus": bus})
    s["ds18b20"] = probes
    return s


def online_count(s):
    return sum([
        bool(s["us_front"]["mm"]), bool(s["us_down"]["mm"]),
        s["ms5837_76"] or s["ms5837_77"], s["veml_front"], s["veml_down"],
        bool(s["ds18b20"]), s["pixhawk"],
    ])


def diff_events(prev, s):
    us_f_desc = ("前视超声波(ttyS7)有帧 %dmm" % s["us_front"]["mm"]) if s["us_front"]["mm"] else "前视超声波(ttyS7)有帧"
    us_d_desc = ("下视超声波(ttyS1)有帧 %dmm" % s["us_down"]["mm"]) if s["us_down"]["mm"] else "下视超声波(ttyS1)有帧"
    checks = [
        ("us_front", bool(s["us_front"]["mm"]), us_f_desc),
        ("us_down", bool(s["us_down"]["mm"]), us_d_desc),
        ("ms5837", s["ms5837_76"] or s["ms5837_77"],
         "MS5837 上线@%s" % ("0x76" if s["ms5837_76"] else "0x77")),
        ("veml_front", s["veml_front"], "VEML7700前视(bus5/3脚SDA,5脚SCL)上线"),
        ("veml_down", s["veml_down"], "VEML7700下视(bus0/27脚SDA,28脚SCL)上线"),
        ("pixhawk", s["pixhawk"], "Pixhawk ttyACM0 在位"),
    ]
    for key, on, desc in checks:
        if key in prev and prev[key] != on:
            log_event(desc if on else desc.replace("上线", "掉线").replace("有帧", "停帧").replace("在位", "拔出"))
    prev_ids = prev.get("_w1ids", set())
    for p in s["ds18b20"]:
        if p["id"] not in prev_ids:
            log_event("DS18B20 %s 上线@%s 温度=%.2f°C" % (p["id"], p["bus"], p["temp"] or -99))
    new_prev = {"_w1ids": {p["id"] for p in s["ds18b20"]}}
    for key, on, _ in checks:
        new_prev[key] = on
    return new_prev


def log_line(s, cycle):
    def mark(v):
        return "✓" if v else "-"
    us_f = ("%dmm" % s["us_front"]["mm"]) if s["us_front"]["mm"] else "-"
    us_d = ("%dmm" % s["us_down"]["mm"]) if s["us_down"]["mm"] else "-"
    ms = "0x76" if s["ms5837_76"] else ("0x77" if s["ms5837_77"] else "-")
    ds = ("%d只:%s" % (len(s["ds18b20"]), ",".join("%.1f°C@%s" % (p["temp"] or -99, p["bus"][-3:]) for p in s["ds18b20"]))) if s["ds18b20"] else "-"
    parts = [
        "前视超声:%s" % us_f,
        "下视超声:%s" % us_d,
        "MS5837:%s" % ms,
        "VEML前:%s" % mark(s["veml_front"]),
        "VEML下:%s" % mark(s["veml_down"]),
        "DS18B20:%s" % ds,
        "Pixhawk:%s" % mark(s["pixhawk"]),
    ]
    return "%s 在线%d/7 | %s" % (time.strftime("%H:%M:%S.%f")[:-4], online_count(s), "  ".join(parts))


def render(s, cycle, last_events):
    out = [CLEAR + BOLD + "SeaUI 传感器实时看板  第 %d 轮  在线 %d/7" % (cycle, online_count(s)) + END]
    f, d = s["us_front"], s["us_down"]
    out.append("  %s 前视超声波 ttyS7   %s" % (GREEN + "●" + END if f["mm"] else DIM + "○" + END,
                                              ("距离 %d mm" % f["mm"]) if f["mm"] else (f["err"] or "无帧(%dB)" % f["bytes"])))
    out.append("  %s 下视超声波 ttyS1   %s" % (GREEN + "●" + END if d["mm"] else DIM + "○" + END,
                                              ("距离 %d mm" % d["mm"]) if d["mm"] else (d["err"] or "无帧(%dB)" % d["bytes"])))
    ms = s["ms5837_76"] or s["ms5837_77"]
    out.append("  %s MS5837 bus5       %s" % (GREEN + "●" + END if ms else DIM + "○" + END,
                                              ("在线@" + ("0x76" if s["ms5837_76"] else "0x77")) if ms else "无应答(3脚SDA/5脚SCL,I2C5)"))
    out.append("  %s VEML7700 前视 bus5 %s" % (GREEN + "●" + END if s["veml_front"] else DIM + "○" + END,
                                              "在线@0x10" if s["veml_front"] else "无应答(3脚SDA/5脚SCL)"))
    out.append("  %s VEML7700 下视 bus0 %s" % (GREEN + "●" + END if s["veml_down"] else DIM + "○" + END,
                                              "在线@0x10" if s["veml_down"] else "无应答(27脚SDA/28脚SCL)"))
    if s["ds18b20"]:
        for p in s["ds18b20"]:
            detail = "%.2f °C" % p["temp"] if p["temp"] is not None else ("CRC错" if not p["ok"] else "无t值")
            out.append("  %s DS18B20 %s @%s  %s" % (GREEN + "●" + END if p["ok"] else YELLOW + "●" + END,
                                                    p["id"], p["bus"], detail))
    else:
        out.append("  %s DS18B20 双总线      无探头(总线在，接上即出 28-xxx)" % (DIM + "○" + END))
    out.append("  %s Pixhawk ttyACM0    %s" % (GREEN + "●" + END if s["pixhawk"] else DIM + "○" + END,
                                              "在位" if s["pixhawk"] else "USB 未插"))
    out.append("")
    out.append(BOLD + "事件流（另存 %s）" % EVENT_LOG + END)
    with events_lock:
        recent = list(events[-12:])
    for stamp, text in recent:
        out.append("  [%s] %s" % (stamp, text))
    if not recent:
        out.append(DIM + "  （暂无变化——接对线的瞬间这里会跳出记录）" + END)
    out.append("")
    out.append(DIM + "提示：正负极接反=永不上线且发热(赶紧断电)；信号线接错=交换后事件流立即记录。Ctrl+C 退出。" + END)
    return "\n".join(out)


def main():
    log_mode = "--log" in sys.argv
    once = "--once" in sys.argv
    interval = 0.1
    for arg in sys.argv:
        if arg.startswith("--interval="):
            interval = max(0.05, float(arg.split("=", 1)[1]))

    state = {"stop": False}
    if serial is not None:
        threading.Thread(target=uart_worker, args=("/dev/ttyS7", state, "us_front"), daemon=True).start()
        threading.Thread(target=uart_worker, args=("/dev/ttyS1", state, "us_down"), daemon=True).start()

    prev = {}
    cycle = 0
    last_render = 0.0
    while True:
        cycle += 1
        s = fast_snapshot(state)
        prev = diff_events(prev, s)
        if log_mode:
            print(log_line(s, cycle), flush=True)
        elif once:
            print(render(s, cycle, True))
            return
        else:
            now = time.time()
            if now - last_render >= 0.5:
                sys.stdout.write(render(s, cycle, False) + "\n")
                sys.stdout.flush()
                last_render = now
        time.sleep(interval)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n退出。事件日志保留在 %s" % EVENT_LOG)
