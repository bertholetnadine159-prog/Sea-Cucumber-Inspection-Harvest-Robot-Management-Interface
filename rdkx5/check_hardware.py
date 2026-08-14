#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# [RDK X5 side] 实机硬件自检
# 拿到板卡后按顺序验证：网络 -> 串口/I2C 设备 -> Python 依赖 ->
# 传感器读数 -> Pixhawk MAVLink -> BPU 模型推理 -> WebSocket 端口。
# 用法：
#   python3 check_hardware.py --config config.yaml
#   python3 check_hardware.py --config config.yaml --simulate   # 无硬件自检
# ============================================================================
from __future__ import annotations

import argparse
import asyncio
import importlib.util
import json
import socket
import sys
import time
from pathlib import Path
from typing import Any


RESULTS: list[tuple[str, bool, str]] = []


def report(name: str, ok: bool, detail: str = "") -> None:
    RESULTS.append((name, ok, detail))
    mark = "PASS" if ok else "FAIL"
    print(f"[{mark}] {name}" + (f" - {detail}" if detail else ""))


def port_accepts(port: int, timeout: float = 2.0) -> bool:
    """端口是否已经有服务在监听（用于判断网关是否正在运行）。"""
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=timeout):
            return True
    except OSError:
        return False


async def _query_gateway_telemetry(port: int, timeout: float) -> dict[str, Any] | None:
    try:
        import websockets
    except Exception:  # noqa: BLE001
        return None
    async with websockets.connect(f"ws://127.0.0.1:{port}", open_timeout=timeout) as ws:
        deadline = asyncio.get_running_loop().time() + timeout
        while asyncio.get_running_loop().time() < deadline:
            remaining = deadline - asyncio.get_running_loop().time()
            raw = await asyncio.wait_for(ws.recv(), remaining)
            message = json.loads(raw)
            if message.get("type") == "telemetry":
                return message
    return None


def query_gateway_telemetry(port: int, timeout: float = 6.0) -> dict[str, Any] | None:
    """连到正在运行的网关，取第一帧 telemetry（含 sensors 与 pixhawk 快照）。"""
    try:
        return asyncio.run(_query_gateway_telemetry(port, timeout))
    except Exception:  # noqa: BLE001
        return None


def check_network() -> None:
    try:
        hostname = socket.gethostname()
        ip = socket.gethostbyname(hostname)
        detail = f"hostname={hostname} ip={ip}"
        # 板卡有线网口默认 192.168.127.10，但不强制，仅展示
        report("network", True, detail)
    except Exception as exc:  # noqa: BLE001
        report("network", False, str(exc))


def check_devices(simulate: bool) -> None:
    if simulate:
        report("devices", True, "simulation mode")
        return
    checks = {
        "pixhawk_serial": "/dev/ttyACM*",
        "ultrasonic_usb": "/dev/ttyUSB*",
        "i2c_bus": "/dev/i2c-*",
        "usb_video": "/dev/video*",
    }
    for name, pattern in checks.items():
        matches = list(Path("/dev").glob(pattern.lstrip("/dev/").lstrip("/")))
        report(name, bool(matches), ", ".join(str(p) for p in matches) if matches else f"no {pattern}")


def check_dependencies() -> None:
    modules = ["yaml", "numpy", "cv2", "serial", "smbus2", "pymavlink", "websockets"]
    missing: list[str] = []
    for module in modules:
        try:
            __import__(module)
        except Exception:  # noqa: BLE001
            missing.append(module)
    hobot_ok = importlib.util.find_spec("hobot_dnn") is not None
    # RDK X5 上 MIPI 摄像头模块可能是 srcampy，也可能是 hobot_vio.libsrcampy
    camera_ok = importlib.util.find_spec("srcampy") is not None or importlib.util.find_spec("hobot_vio") is not None
    if not hobot_ok:
        missing.append("hobot_dnn")
    if not camera_ok:
        missing.append("srcampy/hobot_vio(可选，MIPI摄像头)")
    report("dependencies", not missing, "missing: " + ", ".join(missing) if missing else "all present")


