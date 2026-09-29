#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""I2C5 断电监听：窗口内连续记录 总线线电平变化 + 全地址轮询应答。

用法（板卡上）：python3 scripts/i2c5_power_watch.py [秒=75]
配合用户手动给深度计断电/复电：任何地址应答、任何线电平跳变都带时间戳打印。
铁律：只报真实事件，不做任何合成推断。
"""
import subprocess
import sys
import time

from smbus2 import SMBus

DUR = float(sys.argv[1]) if len(sys.argv) > 1 else 75.0
BUS = 5
ADDRS = list(range(0x03, 0x78))
SDA_GPIO, SCL_GPIO = 390, 389  # I2C5：SDA=3脚 SCL=5脚（docs/PINMAP.md §3）


def sh(cmd, timeout=2):
    return subprocess.run(["sh", "-c", cmd], capture_output=True, text=True,
                          timeout=timeout)


def read_gpio(pin):
    r = sh("cat /sys/class/gpio/gpio%d/value 2>/dev/null" % pin)
    return r.stdout.strip()


for pin in (SDA_GPIO, SCL_GPIO):
    sh("test -d /sys/class/gpio/gpio%d || echo %d > /sys/class/gpio/export" % (pin, pin))
    sh("echo in > /sys/class/gpio/gpio%d/direction" % pin)
time.sleep(0.05)

bus = SMBus(BUS)
t0 = time.monotonic()
last_sda, last_scl = read_gpio(SDA_GPIO), read_gpio(SCL_GPIO)
print("[+  0.0s] 监听开始（窗口 %.0fs）| 初始 SDA=%s SCL=%s" % (DUR, last_sda, last_scl), flush=True)

events = 0
i = 0
CHUNK = 12
last_errno = None
last_errno_t = 0.0
while time.monotonic() - t0 < DUR:
    t = time.monotonic() - t0
    for addr in ADDRS[i:i + CHUNK]:
        try:
            bus.write_quick(addr)
            print("[+%6.1fs] *** 地址应答 0x%02X ***" % (t, addr), flush=True)
            events += 1
        except Exception:
            pass
    i = (i + CHUNK) % len(ADDRS)
    # 每 5s 对配置地址 0x76 做一次带错误分类的读（断电/复电会改变错误类型）
    if t - last_errno_t >= 5.0:
        last_errno_t = t
        try:
            bus.read_byte(0x76)
            state = "ack"
        except OSError as exc:
            state = "errno%s" % exc.errno  # 121=NACK(无应答) 110=控制器超时
        except Exception as exc:
            state = type(exc).__name__
        if state != last_errno:
            print("[+%6.1fs] 0x76 读状态 %s -> %s" % (t, last_errno, state), flush=True)
            events += 1
            last_errno = state
    sda, scl = read_gpio(SDA_GPIO), read_gpio(SCL_GPIO)
    if sda != last_sda or scl != last_scl:
        print("[+%6.1fs] 线电平变化 SDA %s->%s  SCL %s->%s"
              % (t, last_sda, sda, last_scl, scl), flush=True)
        last_sda, last_scl = sda, scl
        events += 1
    if events > 400:
        print("事件超上限，提前结束", flush=True)
        break

print("[+%6.1fs] 监听结束，共 %d 个事件" % (time.monotonic() - t0, events), flush=True)
