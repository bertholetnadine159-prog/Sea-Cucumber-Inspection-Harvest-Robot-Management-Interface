#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""I2C5 深度计真实地址穷举探测（多探测模式 + 连续监听 + MS5837 身份验证）。

用法（板卡上）：python3 scripts/i2c5_addr_hunt.py [bus]（默认 5）

背景：某些深度计模组对 i2cdetect 的默认探测不应答（"找不到真实地址"），
不同探测方式（SMBus quick / 读字节 / 写探测 / 写寄存器后读）应答行为不同，
且可能有上电延迟或间歇应答。本脚本：
  1) 全地址 0x03-0x77 × 4 种探测方式 × 3 轮；
  2) 30s 连续监听抓间歇应答；
  3) 对任何应答地址做 MS5837 身份验证（复位 0x1E + PROM 8 系数 + CRC4）。
铁律：只报真实应答，不做任何合成推断。
"""
import sys
import time

from smbus2 import SMBus

BUS = int(sys.argv[1]) if len(sys.argv) > 1 else 5
ADDRS = list(range(0x03, 0x78))


def ack_modes(bus, addr):
    modes = []
    for name, fn in (
        ("quick", lambda: bus.write_quick(addr)),
        ("rd", lambda: bus.read_byte(addr)),
        ("wr0", lambda: bus.write_byte(addr, 0x00)),
    ):
        try:
            fn()
            modes.append(name)
        except Exception:
            pass
    return modes


def errno_sample(bus, addr):
    try:
        bus.read_byte(addr)
        return "ack"
    except OSError as exc:
        return f"errno{exc.errno}"
    except Exception as exc:
        return type(exc).__name__


def crc4(prom):
    """MS5837/MS5xxx PROM CRC4 校验（标准算法，返回 4 位 CRC 应=0）。"""
    n_rem = 0x3000
    cnt = 0
    bits = [0] * 16
    for i in range(16):
        if i % 2 == 0:
            bits[i] = (prom[cnt // 2] >> 8) & 0xFF
        else:
            bits[i] = prom[cnt // 2] & 0xFF
            cnt += 1
    for i in range(16):
        if i == 0:
            b = bits[0] & 0x0F
        else:
            b = bits[i] >> 4 if i % 2 == 0 else bits[i] & 0x0F
        if i % 2 == 1:
            b = bits[i] & 0x0F
        elif i == 0:
            b = bits[0] & 0x0F
        else:
            b = bits[i] >> 4
        if i == 1 or i == 15:
            b = 0
        n_rem ^= b
        for _ in range(4):
            if n_rem & 0x8000:
                n_rem = (n_rem << 1) ^ 0x3000
            else:
                n_rem <<= 1
    return (n_rem >> 12) & 0x0F


def probe_identity(bus, addr):
    """MS5837 身份验证：复位 -> PROM 读 8 系数 -> CRC4。"""
    try:
        bus.write_byte(addr, 0x1E)  # reset
        time.sleep(0.02)
        prom = []
        for i in range(8):
            data = bus.read_i2c_block_data(addr, 0xA0 + i * 2, 2)
            prom.append((data[0] << 8) | data[1])
        c = crc4(prom)
        manufacturer = prom[7] & 0x0F
        print(f"  IDENTITY 0x{addr:02X}: PROM={[f'{v:04X}' for v in prom]} "
              f"CRC4={'OK(0)' if c == 0 else f'FAIL({c})'} 厂商低4位={manufacturer}")
        return prom
    except Exception as exc:
        print(f"  IDENTITY 0x{addr:02X}: 失败 {exc}")
        return None


def main():
    bus = SMBus(BUS)
    found = {}
    for rnd in range(3):
        for addr in ADDRS:
            modes = ack_modes(bus, addr)
            if modes:
                found.setdefault(addr, set()).update(modes)
                print(f"ROUND{rnd + 1}: 0x{addr:02X} ACK via {modes}")
        time.sleep(0.5)
    print("== 三轮汇总 ==")
    if not found:
        print("(三轮无任何地址应答——排除上电延迟后仍全暗)")
    for addr in sorted(found):
        print(f"0x{addr:02X}: 探测方式 {sorted(found[addr])} 样例={errno_sample(bus, addr)}")

    print("== 30s 连续监听（抓间歇应答） ==")
    seen = set(found)
    t0 = time.time()
    while time.time() - t0 < 30:
        for addr in ADDRS:
            try:
                bus.write_quick(addr)
                if addr not in seen:
                    seen.add(addr)
                    print(f"[{time.time() - t0:5.1f}s] 新应答: 0x{addr:02X} "
                          f"(样例={errno_sample(bus, addr)})")
            except Exception:
                pass
    print("监听结束，全部应答地址:", [f"0x{a:02X}" for a in sorted(seen)] or "无")

    for addr in sorted(seen):
        probe_identity(bus, addr)
    bus.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