def check_sensors(config: dict[str, Any], simulate: bool) -> None:
    from sensors import SensorHub

    hub = SensorHub(config.get("sensors", {}), simulation=simulate)
    try:
        hub.open_all()
        readings = hub.read_all()
        ok_count = sum(1 for reading in readings.values() if reading.get("ok"))
        detail_parts = []
        for name, reading in readings.items():
            if reading.get("ok"):
                values = reading.get("values", {})
                detail_parts.append(f"{name}={ {k: round(v, 3) if isinstance(v, float) else v for k, v in values.items()} }")
            else:
                detail_parts.append(f"{name}=ERR({reading.get('message', '')[:40]})")
        report("sensors", ok_count == len(readings), "; ".join(detail_parts) or "no sensors configured")
    except Exception as exc:  # noqa: BLE001
        report("sensors", False, str(exc))
    finally:
        hub.close_all()


def check_pixhawk(config: dict[str, Any], simulate: bool) -> None:
    from pixhawk_link import PixhawkLink, SimulatedPixhawk

    if simulate:
        pixhawk = SimulatedPixhawk()
        pixhawk.start()
        telemetry = pixhawk.snapshot()
        report("pixhawk", telemetry.connected, json.dumps(telemetry.to_dict(), ensure_ascii=False))
        pixhawk.close()
        return

    # 网关正在运行时已独占 /dev/ttyACM0；再直接打开串口会争抢字节流。
    # 此时改为通过网关的 WebSocket 遥测验证 Pixhawk 状态。
    port = int(config.get("server", {}).get("port", 8080))
    if port_accepts(port):
        payload = query_gateway_telemetry(port)
        if payload is None:
            report("pixhawk", False, f"gateway serving on {port} but telemetry query failed")
            return
        pixhawk_state = payload.get("pixhawk", {})
        report(
            "pixhawk",
            bool(pixhawk_state.get("connected")),
            "verified via running gateway: " + json.dumps(pixhawk_state, ensure_ascii=False),
        )
        return

    pixhawk = PixhawkLink(config.get("pixhawk", {}), simulation=False)
    try:
        pixhawk.start()
        deadline = time.time() + float(config.get("pixhawk", {}).get("heartbeat_timeout_s", 3.0)) + 3.0
        while time.time() < deadline:
            telemetry = pixhawk.snapshot()
            if telemetry.connected:
                break
            time.sleep(0.2)
        telemetry = pixhawk.snapshot()
        report(
            "pixhawk",
            telemetry.connected,
            json.dumps(telemetry.to_dict(), ensure_ascii=False),
        )
    except Exception as exc:  # noqa: BLE001
        report("pixhawk", False, str(exc))
    finally:
        pixhawk.close()


def check_vision(config: dict[str, Any], simulate: bool, base_dir: Path) -> None:
    if simulate:
        report("vision", True, "simulation mode")
        return
    import numpy as np

    try:
        from vision import RDKSegmenter

        segmenter = RDKSegmenter(config.get("vision", {}), base_dir)
        frame = np.zeros((640, 640, 3), dtype=np.uint8)
        t0 = time.monotonic()
        detections = segmenter.predict(frame)
        elapsed_ms = (time.monotonic() - t0) * 1000.0
        report("vision_bpu", True, f"model loaded, dummy inference {elapsed_ms:.1f} ms, detections={len(detections)}")
    except Exception as exc:  # noqa: BLE001
        report("vision_bpu", False, str(exc))


def check_server_port(config: dict[str, Any]) -> None:
    port = int(config.get("server", {}).get("port", 8080))
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("0.0.0.0", port))
        free = True
    except OSError:
        free = False
    finally:
        sock.close()
    if free:
        report("server_port", True, f"port {port} free (gateway not running)")
    elif port_accepts(port):
        report("server_port", True, f"port {port} already serving (gateway running)")
    else:
        report("server_port", False, f"port {port} in use but not accepting connections")


def main() -> None:
    parser = argparse.ArgumentParser(description="[RDK X5 side] hardware self check")
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument("--simulate", action="store_true")
    args = parser.parse_args()

    import yaml

    with open(args.config, "r", encoding="utf-8") as handle:
        config = yaml.safe_load(handle) or {}
    base_dir = Path(args.config).resolve().parent

    print("=== SeaUI RDK X5 硬件自检 ===")
    check_network()
    check_devices(args.simulate)
    check_dependencies()
    check_sensors(config, args.simulate)
    check_pixhawk(config, args.simulate)
    check_vision(config, args.simulate, base_dir)
    check_server_port(config)

    failed = [name for name, ok, _ in RESULTS if not ok]
    print("=" * 40)
    print(f"total={len(RESULTS)} passed={len(RESULTS) - len(failed)} failed={len(failed)}")
    if failed:
        print("FAILED:", ", ".join(failed))
        sys.exit(1)
    print("all checks passed")


if __name__ == "__main__":
    main()
