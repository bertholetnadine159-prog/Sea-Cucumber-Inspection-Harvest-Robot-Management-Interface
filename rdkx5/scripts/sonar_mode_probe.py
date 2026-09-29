#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""声纳"被动监听 vs 触发"对照探针（板卡上执行）。

用法：python3 scripts/sonar_mode_probe.py /dev/ttyS7
逻辑：
  阶段1 被动监听 3s（不发任何触发）——有帧 = 模组处于自动上报模式
  阶段2 send_break 40ms 触发后收 1s——有帧 = 受控模式正常应答
  阶段3 再被动监听 1s
全部打印原始十六进制，不做任何合成推断。
"""
import sys
import time

PORT = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyS7"


def hexdump(buf: bytes) -> str:
    return " ".join(f"{b:02X}" for b in buf[:64])


def collect(ser, seconds: float):
    buf = b""
    deadline = time.time() + seconds
    while time.time() < deadline:
        chunk = ser.read(64)
        if chunk:
            buf += chunk
    return buf


def main() -> int:
    import serial

    ser = serial.Serial(port=PORT, baudrate=115200, timeout=0.05)
    try:
        ser.reset_input_buffer()
        print(f"[{PORT}] 阶段1 被动监听 3s（无触发）…")
        b1 = collect(ser, 3.0)
        print(f"  收到 {len(b1)} 字节: {hexdump(b1) if b1 else '(静默)'}")

        print(f"[{PORT}] 阶段2 触发（RX 拉低 40ms）后收 1s …")
        try:
            ser.send_break(duration=0.04)
        except Exception as exc:
            print(f"  send_break 失败: {exc}")
        b2 = collect(ser, 1.0)
        print(f"  收到 {len(b2)} 字节: {hexdump(b2) if b2 else '(静默)'}")

        print(f"[{PORT}] 阶段3 触发后再被动监听 1s …")
        b3 = collect(ser, 1.0)
        print(f"  收到 {len(b3)} 字节: {hexdump(b3) if b3 else '(静默)'}")

        if b1:
            print(f"VERDICT[{PORT}]: AUTO_MODE（被动即有帧——模组自动上报模式）")
        elif b2:
            print(f"VERDICT[{PORT}]: TRIGGER_OK（受控模式应答正常）")
        else:
            print(f"VERDICT[{PORT}]: SILENT（被动+触发均无帧——TX 未到板/未供电/线序错）")
        return 0
    finally:
        ser.close()


if __name__ == "__main__":
    sys.exit(main())
