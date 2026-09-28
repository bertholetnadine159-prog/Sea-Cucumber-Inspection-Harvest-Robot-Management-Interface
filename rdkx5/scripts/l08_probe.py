#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""DYP-L08-V3.0 声纳距离读取探针（UART 受控型，按官方规格书 V1.2）。

规格要点（DYP-RD-产品规格书 L08-V3.0 §3.1）：
  波特率 115200 8N1（TTL5V 电平）；触发 = RX 低脉冲，T1 > T2+15ms（T2≈18ms），
  即 RX 拉低须 >33ms；触发周期 >33ms；超 5 秒无触发进入休眠。
  输出帧：FF + Data_H + Data_L + SUM，SUM=(FF+DH+DL)&0xFF，距离 mm = DH*256+DL。
  出水状态：输出 0xFFFB（需先经 Modbus 0x0401 开启并标定）。

用法：python3 rdkx5/scripts/l08_probe.py --port /dev/ttyS7 --rounds 5
"""

from __future__ import annotations

import argparse
import time

import serial

TRIGGER_LOW_S = 0.040   # RX 拉低 40ms（规格要求 >33ms）
SETTLE_S = 0.005
FRAME_WAIT_S = 0.30     # 帧输出 T2≈18ms，留足余量


def parse_ff(buf: bytes):
    """从缓冲提取最后一个合法 FF 帧，返回 (距离mm, 帧) 或 (None, None)。"""
    best = None
    for i in range(len(buf) - 3):
        if buf[i] != 0xFF:
            continue
        dh, dl, cs = buf[i + 1], buf[i + 2], buf[i + 3]
        if (0xFF + dh + dl) & 0xFF != cs:
            continue
        mm = dh * 256 + dl
        best = (mm, buf[i:i + 4])
    return best


def main() -> int:
    parser = argparse.ArgumentParser(description="DYP-L08-V3.0 声纳读取（115200 受控型）")
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--rounds", type=int, default=6)
    args = parser.parse_args()

    try:
        ser = serial.Serial(args.port, args.baud, bytesize=8, parity="N",
                            stopbits=1, timeout=0.05)
    except Exception as exc:
        print(f"[FAIL] 打开 {args.port} 失败: {exc}")
        return 3

    print(f"{args.port} @ {args.baud}（L08-V3.0 受控型）：触发=RX 拉低 40ms，收帧 300ms，共 {args.rounds} 轮")
    ok = 0
    seen = b""
    try:
        for n in range(args.rounds):
            ser.reset_input_buffer()
            # 规格时序：RX 拉低 40ms（>33ms），期间/随后模组输出一帧
            ser.break_condition = True   # TX 连续低电平
            t_end = time.time() + TRIGGER_LOW_S
            frame = None
            while time.time() < t_end:
                chunk = ser.read(64)
                if chunk:
                    seen += chunk
                    if frame is None:
                        frame = parse_ff(seen[-64:])
            ser.break_condition = False   # 释放线路（高电平）
            # 线路拉高后再收 300ms（帧可能在释放后才输出完）
            t_tail = time.time() + FRAME_WAIT_S
            while time.time() < t_tail and frame is None:
                chunk = ser.read(64)
                if chunk:
                    seen += chunk
                    frame = parse_ff(seen[-64:])

            if frame is None:
                # 也兼容模块把帧放在拉低期间内已收完的情况
                frame = parse_ff(seen[-128:])
            if frame:
                mm, raw = frame
                if mm == 0xFFFB:
                    print(f"  轮{n + 1}: 出水状态帧（0xFFFB）——模组存活")
                elif mm == 0:
                    print(f"  轮{n + 1}: 距离 0mm（盲区/无目标）帧 {raw.hex(' ')}")
                else:
                    print(f"  轮{n + 1}: 距离 = {mm} mm（{raw.hex(' ')}）")
                ok += 1
            else:
                print(f"  轮{n + 1}: 无合法 FF 帧" + (f"（杂散 {seen[-24:].hex(' ')}）" if seen else ""))
            seen = b""
            time.sleep(0.05)  # 触发周期 >33ms 已满足
    finally:
        ser.close()

    if ok:
        print(f"VERDICT: L08_OK —— 声纳正常应答（{ok}/{args.rounds} 轮有效）")
        return 0
    print("VERDICT: L08_SILENT —— 规格触发下仍无帧（查 5V 供电/共地/线序）")
    return 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
