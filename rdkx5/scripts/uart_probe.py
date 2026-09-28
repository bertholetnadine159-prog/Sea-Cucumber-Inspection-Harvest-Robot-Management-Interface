#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""串口收发探针：判定"串口本体好/坏"与"对端设备有无数据"。

在 RDK X5 板卡上运行：
    python3 rdkx5/scripts/uart_probe.py --port /dev/ttyS1              # 只收 3 秒
    python3 rdkx5/scripts/uart_probe.py --port /dev/ttyS7 --loopback   # 回环自测
    python3 rdkx5/scripts/uart_probe.py --port /dev/ttyS7 --trigger    # ctrl 型声纳触发

三种模式：
  默认      : 被动收听 N 秒（适合 auto 自动上报型声纳）
  --loopback: 短接 TXD/RXD 后自发自收，验证串口本体
  --trigger : 先把 TX 拉低约 4ms（满足 ff_uart_ctrl 型声纳"500µs 低脉冲触发"
              的要求），再收帧。DYP 电应普 ff_uart_ctrl 模式专用。
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
    parser.add_argument("--trigger", action="store_true", help="ctrl 型声纳：低脉冲触发一帧再收")
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

    label = "回环收发" if args.loopback else ("触发后收帧" if args.trigger else "被动收听")
    print(f"{args.port} @ {args.baud} 已打开（{label}），收听 {args.seconds}s ...")

    if args.loopback:
        ser.write(TEST_PATTERN)
        ser.flush()
        print(f"已发送测试码 {TEST_PATTERN.hex(' ')}")

    if args.trigger:
        # ff_uart_ctrl 协议（例程逐拍复刻）：主控把传感器 RX 拉低 500µs
        # 触发一次测量输出，随后线路回到高电平，模块回 4 字节帧；
        # 例程每 500ms 重复一次触发。send_break 产生真正的连续低电平
        # （无 stop 位毛刺），比 0x00 字节拼脉冲更贴近例程。
        print("按例程序节奏触发：每 500ms 发一次 500µs 连续低电平，随后收帧 ...")
        import time as _t
        trigger_until = _t.time() + max(args.seconds, 2.0)
        collected = b""
        while _t.time() < trigger_until:
            try:
                ser.send_break(duration=0.0005)  # 500µs 连续低电平
            except Exception:
                ser.write(b"\x00\x00")  # 内核不支持 break 时退化为短脉冲
            ser.flush()
            _t.sleep(0.06)  # 触发后等测量完成
            collected += ser.read(64)
            # 例程每 500ms 一轮；把剩余窗口交给下一轮触发
            _t.sleep(0.44)
        buf = collected
    else:
        buf = b""
        deadline = time.time() + args.seconds
        while time.time() < deadline:
            buf += ser.read(256)
    ser.close()

    if not buf:
        print("VERDICT: RX_SILENT —— 未收到任何字节")
        if args.trigger:
            print("  触发后仍无帧：声纳不在该口 / 未供电 / 声纳为 auto 型（改用被动模式再试）")
        elif args.loopback:
            print("  回环失败：该串口 TX→RX 不通（引脚复用/串口本体问题）")
        else:
            print("  对端（声纳）无数据上来：查声纳供电、TXD/RXD 是否接反、共地")
        return 1

    shown = buf.hex(" ") if args.hex else buf.decode(errors="replace")
    print(f"收到 {len(buf)} 字节: {shown[:200]}")
    ff_frames = sum(1 for i in range(len(buf) - 3) if buf[i] == 0xFF)
    if args.loopback:
        if TEST_PATTERN in buf:
            print("VERDICT: LOOPBACK_OK —— 串口收发硬件正常，问题在对端接线/供电")
        else:
            print("VERDICT: LOOPBACK_PARTIAL —— 有数据但与发送不符（波特率/干扰/接线）")
    elif args.trigger:
        if ff_frames:
            print("VERDICT: TRIGGER_OK —— 触发后收到 FF 帧（声纳存活，为 ctrl 触发型）")
        else:
            print("VERDICT: TRIGGER_SILENT —— 触发后无 FF 帧")
    else:
        print(f"FF 帧头候选 {ff_frames} 个（出水探头也会报 FF FB xx cs 帧）")
        print("VERDICT: RX_ACTIVE —— 有数据上来")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
