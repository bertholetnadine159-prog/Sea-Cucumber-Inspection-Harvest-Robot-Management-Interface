#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""[RDK X5 side] 核心逻辑单元测试（PC 上无需硬件即可运行）。

运行：cd rdkx5 && python -m unittest discover -s tests -v
"""

import time
import unittest

from sensors import SensorHub, Ultrasonic
from pixhawk_link import PixhawkLink
from vision import VideoPipeline


class UltrasonicProtocolTest(unittest.TestCase):
    def test_valid_ff_frame(self) -> None:
        distance_mm = 352
        data_h = distance_mm >> 8
        data_l = distance_mm & 0xFF
        checksum = Ultrasonic.checksum(data_h, data_l)
        frame = bytes([0xFF, data_h, data_l, checksum])
        distance, message = Ultrasonic.parse_ff_uart(frame)
        self.assertAlmostEqual(distance, 0.352, places=3)
        self.assertEqual(message, "ok")

    def test_bad_checksum_rejected(self) -> None:
        frame = bytes([0xFF, 0x01, 0x60, 0x00])
        distance, _ = Ultrasonic.parse_ff_uart(frame)
        self.assertIsNone(distance)

    def test_out_of_water_value(self) -> None:
        frame = bytes([0xFF, 0xFF, 0xFB, Ultrasonic.checksum(0xFF, 0xFB)])
        distance, message = Ultrasonic.parse_ff_uart(frame)
        self.assertIsNone(distance)
        self.assertIn("out of water", message)


class SensorHubSimulationTest(unittest.TestCase):
    def test_all_configured_sensors_read_ok(self) -> None:
        config = {
            "veml7700_front": {"enabled": True, "bus": 5, "address": 0x10},
            "ms5837": {"enabled": True, "bus": 1, "address": 0x76},
            "ds18b20_1": {"enabled": True},
            "ultrasonic_front": {"enabled": True, "port": "/dev/ttyUSB0"},
        }
        hub = SensorHub(config, simulation=True)
        hub.open_all()
        readings = hub.read_all()
        hub.close_all()
        self.assertTrue(readings["veml7700_front_light"]["ok"])
        self.assertTrue(readings["ms5837_depth"]["ok"])
        self.assertTrue(readings["ds18b20_water_1"]["ok"])
        self.assertTrue(readings["ultrasonic_front_suction_mouth"]["ok"])
        self.assertIn("depth_m", readings["ms5837_depth"]["values"])


class PixhawkDeadmanTest(unittest.TestCase):
    def test_stale_axes_neutralize(self) -> None:
        pixhawk = PixhawkLink(
            {"control_mode": "manual_control", "deadman_ms": 20},
            simulation=True,
        )
        pixhawk.start()
        try:
            pixhawk.set_axes({"surge": 0.8, "sway": -0.3})
            self.assertEqual(pixhawk._effective_axes()["surge"], 0.8)
            time.sleep(0.08)
            effective = pixhawk._effective_axes()
            self.assertEqual(effective["surge"], 0.0)
            self.assertEqual(effective["sway"], 0.0)
        finally:
            pixhawk.close()

    def test_emergency_stop_neutralizes(self) -> None:
        pixhawk = PixhawkLink(
            {"control_mode": "manual_control", "deadman_ms": 1000},
            simulation=True,
        )
        pixhawk.start()
        try:
            pixhawk.set_axes({"heave": 1.0})
            pixhawk.emergency_stop(disarm=False)
            self.assertEqual(pixhawk._effective_axes()["heave"], 0.0)
        finally:
            pixhawk.close()


class VideoPipelineSimulationTest(unittest.TestCase):
    def test_simulated_pipeline_produces_jpeg(self) -> None:
        from pathlib import Path

        config = {
            "source": "simulation",
            "width": 640,
            "height": 360,
            "fps": 30,
            "jpeg_quality": 80,
            "enabled": False,  # 仿真不加载 BPU 模型
        }
        pipeline = VideoPipeline(config, Path("."), simulation=True)
        pipeline.start()
        try:
            deadline = time.time() + 3
            frame = None
            while time.time() < deadline:
                frame = pipeline.latest()
                if frame is not None and frame.jpeg:
                    break
                time.sleep(0.05)
            self.assertIsNotNone(frame)
            self.assertTrue(frame.jpeg.startswith(b"\xff\xd8"))  # JPEG SOI
            self.assertEqual(frame.width, 640)
            self.assertEqual(frame.height, 360)
        finally:
            pipeline.stop()


class GatewayResilienceTest(unittest.TestCase):
    def test_pixhawk_start_without_hardware_does_not_raise(self) -> None:
        pixhawk = PixhawkLink(
            {
                "enabled": True,
                "connection": "/dev/ttyACM99",
                "baud": 115200,
                "heartbeat_timeout_s": 1.0,
                "control_mode": "manual_control",
            },
            simulation=False,
        )
        try:
            pixhawk.start()
            self.assertFalse(pixhawk.snapshot().connected)
        finally:
            pixhawk.close()

    def test_video_pipeline_with_missing_model_streams_raw_frames(self) -> None:
        from pathlib import Path

        config = {
            "source": "simulation",
            "width": 320,
            "height": 240,
            "fps": 30,
            "jpeg_quality": 80,
            "enabled": True,
            "model_path": "./does_not_exist.bin",
            "yolo_script": "./does_not_exist.py",
        }
        pipeline = VideoPipeline(config, Path("."), simulation=False)
        self.assertIsNone(pipeline.segmenter)
        pipeline.start()
        try:
            deadline = time.time() + 3
            frame = None
            while time.time() < deadline:
                frame = pipeline.latest()
                if frame is not None:
                    break
                time.sleep(0.05)
            self.assertIsNotNone(frame)
            self.assertTrue(frame.jpeg.startswith(b"\xff\xd8"))
        finally:
            pipeline.stop()


if __name__ == "__main__":
    unittest.main()
