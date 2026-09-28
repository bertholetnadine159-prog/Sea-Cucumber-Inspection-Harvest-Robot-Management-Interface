#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""高电平触发探针：针对 TRIGGER_HIGH 型 DYP 声纳。

UART 空闲为高电平；发送 4 个 0xFF 字节 = 线路保持连续高电平约 4ms，
等效 pwm.ino 中 TRIGGER_HIGH 模式的"高脉冲触发"。触发后收 4 字节 FF 帧。
"""

from __future__ import annotations

import argparse
import serial
import time


def main() -> int:
    parser = argparse.ArgumentParser(description="高电平触发探针")
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=9600)
    parser.add_argument("--rounds", type=int, default=6)
    args = parser.parse_args()

    ser = serial.Serial(args.port, args.baud, timeout=0.05)
    print(f"{args.port} @ {args.baud}：高脉冲触发（发 FF FF FF FF ≈ 4ms 连续高），共 {args.rounds} 轮")
    any_data = False
    for n in range(args.rounds):
        ser.reset_input_buffer()
        ser.write(b"\xFF\xFF\xFF\xFF")
        ser.flush()
        t0 = time.time()
        buf = b""
        while time.time() - t0 < 0.4:
            chunk = ser.read(64)
            if chunk:
                buf += chunk
                if b"\xff" in buf and len(buf) >= 4:
                    break
        if buf:
            any_data = True
            print(f"  轮{n + 1}: {buf.hex(' ')}")
        time.sleep(0.4)
    ser.close()
    if not any_data:
        print("VERDICT: HIGH_TRIGGER_SILENT —— 高脉冲触发无响应")
        return 1
    print("VERDICT: HIGH_TRIGGER_DATA —— 有数据上来（声纳存活）")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
