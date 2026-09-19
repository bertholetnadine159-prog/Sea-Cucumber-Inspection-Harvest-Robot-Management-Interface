#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""[RDK X5 side] Pixhawk auto-arm / 链路重连重解锁单元测试。

不 import pymavlink、不访问真实串口：手工向 PixhawkLink 注入 fake
master/mavutil（不调用 start()），可在任意平台（含无 pymavlink 的
Windows/Python 3.14）独立运行。无真实 sleep、无线程时序依赖。

运行：cd rdkx5 && python -m unittest discover -s tests -v
"""

import unittest

from pixhawk_link import PixhawkLink

MAV_CMD_COMPONENT_ARM_DISARM = 400
MAV_CMD_DO_SET_SERVO = 183


class FakeMavCommands:
    """记录每次 command_long_send 的 (target_system, target_component,
    command, confirmation, params)；可选让首次 ARM 命令抛 RuntimeError
    （先记录后抛出，保证"失败尝试"也计数）。"""

    def __init__(self, fail_first_arm: bool = False) -> None:
        self.calls: list[tuple[int, int, int, int, tuple[int, ...]]] = []
        self._fail_first_arm = fail_first_arm

    def command_long_send(self, target_system, target_component, command,
                          confirmation, *params) -> None:
        self.calls.append(
            (target_system, target_component, command, confirmation, tuple(params)),
        )
        if command == MAV_CMD_COMPONENT_ARM_DISARM and self._fail_first_arm:
            self._fail_first_arm = False
            raise RuntimeError("simulated arm failure")


class FakeMaster:
    """模拟 pymavlink master：持有 mav，记录 close() 调用。"""

    def __init__(self, fail_first_arm: bool = False) -> None:
        self.mav = FakeMavCommands(fail_first_arm=fail_first_arm)
        self.target_system = 1
        self.target_component = 1
        self.closed = False

    def close(self) -> None:
        self.closed = True


class FakeMavutil:
    """模拟 pymavlink.mavutil 的最小命名空间，仅含测试用到的常量。"""

    class mavlink:  # noqa: N801 - 与 pymavlink 的属性名保持一致
        MAV_CMD_COMPONENT_ARM_DISARM = MAV_CMD_COMPONENT_ARM_DISARM
        MAV_CMD_DO_SET_SERVO = MAV_CMD_DO_SET_SERVO


class AutoArmTestBase(unittest.TestCase):
    def make_link(self, fail_first_arm: bool = False) -> tuple[PixhawkLink, FakeMaster]:
        link = PixhawkLink(
            {
                "control_mode": "manual_control",
                "suction_channels": [13, 14],
                "suction_neutral_pwm": 1000,
                "auto_arm": True,
            },
            simulation=False,
        )
        master = FakeMaster(fail_first_arm=fail_first_arm)
        link.master = master
        link.mavutil = FakeMavutil()
        return link, master

    @staticmethod
    def arm_commands(master: FakeMaster) -> list[tuple[int, int, int, int, tuple[int, ...]]]:
        return [c for c in master.mav.calls if c[2] == MAV_CMD_COMPONENT_ARM_DISARM]

    @staticmethod
    def servo_calls(master: FakeMaster) -> list[tuple[int, int]]:
        return [(c[4][0], c[4][1]) for c in master.mav.calls if c[2] == MAV_CMD_DO_SET_SERVO]


class LinkEstablishedAutoArmTest(AutoArmTestBase):
    def test_link_established_force_arm_and_neutral_pwm(self) -> None:
        link, master = self.make_link()
        link._on_link_established()
        arm_commands = self.arm_commands(master)
        self.assertEqual(len(arm_commands), 1)
        self.assertEqual(arm_commands[0][0], 1)  # target_system
        self.assertEqual(arm_commands[0][1], 1)  # target_component
        self.assertEqual(arm_commands[0][4][:2], (1, 21196))
        self.assertTrue(link._auto_arm_done)
        # initialize_escs 在 arm 前后各跑一轮：通道 5-16 各出现两次
        servos = self.servo_calls(master)
        channels = {ch for ch, _ in servos}
        self.assertEqual(channels, set(range(5, 17)))
        self.assertEqual(len(servos), 24)
        for channel, pwm in servos:
            if channel in (13, 14):
                self.assertEqual(pwm, 1000)
            else:
                self.assertEqual(pwm, 1500)


class DropLinkRearmTest(AutoArmTestBase):
    def test_drop_link_resets_and_relink_rearms(self) -> None:
        link, master = self.make_link()
        link._on_link_established()
        self.assertTrue(link._auto_arm_done)
        link._drop_link()
        self.assertFalse(link._auto_arm_done)
        self.assertIsNone(link.master)
        self.assertTrue(master.closed)
        # 新链路建立后重新 auto-arm：ARM 命令总数增加 1 条，参数不变
        new_master = FakeMaster()
        link.master = new_master
        link.mavutil = FakeMavutil()
        link._on_link_established()
        arm_commands = self.arm_commands(new_master)
        self.assertEqual(len(arm_commands), 1)
        self.assertEqual(arm_commands[0][4][:2], (1, 21196))
        self.assertTrue(link._auto_arm_done)


class FailedArmRetryTest(AutoArmTestBase):
    def test_failed_arm_retried_without_disconnect(self) -> None:
        link, master = self.make_link(fail_first_arm=True)
        link._on_link_established()
        self.assertFalse(link._auto_arm_done)
        self.assertEqual(len(self.arm_commands(master)), 1)
        # 限频窗口内立即重试：被拦截，不再发命令
        link._maybe_retry_auto_arm()
        self.assertEqual(len(self.arm_commands(master)), 1)
        # 回拨尝试时刻越过限频窗口：补试成功，全程未重建 master
        link._last_auto_arm_attempt -= link.AUTO_ARM_RETRY_S + 1.0
        link._maybe_retry_auto_arm()
        arm_commands = self.arm_commands(master)
        self.assertEqual(len(arm_commands), 2)
        self.assertEqual(arm_commands[1][4][:2], (1, 21196))
        self.assertTrue(link._auto_arm_done)
        self.assertIs(master, link.master)


class OperatorDisarmRedLineTest(AutoArmTestBase):
    def test_operator_disarm_not_rearmed_by_retry(self) -> None:
        link, master = self.make_link()
        link._on_link_established()
        # 操作员 disarm + 急停：不得触碰 _auto_arm_done
        link.arm(False, force=True)
        link.emergency_stop(disarm=True)
        self.assertTrue(link._auto_arm_done)
        armed_count = len([c for c in self.arm_commands(master) if c[4][0] == 1])
        self.assertEqual(armed_count, 1)
        # 即使越过限频窗口，重试路径也不得重新解锁
        link._last_auto_arm_attempt -= link.AUTO_ARM_RETRY_S + 1.0
        link._maybe_retry_auto_arm()
        armed_count = len([c for c in self.arm_commands(master) if c[4][0] == 1])
        self.assertEqual(armed_count, 1)
        self.assertTrue(link._auto_arm_done)


class AutoArmConfigDefaultTest(unittest.TestCase):
    def test_auto_arm_default_true_when_config_missing(self) -> None:
        self.assertIs(PixhawkLink({}, simulation=False)._auto_arm, True)
        self.assertIs(PixhawkLink({"auto_arm": False}, simulation=False)._auto_arm, False)


class RetryNoopAfterDropTest(AutoArmTestBase):
    def test_retry_noop_when_master_dropped(self) -> None:
        link, master = self.make_link()
        link._drop_link()
        self.assertIsNone(link.master)
        # 断链状态下（master=None）即使限频窗口已过也不产生任何命令
        link._last_auto_arm_attempt -= link.AUTO_ARM_RETRY_S + 1.0
        link._maybe_retry_auto_arm()
        self.assertEqual(master.mav.calls, [])


if __name__ == "__main__":
    unittest.main()
