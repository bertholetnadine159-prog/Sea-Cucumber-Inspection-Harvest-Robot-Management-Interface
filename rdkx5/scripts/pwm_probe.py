#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""PWM 型超声波声纳距离读取探针（DYP A02/ME007 PWM 输出型）。

协议（examples/pwm/pwm.ino 考证）：
  触发：传感器 RX 上 100µs 低脉冲（下降沿触发，周期须 >70ms，例程 500ms 一轮）
  输出：传感器 TX 输出一个 TTL 高电平脉宽 T，距离 S = T / 57.5 (cm)，声速 348m/s
  无目标：输出约 35ms 固定脉宽

实现：RX 以 921600 波特打开（位宽 1.085µs）。PWM 高电平 = 线路空闲（无字节），
低电平 = 连续 0x00 字节流。以每字节的接收时间戳测"触发结束 -> 下一低电平字节流
起始"的间隔，即高电平脉宽，精度约 ±20µs（≈±0.4cm）。

用法：python3 rdkx5/scripts/pwm_probe.py --port /dev/ttyS7 --samples 10
"""

from __future__ import annotations

import argparse
import time

TRIGGER_BREAK_S = 0.0001   # 100µs 触发低脉冲（send_break 连续低电平）
SAMPLE_PERIOD_S = 0.5      # 例程序节奏：500ms 一轮
NO_TARGET_WIDTH_US = 35000  # 无目标固定脉宽（约 35ms）
SOUND_DIVIDER = 57.5        # 距离(cm) = 脉宽(µs) / 57.5


def main() -> int:
    parser = argparse.ArgumentParser(description="PWM 型声纳距离读取")
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=921600)
    parser.add_argument("--samples", type=int, default=10)
    args = parser.parse_args()

    try:
        import serial
    except ImportError:
        print("[FAIL] 未安装 pyserial")
        return 3

    try:
        ser = serial.Serial(args.port, args.baud, timeout=0.02)
    except Exception as exc:
        print(f"[FAIL] 打开 {args.port} 失败: {exc}")
        return 3

    print(f"PWM 声纳探针：{args.port} @ {args.baud}，每 {int(SAMPLE_PERIOD_S*1000)}ms 触发一次，共 {args.samples} 次采样")
    readings: list[float] = []
    try:
        for n in range(args.samples):
            # 触发：100µs 连续低电平（下降沿触发模组）
            ser.reset_input_buffer()
            ser.send_break(duration=TRIGGER_BREAK_S)
            ser.flush()
            trigger_end = time.time()
            # 等高电平脉宽结束：脉宽期线路空闲（无字节），结束后低电平字节流到来。
            # 第一批字节的到达时刻 - 触发结束时刻 ≈ 高电平脉宽。
            first_byte_at = None
            deadline = trigger_end + 0.5
            got = b""
            while time.time() < deadline:
                chunk = ser.read(256)
                if chunk:
                    if first_byte_at is None:
                        first_byte_at = time.time()
                    got += chunk
                    # 低电平字节流持续 ~触发脉宽之外的整个低周期；采到即认为脉宽已结束
                    if len(got) >= 16:
                        break
            if first_byte_at is None:
                print(f"  [{n+1}/{args.samples}] 无任何字节（模组未响应触发）")
                continue
            width_us = (first_byte_at - trigger_end) * 1e6
            if width_us > NO_TARGET_WIDTH_US * 1.4:
                note = "超出量程/无目标"
                dist_cm = None
            else:
                dist_cm = width_us / SOUND_DIVIDER
                note = f"≈{dist_cm:.1f} cm" + ("（无目标 35ms 固定脉宽）" if abs(width_us - NO_TARGET_WIDTH_US) < 3000 else "")
            print(f"  [{n+1}/{args.samples}] 脉宽 ≈ {width_us:.0f} µs -> {note}（原始 {len(got)}B）")
            if dist_cm is not None:
                readings.append(dist_cm)
            time.sleep(SAMPLE_PERIOD_S - 0.06)
    finally:
        ser.close()

    if readings:
        ok = [d for d in readings if d < 700]
        print(f"VERDICT: PWM_OK —— 有效读数 {len(ok)}/{args.samples}："
              + (f"min={min(ok):.1f}cm max={max(ok):.1f}cm" if ok else "全部为无目标状态"))
        return 0
    print("VERDICT: PWM_SILENT —— 声纳未响应 PWM 触发（检查接线/供电/型号）")
    return 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
