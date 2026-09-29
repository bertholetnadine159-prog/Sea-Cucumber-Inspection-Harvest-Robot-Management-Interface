#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""[RDK X5 side] 泵输出 20% 硬钳位单元测试。

用户硬规则（2026-09-29）：台架测试所有电机输出不得超过 20%。
钳位做在网关 suction 命令这一最后一环：无论 UI/后端发来多大百分比，
实际下发的 PWM 都不得越过 config 的 suction_max_power_percent。

运行：cd rdkx5 && python -m unittest discover -s tests -v
"""

import asyncio
import unittest

from stream_server import CommandHandler


class FakePixhawk:
    """只记录 set_pwm 调用的最小桩。"""

    def __init__(self) -> None:
        self.pwms: dict[int, int] = {}

    def set_pwm(self, channel: int, pwm: int) -> None:
        self.pwms[channel] = pwm


def make_handler(max_percent: float) -> tuple[CommandHandler, FakePixhawk]:
    pixhawk = FakePixhawk()
    handler = CommandHandler(
        pixhawk,
        video=None,
        suction_channels=[9, 10],
        servo_channel=11,
        light_channels=[],
        safety={},
        suction_max_power_percent=max_percent,
    )
    return handler, pixhawk


class SuctionCapTest(unittest.TestCase):
    """suction 命令必须被 config 上限钳住；泵通道随 config 走。"""

    def suction(self, handler: CommandHandler, percent) -> dict:
        message = {
            "type": "command",
            "command": "suction",
            "params": {"power_percent": percent},
        }
        return asyncio.run(handler.handle(message))

    def test_full_power_request_clamped_to_20_percent(self) -> None:
        handler, pixhawk = make_handler(20.0)
        ack = self.suction(handler, 100)
        self.assertTrue(ack["success"])
        self.assertTrue(ack["capped"])
        self.assertEqual(ack["percent"], 20)
        # 单向泵电调：1000=停，20% = 1000 + 0.2*1000 = 1200us
        self.assertEqual(ack["pwm"], 1200)
        self.assertEqual(pixhawk.pwms, {9: 1200, 10: 1200})

    def test_grab_style_100_percent_never_exceeds_cap(self) -> None:
        handler, pixhawk = make_handler(20.0)
        ack = self.suction(handler, 100)
        self.assertLessEqual(ack["pwm"], 1200)

    def test_request_below_cap_passes_through(self) -> None:
        handler, pixhawk = make_handler(20.0)
        ack = self.suction(handler, 10)
        self.assertFalse(ack["capped"])
        self.assertEqual(ack["pwm"], 1100)
        self.assertEqual(pixhawk.pwms, {9: 1100, 10: 1100})

    def test_zero_stops_pump(self) -> None:
        handler, pixhawk = make_handler(20.0)
        ack = self.suction(handler, 0)
        self.assertEqual(ack["pwm"], 1000)
        self.assertEqual(pixhawk.pwms, {9: 1000, 10: 1000})

    def test_cap_is_clamped_into_0_100(self) -> None:
        # 配置越界时钳位上限自身也要收敛到合法区间
        handler, pixhawk = make_handler(150.0)
        ack = self.suction(handler, 100)
        self.assertFalse(ack["capped"])
        self.assertEqual(ack["pwm"], 2000)
        handler2, _ = make_handler(-5.0)
        ack2 = self.suction(handler2, 50)
        self.assertEqual(ack2["pwm"], 1000)

    def test_default_cap_is_20_percent(self) -> None:
        pixhawk = FakePixhawk()
        handler = CommandHandler(
            pixhawk, video=None, suction_channels=[9, 10],
            servo_channel=11, light_channels=[], safety={},
        )
        self.assertEqual(handler.suction_max_power_percent, 20.0)


if __name__ == "__main__":
    unittest.main()
