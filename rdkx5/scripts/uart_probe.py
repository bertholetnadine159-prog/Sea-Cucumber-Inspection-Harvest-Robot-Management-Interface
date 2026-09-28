#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""串口收发探针：判定"串口本体好/坏"与"对端设备有无数据"。

在 RDK X5 板卡上运行：
    python3 rdkx5/scripts/uart_probe.py --port /dev/ttyS1            # 只收 3 秒
    python3 rdkx5/scripts/uart_probe.py --port /dev/ttyS7 --loopback # 回环自测

回环自测法（区分串口好坏与对端问题）：
  用杜邦线把该串口的 TXD 与 RXD 短接后加 --loopback：
  脚本发出 6 字节测试码，若原样收回 → 该串口收发硬件全部正常，
  问题在对端（声纳没接好/没供电）；收不到 → 串口引脚/复用问题。
"""

from __future__ import annotations

import argparse
import time

TEST_PATTERN = b"\xAA\x55\xFF\x00\x31\x7E"  # 含边沿丰富的测试码


def main() -> int:
    parser = argparse.ArgumentParser(description="串口收发探针")
    parser.add_argument("--port", required=True)
    parser.add_argument("--baud", type=int, default=9600)
    parser.add_argument("--seconds", type=float, default=3.0)
    parser.add_argument("--loopback", action="store_true", help="先发测试码再收（需短接 TXD/RXD）")
    parser.add_argument("--hex", action="store_true", help="按十六进制打印收到的数据")
    args = parser.parse_args()

    try:
        import serial
    except ImportError:
        print("[FAIL] 未安装 pyserial：pip3 install -i https://pypi.tuna.tsinghua.edu.cn/simple pyserial")
        return 3

    try:
        ser = serial.Serial(args.port, args.baud, timeout=0.1)
    except Exception as exc:
        print(f"[FAIL] 打开 {args.port} 失败: {exc}")
        return 3

    print(f"{args.port} @ {args.baud} 已打开，收听 {args.seconds}s ...")
    if args.loopback:
        ser.write(TEST_PATTERN)
        ser.flush()
        print(f"已发送测试码 {TEST_PATTERN.hex(' ')}")

    buf = b""
    deadline = time.time() + args.seconds
    while time.time() < deadline:
        buf += ser.read(256)
    ser.close()

    if not buf:
        print("VERDICT: RX_SILENT —— 未收到任何字节")
        if args.loopback:
            print("  回环失败：该串口 TX→RX 不通（引脚复用/串口本体问题）")
        else:
            print("  对端（声纳）无数据上来：查声纳供电、TXD/RXD 是否接反、共地")
        return 1

    shown = buf.hex(" ") if args.hex else buf.decode(errors="replace")
    print(f"收到 {len(buf)} 字节: {shown[:200]}")
    if args.loopback:
        if TEST_PATTERN in buf:
            print("VERDICT: LOOPBACK_OK —— 串口收发硬件正常，问题在对端接线/供电")
        else:
            print("VERDICT: LOOPBACK_PARTIAL —— 有数据但与发送不符（波特率/干扰/接线）")
    else:
        ff_frames = sum(1 for i in range(len(buf) - 3) if buf[i] == 0xFF)
        print(f"FF 帧头候选 {ff_frames} 个（声纳帧以 FF 开头，出水时为 FF FB xx cs）")
        print("VERDICT: RX_ACTIVE —— 有数据上来")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
