#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""板上 USB 串口设备身份与原始字节流探针。

在 RDK X5 板上运行（建议先停掉网关以独占串口）：
    python3 /tmp/pixhawk_raw_probe.py --seconds 10

三步（只读诊断 + 无线电安全的单条参数读，绝无电机指令）：
  1. 打印 USB 总线上全部设备的 VID/PID/厂商/产品字符串 + udevadm 身份
  2. 用 pyserial 裸抓 N 秒原始字节（不做 MAVLink 假设），逐块 hexdump
  3. 若有原始字节，再用 pymavlink 解析心跳/参数（验证 srcSystem 与参数值）
"""

from __future__ import annotations

import argparse
import glob
import subprocess
import time


def print_identity(port: str) -> None:
    print("===== USB device identity =====")
    attrs = ("idVendor", "idProduct", "manufacturer", "product", "serial")
    for dev_path in sorted(glob.glob("/sys/bus/usb/devices/*/idVendor")):
        dev = dev_path.rsplit("/", 1)[-2]
        parts = []
        for attr in attrs:
            try:
                with open(f"/sys/bus/usb/devices/{dev}/{attr}") as fh:
                    value = fh.read().strip()
            except OSError:
                value = "-"
            if value and value != "-":
                parts.append(f"{attr}={value}")
        if parts:
            print(f"  {dev}: " + " ".join(parts))
    try:
        out = subprocess.run(
            ["udevadm", "info", "-q", "property", "-n", port],
            capture_output=True, text=True, timeout=10,
        ).stdout.strip()
        interesting = [
            line for line in out.splitlines()
            if any(k in line for k in ("ID_VENDOR", "ID_MODEL", "ID_SERIAL", "ID_USB"))
        ]
        print(f"===== udevadm {port} =====")
        for line in interesting[:20]:
            print(f"  {line}")
    except Exception as exc:  # noqa: BLE001
        print(f"  udevadm failed: {exc}")


def raw_capture(port: str, baud: int, seconds: float) -> int:
    import serial

    print(f"===== raw capture {seconds}s on {port} @ {baud} =====")
    ser = serial.Serial(port, baud, timeout=0.5)
    start = time.monotonic()
    total = 0
    chunks = 0
    while time.monotonic() - start < seconds:
        data = ser.read(256)
        if data:
            total += len(data)
            chunks += 1
            if chunks <= 12:
                print(f"  t={time.monotonic() - start:5.1f}s +{len(data)}B: {data[:48].hex(' ')}")
    ser.close()
    print(f"[probe] raw total={total} bytes in {chunks} chunks")
    return total


def mavlink_check(port: str, baud: int, seconds: float, probe_param: str) -> int:
    from pymavlink import mavutil

    print(f"===== MAVLink parse {seconds}s on {port} =====")
    master = mavutil.mavlink_connection(port, baud=baud)
    hb = master.wait_heartbeat(timeout=5.0)
    if hb is None:
        print("[probe] RESULT: NO_HEARTBEAT (raw bytes exist but no valid MAVLink frames)")
        master.close()
        return 1
    print(
        f"[probe] heartbeat srcSystem={master.target_system} "
        f"srcComponent={master.target_component}"
    )

    start = time.monotonic()
    next_gcs_hb = start
    param_sent = False
    per_second: list[tuple[int, str]] = []
    cur_sec, cur_count, cur_types = -1, 0, {}

    while time.monotonic() - start < seconds:
        now = time.monotonic()
        elapsed = now - start
        sec = int(elapsed)
        if sec != cur_sec:
            if cur_sec >= 0:
                per_second.append((cur_sec, cur_count, cur_types))
            cur_sec, cur_count, cur_types = sec, 0, {}
        if now >= next_gcs_hb:
            master.mav.heartbeat_send(
                mavutil.mavlink.MAV_TYPE_GCS,
                mavutil.mavlink.MAV_AUTOPILOT_INVALID, 0, 0, 0,
            )
            next_gcs_hb = now + 1.0
        if not param_sent and elapsed >= 4.0:
            master.mav.param_request_read_send(
                master.target_system, master.target_component,
                probe_param.encode(), -1,
            )
            param_sent = True
            print(f"[probe] PARAM_REQUEST_READ({probe_param}) at t={elapsed:.1f}")
        msg = master.recv_match(blocking=True, timeout=0.2)
        if msg is not None:
            mtype = msg.get_type()
            cur_count += 1
            cur_types[mtype] = cur_types.get(mtype, 0) + 1
            if mtype == "PARAM_VALUE":
                print(f"[probe] PARAM_VALUE {msg.param_id} = {msg.param_value}")
    per_second.append((cur_sec, cur_count, cur_types))
    master.close()

    print("===== per-second message counts =====")
    for sec, count, types in per_second:
        detail = " ".join(f"{k}x{v}" for k, v in types.items())
        print(f"  t={sec:3d}s  count={count:4d}  {detail}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="USB 串口身份与原始流探针")
    parser.add_argument("--port", default="/dev/ttyACM0")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--seconds", type=float, default=10.0)
    parser.add_argument("--probe-param", default="SERVO5_FUNCTION")
    args = parser.parse_args()

    print_identity(args.port)
    total = raw_capture(args.port, args.baud, args.seconds)
    if total == 0:
        print("[probe] VERDICT: DEVICE_SILENT — 设备完全不出数据（可能不是 Pixhawk，或已挂死）")
        return 2
    mavlink_check(args.port, args.baud, args.seconds, args.probe_param)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
