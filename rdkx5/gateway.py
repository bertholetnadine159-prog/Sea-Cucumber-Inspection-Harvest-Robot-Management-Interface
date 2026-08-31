#!/usr/bin/env python3
# ============================================================================
# [RDK X5 side] SeaUI 网关主程序
#
# 在 D-Robotics RDK X5 上运行（不要在 PC 上运行）：
#   1. 采集 MIPI/USB 摄像头
#   2. 用 BPU 跑 YOLO11 海参分割（hobot_dnn + YOLO11_LBL.bin）
#   3. 把标注后 JPEG 视频流 + 传感器 + Pixhawk 状态经 WebSocket 推给 PC
#   4. 接收 PC 控制命令，经 MAVLink 控制 Pixhawk 2.4.8
#
# 启动：python3 gateway.py --config config.yaml
# ============================================================================
from __future__ import annotations

import argparse
import asyncio
import logging
import signal
from pathlib import Path
from typing import Any

import yaml

from pixhawk_link import PixhawkLink, SimulatedPixhawk
from sensors import SensorHub
from stream_server import CommandHandler, StreamServer
from vision import VideoPipeline


LOGGER = logging.getLogger("rdkx5.gateway")


def load_config(path: str) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def build_components(config: dict[str, Any], base_dir: Path):
    legacy_video = dict(config.get("video", {}))
    cameras_cfg = config.get("cameras", {}) or {}
    simulation = bool(config.get("sensors", {}).get("simulation", False)) or bool(
        str(legacy_video.get("source", "")).lower() == "simulation"
        or any(
            isinstance(cfg, dict) and str(cfg.get("source", "")).lower() == "simulation"
            for cfg in cameras_cfg.values()
        )
    )

    pixhawk_config = dict(config.get("pixhawk", {}))
    pixhawk_config["deadman_ms"] = config.get("safety", {}).get("deadman_ms", 1000)
    pixhawk = SimulatedPixhawk() if simulation else PixhawkLink(pixhawk_config, simulation=False)
    pixhawk.start()

    sensor_hub = SensorHub(config.get("sensors", {}), simulation=simulation)
    sensor_hub.open_all()
    sensor_hub.read_all()

    # 摄像头与视觉参数合并后交给 VideoPipeline（支持双摄像头 + 活动摄像头切换）
    video_config = {
        **legacy_video,
        **config.get("vision", {}),
        "cameras": cameras_cfg,
        "active_camera": config.get("active_camera", legacy_video.get("active_camera", "camera_1")),
        "jpeg_quality": config.get("jpeg_quality", legacy_video.get("jpeg_quality", 78)),
    }
    video = VideoPipeline(video_config, base_dir, simulation=simulation)
    video.start()

    handler = CommandHandler(
        pixhawk,
        video,
        suction_channels=list(pixhawk_config.get("suction_channels", [9, 10])),
        servo_channel=int(pixhawk_config.get("servo_channel", 11)),
        light_channels=list(pixhawk_config.get("light_channels", [])),
        safety=config.get("safety", {}),
    )
    server_config = config.get("server", {})
    server = StreamServer(
        str(server_config.get("host", "0.0.0.0")),
        int(server_config.get("port", 8080)),
        video,
        sensor_hub,
        pixhawk,
        handler,
        telemetry_hz=int(config.get("telemetry", {}).get("hz", 5)),
    )
    return pixhawk, sensor_hub, video, server


def main() -> None:
    parser = argparse.ArgumentParser(description="SeaUI RDK X5 gateway")
    parser.add_argument("--config", default="config.yaml", help="path to config.yaml")
    parser.add_argument("--simulate", action="store_true", help="run without hardware")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="[%(asctime)s] [%(name)s] %(levelname)s %(message)s")
    base_dir = Path(args.config).resolve().parent
    config = load_config(args.config)
    if args.simulate:
        config.setdefault("cameras", {})["camera_1"] = {"source": "simulation"}
        config.setdefault("sensors", {})["simulation"] = True
        config.setdefault("pixhawk", {})["enabled"] = False

    pixhawk, sensor_hub, video, server = build_components(config, base_dir)

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    loop.run_until_complete(server.start())
    LOGGER.info("[RDK X5] gateway running. Press Ctrl+C to stop.")

    def shutdown(signum, frame):  # noqa: ARG001
        LOGGER.info("[RDK X5] shutting down...")
        loop.call_soon_threadsafe(loop.stop)

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    try:
        loop.run_forever()
    finally:
        loop.run_until_complete(server.stop())
        video.stop()
        sensor_hub.close_all()
        pixhawk.close()
        loop.close()
        LOGGER.info("[RDK X5] gateway stopped")


if __name__ == "__main__":
    main()
