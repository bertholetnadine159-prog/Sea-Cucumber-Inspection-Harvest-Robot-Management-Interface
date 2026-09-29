#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""I2C 总线卡死恢复（9 个时钟脉冲 + STOP，I2C 规范标准救总线法）。

用法（板卡上）：python3 scripts/i2c_bus_recover.py [5]
只支持本项目已知总线 I2C5（docs/PINMAP.md §3 权威映射）：
  SDA = SOC390 = 40-pin 3脚；SCL = SOC389 = 40-pin 5脚。
sysfs 交互走 shell 命令（与 super_query/board_super_query 同一模式）；
恢复时钟为毫秒级——I2C 从机容忍慢时钟，不影响恢复效果。

原理：从机在传输中途被复位会持续拉低 SDA 等下一个位，主机发不出 START。
标准恢复 = 释放两条线，若 SDA 低则手动打 9 个 SCL 时钟让从机吐完剩余位，
再补一个 STOP（SCL 高时 SDA 由低到高）。若打完时钟 SDA 仍为低 = 硬件短路/
接错，不是从机挂住。
实测（2026-09-29）：I2C5 两线释放后均高——总线未被拉死，NACK 的根因在
器件侧（没供电/SDA-SCL 接反/接错脚），不在卡死。
"""
import subprocess
import sys
import time

# 只允许 I2C5 的两个已知垫片（全字面路径）
SDA_GPIO = 390
SCL_GPIO = 389
SDA_VALUE = "/sys/class/gpio/gpio390/value"
SCL_VALUE = "/sys/class/gpio/gpio389/value"


def sh(cmd, timeout=5):
    return subprocess.run(["sh", "-c", cmd], capture_output=True, text=True,
                          timeout=timeout)


def write_sys(path, content):
    sh("echo %s > %s" % (content, path))


def read_value(path):
    r = sh("cat %s 2>/dev/null" % path)
    return r.stdout.strip()


def export_gpio(gpio):
    sh("test -d /sys/class/gpio/gpio%d || echo %d > /sys/class/gpio/export" % (gpio, gpio))
    time.sleep(0.05)


def release_gpio(gpio):
    sh("echo %d > /sys/class/gpio/unexport 2>/dev/null" % gpio)


def main():
    if len(sys.argv) > 1 and sys.argv[1] != "5":
        print("I2C_RECOVER: 拒绝——只支持 I2C5（用法: i2c_bus_recover.py [5]）")
        return 1
    export_gpio(SDA_GPIO)
    export_gpio(SCL_GPIO)
    try:
        # 双线释放为输入（靠板上拉回高）
        write_sys("/sys/class/gpio/gpio390/direction", "in")
        write_sys("/sys/class/gpio/gpio389/direction", "in")
        time.sleep(0.01)
        sda_v = read_value(SDA_VALUE)
        scl_v = read_value(SCL_VALUE)
        print("I2C_RECOVER bus5: 释放后 SDA=%s SCL=%s" % (sda_v, scl_v))

        if sda_v == "1" and scl_v == "1":
            print("I2C_RECOVER: 两线均为高——总线未被拉死（问题在器件应答/接线，不在卡死）")
        elif sda_v == "0":
            # SCL 打 9 个时钟（shell 写入为毫秒级，从机容忍慢时钟）
            for _ in range(9):
                write_sys("/sys/class/gpio/gpio389/direction", "out")  # SCL 低
                time.sleep(0.000005)
                write_sys("/sys/class/gpio/gpio389/direction", "in")   # 释放回高
                time.sleep(0.000005)
            # STOP：SCL 高时 SDA 拉低再释放
            write_sys("/sys/class/gpio/gpio390/value", "0")
            write_sys("/sys/class/gpio/gpio390/direction", "out")
            time.sleep(0.00001)
            write_sys("/sys/class/gpio/gpio390/direction", "in")
            time.sleep(0.01)
            sda_v2 = read_value(SDA_VALUE)
            scl_v2 = read_value(SCL_VALUE)
            if sda_v2 == "1":
                print("I2C_RECOVER: 9-clock + STOP 后 SDA 回高（%s/%s）——从机挂住已解除，可重扫"
                      % (sda_v2, scl_v2))
            else:
                print("I2C_RECOVER: 9-clock + STOP 后 SDA 仍为低（%s/%s）"
                      "——SDA 对地短路/SDA-SCL 接反/器件损坏，查接线" % (sda_v2, scl_v2))
        else:
            print("I2C_RECOVER: SCL 被拉低（%s/%s）——SCL 短路/接反，软件无法恢复"
                  % (sda_v, scl_v))
    finally:
        release_gpio(SDA_GPIO)
        release_gpio(SCL_GPIO)
    return 0


if __name__ == "__main__":
    sys.exit(main())
