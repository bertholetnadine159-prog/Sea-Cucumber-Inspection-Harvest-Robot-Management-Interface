#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gpio cdev 深度诊断：芯片信息 + v1/v2 ABI 请求对比。"""

import fcntl
import os
import struct

# CHIPINFO: _IOR(0xB4, 0x06, struct gpiochip_info{name[32],label[32],lines u32}) = 68B
CHIPINFO = (2 << 30) | (68 << 16) | (0xB4 << 8) | 0x06

print("== CHIPINFO 各芯片 ==")
chips = {}
for n in range(6):
    fd = os.open(f"/dev/gpiochip{n}", os.O_RDONLY)
    buf = bytearray(68)
    try:
        fcntl.ioctl(fd, CHIPINFO, buf, True)
        name = buf[0:32].rstrip(b"\x00").decode(errors="replace")
        label = buf[32:64].rstrip(b"\x00").decode(errors="replace")
        lines = struct.unpack_from("I", buf, 64)[0]
        chips[n] = (name, lines)
        print(f"gpiochip{n}: name={name} lines={lines}")
    except OSError as e:
        print(f"gpiochip{n}: errno={e.errno}")
    os.close(fd)

print("== v1/v2 请求对比（chip4 line0/1） ==")
if 4 not in chips:
    print("chip4 不存在")
else:
    name, lines = chips[4]
    print(f"chip4 = {name}, lines={lines}")
    chip_fd = os.open("/dev/gpiochip4", os.O_RDONLY)

    # v1 event：line0 BOTH
    for req in (0x8030B40E, 0xC030B40E):
        buf = bytearray(struct.pack("III32si", 0, 1, 3, b"t".ljust(32, b"\x00"), 0))
        try:
            fcntl.ioctl(chip_fd, req, buf, True)
            print(f"v1 event 0x{req:08X}: OK")
        except OSError as e:
            print(f"v1 event 0x{req:08X}: errno={e.errno}")

    # v1 handle：单线 line0 输入
    for req in (0x816CB403, 0xC16CB403):
        buf = bytearray(struct.pack("II64s32sIi", 0, 1, bytes(64), b"t".ljust(32, b"\x00"), 1, 0))
        try:
            fcntl.ioctl(chip_fd, req, buf, True)
            print(f"v1 handle 0x{req:08X}: OK")
        except OSError as e:
            print(f"v1 handle 0x{req:08X}: errno={e.errno}")

    # v2 line request：lines 0+1 输出+双边沿
    # struct gpio_v2_line_request: line_offsets[2],num_lines,config,consumer[32],
    #                              event_buffer_size,padding[5],fd  -> 76B
    # flags: OUTPUT=BIT2(4), EDGE_RISING=BIT3(8), EDGE_FALLING=BIT4(16) -> 28
    v2 = 76
    req_v2 = (2 << 30) | (v2 << 16) | (0xB4 << 8) | 0x05
    buf = bytearray(struct.pack(
        "2I I I 32s I 5I i",
        0, 1,          # line_offsets
        2,             # num_lines
        4 | 8 | 16,    # OUTPUT|RISING|FALLING
        b"pwm".ljust(32, b"\x00"),
        16,            # event_buffer_size
        0, 0, 0, 0, 0,  # padding[5]
        0,             # fd
    ))
    try:
        fcntl.ioctl(chip_fd, req_v2, buf, True)
        fd = struct.unpack_from("i", buf, 72)[0]
        print(f"v2 line request 0x{req_v2:08X}: OK fd={fd}")
    except OSError as e:
        print(f"v2 line request 0x{req_v2:08X}: errno={e.errno}")
    os.close(chip_fd)
