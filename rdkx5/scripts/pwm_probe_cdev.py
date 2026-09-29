#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""PWM 型声纳距离读取探针（GPIO cdev 边沿时间戳版）。

协议（examples/pwm/pwm.ino 考证）：
  触发：传感器 RX 100µs 低脉冲；输出：TX 一个高电平脉宽 T，距离 S = T / 57.5 (cm)；
  无目标输出约 35ms 固定脉宽；触发周期须 >70ms。

实现：UART7_RX = /dev/gpiochip4 line 0（lsio_uart7_rx 球），
     UART7_TX = /dev/gpiochip4 line 1（lsio_uart7_tx 球）。
     用 GPIO 字符设备（cdev）做输出触发 + 双边沿事件时间戳（内核 CLOCK_REALTIME ns），
     脉宽 = 触发上升沿之后第一个下降沿的时间差。
注意：cdev 占用期间 UART7 功能被切换为 GPIO；结束后释放，如需恢复串口
     语义请重启网关或板卡。

用法：python3 rdkx5/scripts/pwm_probe_cdev.py --samples 8
"""

from __future__ import annotations

import argparse
import ctypes
import fcntl
import os
import selectors
import struct
import time

CHIP = "/dev/gpiochip4"
RX_LINE = 0   # lsio_uart7_rx 球 = 40-pin 13 脚（GPIO27/SOC379）：声纳 TX 输出接此，探针在此收边沿
TX_LINE = 1   # lsio_uart7_tx 球 = 40-pin 11 脚（GPIO17/SOC380）：探针触发输出接声纳 RX
# 脚号考证（docs/PINMAP.md §2）：官方表+出厂表+板卡 gpioinfo+板卡 dts 四环一致——
# 线0=RXD=13脚、线1=TXD=11脚；勿把 BCM 号 17/27 当 cdev 线号（那是置换关系不是恒等）。

GPIOHANDLE_REQUEST_OUTPUT = 2
GPIOEVENT_REQUEST_BOTH_EDGES = 3
EVENT_RISING = 1
EVENT_FALLING = 2

# struct gpiohandle_request: lineoffsets[64] + flags + default_values[64] + label[32] + lines + fd
GPIO_GET_LINEHANDLE_IOCTL = (2 << 30) | (364 << 16) | (0xB4 << 8) | 0x03
# struct gpiohandle_data: values[64]
GPIOHANDLE_SET_LINE_VALUES_IOCTL = (2 << 30) | (64 << 16) | (0xB4 << 8) | 0x09
# struct gpioevent_request: lineoffset + handleflags + eventflags + label[32] + fd
GPIO_GET_LINEEVENT_IOCTL = (2 << 30) | (48 << 16) | (0xB4 << 8) | 0x0E


def main() -> int:
    parser = argparse.ArgumentParser(description="PWM 型声纳距离读取（cdev 边沿时间戳）")
    parser.add_argument("--samples", type=int, default=8)
    parser.add_argument("--period-ms", type=int, default=500)
    args = parser.parse_args()

    chip_fd = os.open(CHIP, os.O_RDONLY)

    # ---- 事件句柄：RX 双边沿 ----
    ev_req = bytearray(struct.pack(
        "III32si",
        RX_LINE,
        1,  # GPIOHANDLE_REQUEST_INPUT
        GPIOEVENT_REQUEST_BOTH_EDGES,
        b"sonar-rx".ljust(32, b"\0"),
        0,
    ))
    fcntl.ioctl(chip_fd, GPIO_GET_LINEEVENT_IOCTL, ev_req, True)
    ev_fd = struct.unpack_from("i", ev_req, 44)[0]
    os.set_blocking(ev_fd, False)

    # ---- 输出句柄：TX，默认高电平（空闲） ----
    tx_req = bytearray(struct.pack(
        "64I I 64s 32s I i",
        *([TX_LINE] + [0] * 63),
        GPIOHANDLE_REQUEST_OUTPUT,
        bytes([1] + [0] * 63),  # 默认值：高
        b"sonar-tx".ljust(32, b"\0"),
        1,
        0,
    ))
    fcntl.ioctl(chip_fd, GPIO_GET_LINEHANDLE_IOCTL, tx_req, True)
    tx_fd = struct.unpack_from("i", tx_req, 360)[0]

    def tx_set(value: int) -> None:
        data = bytearray(struct.pack("64B", value, *([0] * 63)))
        fcntl.ioctl(tx_fd, GPIOHANDLE_SET_LINE_VALUES_IOCTL, data, True)

    sel = selectors.DefaultSelector()
    sel.register(ev_fd, selectors.EVENT_READ)
    drain = bytearray()
    while True:
        for key, _ in sel.select(0):
            drain += os.read(ev_fd, 256)
        if not drain:
            break

    print(f"PWM 声纳探针（cdev）：{CHIP} rx=line{RX_LINE} tx=line{TX_LINE}，{args.samples} 次采样，"
          f"周期 {args.period_ms}ms")
    readings = []
    try:
        for n in range(args.samples):
            sel.select(0)
            try:
                while True:
                    os.read(ev_fd, 256)  # 清残留边沿
            except BlockingIOError:
                pass

            tx_set(0)                      # 触发：TX 拉低 100µs
            time.sleep(0.0001)
            tx_set(1)                      # 上升沿 = 模组开始输出高脉宽
            t_high_ns = time.time_ns()

            width_ns = None
            deadline = t_high_ns / 1000.0 + 350  # ms 上限（35ms 无目标 + 余量）
            events_seen = []
            while time.time() < deadline:
                for key, _ in sel.select(0.05):
                    chunk = os.read(ev_fd, 256)
                    for off in range(0, len(chunk) // 16 * 16, 16):
                        ts_ns, eid = struct.unpack_from("<QI4x", chunk, off)
                        events_seen.append((ts_ns, eid))
                        if eid == EVENT_FALLING and ts_ns > t_high_ns and width_ns is None:
                            width_ns = ts_ns - t_high_ns
                if width_ns is not None:
                    break

            if width_ns is None:
                print(f"  [{n+1}/{args.samples}] 未捕获下降沿（事件数 {len(events_seen)}）")
                continue
            width_us = width_ns / 1000.0
            if width_us > 50000:
                note = "无目标（35ms 固定脉宽）"
            else:
                readings.append(width_us / 57.5)
                note = f"距离 ≈ {width_us / 57.5:.1f} cm"
            print(f"  [{n+1}/{args.samples}] 脉宽 ≈ {width_us:.0f} µs -> {note}")
            time.sleep((args.period_ms - 100) / 1000.0)
    finally:
        os.close(tx_fd)
        os.close(ev_fd)
        os.close(chip_fd)

    if readings:
        print(f"VERDICT: PWM_OK —— 有效读数 {len(readings)}/{args.samples}："
              f"min={min(readings):.1f}cm max={max(readings):.1f}cm avg={sum(readings)/len(readings):.1f}cm")
        return 0
    print("VERDICT: PWM_SILENT —— 未捕获 PWM 脉宽（模组/接线待查）")
    return 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
