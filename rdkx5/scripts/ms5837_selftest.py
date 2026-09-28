#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""MS5837 健康自检：判定传感器本身是好是坏，还是根本没接上。

在 RDK X5 板卡上直接运行（需要 smbus2）：
    python3 rdkx5/scripts/ms5837_selftest.py            # 默认 bus 5, 0x76
    python3 rdkx5/scripts/ms5837_selftest.py --bus 1 --addr 0x77

判定逻辑（金标准是 CRC4）：
  1. 总线扫描 0x76/0x77 —— 无应答 = 接线/供电问题（传感器好坏未知）
  2. 读 PROM 8 个系数：
       全 0x0000 / 全 0xFFFF            = 无有效应答，先查接线
       系数有值但 CRC4 校验失败         = 数据线干扰大（缩短线/加去耦）
       CRC4 通过                        = 传感器芯片真实存在且健康
  3. 触发一次压力(D1)/温度(D2)转换并读回：
       D1/D2 全 0                       = 转换异常（时钟拉伸/接触不良）
       D1/D2 有合理值并算出压力温度     = 传感器完全正常
"""

from __future__ import annotations

import argparse
import sys
import time

RESET_CMD = 0x1E      # 复位
READ_PROM_BASE = 0xA0  # PROM 系数寄存器基址（A0..AE 共 8 字）
CONVERT_D1 = {4096: 0x44, 8192: 0x48, 512: 0x46}   # 压力转换命令（OSR）
CONVERT_D2 = {4096: 0x54, 8192: 0x58, 512: 0x56}   # 温度转换命令（OSR）
READ_ADC = 0x00


def crc4(prom: list[int]) -> int:
    """MS58xx 标准 CRC4 校验（BlueRobotics 同款算法）。"""
    p = list(prom)
    p[0] &= 0xFF00  # 低 4 位是 CRC 本身，参与校验前置零
    n_rem = 0x0000
    for i in range(16):
        if i % 2 == 1:
            n_rem ^= p[i >> 1] & 0x00FF
        else:
            n_rem ^= p[i >> 1] >> 8
        for _ in range(8):
            n_rem = (n_rem << 1) ^ 0x3000 if n_rem & 0x8000 else n_rem << 1
    return (n_rem >> 12) & 0x000F


def scan(bus, want: list[int]) -> int | None:
    """在总线上找 MS5837 地址。"""
    for addr in want:
        try:
            bus.read_byte(addr)
            return addr
        except OSError:
            continue
    return None


def read_prom(bus, addr: int) -> list[int] | None:
    try:
        words = []
        for i in range(8):
            w = bus.read_word_data(addr, READ_PROM_BASE + i * 2)
            words.append(((w & 0xFF) << 8) | (w >> 8))  # smbus 小端 → MS5837 大端
        return words
    except OSError as exc:
        print(f"  读 PROM 失败: {exc}")
        return None


def convert_and_read(bus, addr: int, cmd: int, wait_s: float) -> int | None:
    try:
        bus.write_byte(addr, cmd)
        time.sleep(wait_s)
        raw = bus.read_i2c_block_data(addr, READ_ADC, 3)
        return (raw[0] << 16) | (raw[1] << 8) | raw[2]
    except OSError as exc:
        print(f"  转换读取失败(cmd=0x{cmd:02X}): {exc}")
        return None


def compute_30ba(d1: int, d2: int, c: list[int]) -> tuple[float, float]:
    """MS5837-30BA 一阶+二阶补偿（BlueRobotics 同款），返回 (温度°C, 压力 mbar)。"""
    dT = d2 - c[4] * 256
    temp = 2000 + dT * c[5] / 8388608
    off = c[1] * 131072 + (c[3] * dT) / 128
    sens = c[0] * 65536 + (c[2] * dT) / 256
    t2 = off2 = sens2 = 0.0
    if temp >= 2000:
        t2 = 3 * dT * dT / 8589934592
        off2 = 1 * (temp - 2000) ** 2 / 32768
        sens2 = 0
    else:
        t2 = 3 * dT * dT / 8589934592
        off2 = 3 * (temp - 2000) ** 2 / 128
        sens2 = 5 * (temp - 2000) ** 2 / 8192
        if temp < -1500:
            off2 += 7 * (temp + 1500) ** 2
            sens2 += 4 * (temp + 1500) ** 2
    temp = (temp - t2) / 100
    press = ((d1 * (sens - sens2) / 4194304 - (off - off2)) / 16384) / 10
    return temp, press


def main() -> int:
    parser = argparse.ArgumentParser(description="MS5837 健康自检")
    parser.add_argument("--bus", type=int, default=5)
    parser.add_argument("--addr", default="0x76")
    args = parser.parse_args()
    want = [int(args.addr, 16)] + ([0x77] if int(args.addr, 16) != 0x77 else [])

    try:
        from smbus2 import SMBus
    except ImportError:
        print("[FAIL] 未安装 smbus2：pip3 install -i https://pypi.tuna.tsinghua.edu.cn/simple smbus2")
        return 3

    print(f"[1/4] 扫描 I2C-{args.bus} 的 0x76/0x77 ...")
    with SMBus(args.bus) as bus:
        addr = scan(bus, want)
        if addr is None:
            print("  VERDICT: NOT_ON_BUS —— 传感器无应答（好坏未知，先查硬件）")
            print("  排查：SDA/SCL 是否接反 → 3.3V 供电 → 共地 → 上拉电阻")
            return 2
        print(f"  地址 0x{addr:02X} 有应答")

        print("[2/4] 复位并读 PROM 8 系数 ...")
        try:
            bus.write_byte(addr, RESET_CMD)
            time.sleep(0.01)
        except OSError as exc:
            print(f"  [FAIL] 复位失败: {exc}")
            return 2
        prom = read_prom(bus, addr)
        if prom is None:
            print("  VERDICT: BUS_UNSTABLE —— 总线不稳定（线太长/干扰/接触不良）")
            return 2
        print("  PROM:", " ".join(f"C{i + 1}=0x{w:04X}" for i, w in enumerate(prom)))
        if all(w == 0x0000 for w in prom) or all(w == 0xFFFF for w in prom):
            print("  VERDICT: NOT_ON_BUS —— 系数全 0/全 F，读到的不是有效芯片，先查接线与供电")
            return 2

        print("[3/4] CRC4 校验 PROM ...")
        calc, stored = crc4(prom), prom[0] & 0x000F
        print(f"  计算 CRC={calc:X}，芯片存储 CRC={stored:X}")
        if calc != stored:
            print("  VERDICT: CRC_FAIL —— 系数校验失败：数据线干扰大或芯片异常（缩短线/换线再试）")
            return 1
        print("  [OK] CRC 通过 —— 传感器芯片真实且应答正确")

        print("[4/4] 触发压力/温度转换 ...")
        d1 = convert_and_read(bus, addr, CONVERT_D1[8192], 0.02)
        d2 = convert_and_read(bus, addr, CONVERT_D2[8192], 0.02)
        if not d1 or not d2:
            print("  VERDICT: CONV_FAIL —— 转换读数全 0/失败：接触不良或器件异常")
            return 1
        temp_c, press_mbar = compute_30ba(d1, d2, prom)
        print(f"  D1={d1} D2={d2}")
        print(f"  压力 ≈ {press_mbar:.1f} mbar（水面大气压约 1013 mbar，入水每深 1m +~100 mbar）")
        print(f"  温度 ≈ {temp_c:.2f} °C")
        print("VERDICT: SENSOR_GOOD —— 传感器完全正常（CRC 通过 + 转换读数有效）")
        return 0


if __name__ == "__main__":
    sys.exit(main())
