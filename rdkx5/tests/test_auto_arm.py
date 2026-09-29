#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""[RDK X5 side] Pixhawk auto-arm / ACK 确认闭环 / 链路重连重解锁单元测试。

不 import pymavlink、不访问真实串口：手工向 PixhawkLink 注入 fake
master/mavutil（不调用 start()），可在任意平台（含无 pymavlink 的
Windows/Python 3.14）独立运行。无真实 sleep、无线程时序依赖。

auto-arm 语义（2026-09-29 起）：发出 ARM 命令只算"在途确认"，
必须收到 COMMAND_ACK(cmd=400, result=0) 才算完成；被拒或 ACK 丢失
按 AUTO_ARM_RETRY_S 限频重发。操作员 disarm/急停终结 auto-arm 使命，
重试路径绝不重新解锁。

运行：cd rdkx5 && python -m unittest discover -s tests -v
"""

import time
import unittest

from pixhawk_link import PixhawkLink

MAV_CMD_COMPONENT_ARM_DISARM = 400
MAV_CMD_DO_SET_SERVO = 183


class FakeMsg:
    """模拟 pymavlink 消息：类型名 + 任意属性。"""

    def __init__(self, mtype: str, **attrs) -> None:
        self._type = mtype
        for key, value in attrs.items():
            setattr(self, key, value)

    def get_type(self) -> str:
        return self._type


class FakeMavCommands:
    """记录每次 command_long_send 的 (target_system, target_component,
    command, confirmation, params)；可选让首次 ARM 命令抛 RuntimeError
    （先记录后抛出，保证"失败尝试"也计数）。"""

    def __init__(self, fail_first_arm: bool = False) -> None:
        self.calls: list[tuple[int, int, int, int, tuple[int, ...]]] = []
        self.param_calls: list[tuple[str, float]] = []
        self._fail_first_arm = fail_first_arm

    def command_long_send(self, target_system, target_component, command,
                          confirmation, *params) -> None:
        self.calls.append(
            (target_system, target_component, command, confirmation, tuple(params)),
        )
        if command == MAV_CMD_COMPONENT_ARM_DISARM and self._fail_first_arm:
            self._fail_first_arm = False
            raise RuntimeError("simulated arm failure")

    def param_set_send(self, target_system, target_component, param_id,
                       value, param_type) -> None:
        self.param_calls.append((param_id.decode() if isinstance(param_id, bytes) else str(param_id),
                                 float(value)))


class FakeMaster:
    """模拟 pymavlink master：持有 mav、消息收件箱、记录 close() 调用。"""

    def __init__(self, fail_first_arm: bool = False) -> None:
        self.mav = FakeMavCommands(fail_first_arm=fail_first_arm)
        self.target_system = 1
        self.target_component = 1
        self.closed = False
        self.inbox: list[FakeMsg] = []

    def recv_match(self, blocking: bool = False, **kwargs):
        # _drain_messages 使用 blocking=False 逐条取空收件箱
        if self.inbox:
            return self.inbox.pop(0)
        return None

    def close(self) -> None:
        self.closed = True


class FakeMavutil:
    """模拟 pymavlink.mavutil 的最小命名空间，仅含测试用到的常量。"""

    class mavlink:  # noqa: N801 - 与 pymavlink 的属性名保持一致
        MAV_CMD_COMPONENT_ARM_DISARM = MAV_CMD_COMPONENT_ARM_DISARM
        MAV_CMD_DO_SET_SERVO = MAV_CMD_DO_SET_SERVO
        MAV_MODE_FLAG_SAFETY_ARMED = 1
        MAV_PARAM_TYPE_REAL32 = 7


class AutoArmTestBase(unittest.TestCase):
    def make_link(self, fail_first_arm: bool = False) -> tuple[PixhawkLink, FakeMaster]:
        link = PixhawkLink(
            {
                "control_mode": "manual_control",
                "suction_channels": [9, 10],
                "suction_neutral_pwm": 1000,
                "auto_arm": True,
            },
            simulation=False,
        )
        master = FakeMaster(fail_first_arm=fail_first_arm)
        link.master = master
        link.mavutil = FakeMavutil()
        return link, master

    def inject_arm_ack(self, link: PixhawkLink, result: int) -> None:
        link.master.inbox.append(
            FakeMsg("COMMAND_ACK", command=MAV_CMD_COMPONENT_ARM_DISARM, result=result),
        )

    def drain(self, link: PixhawkLink) -> None:
        # 刷新心跳时刻避免 _drain_messages 触发心跳超时断链
        link._last_heartbeat = time.monotonic()
        link._drain_messages()

    def confirm_auto_arm(self, link: PixhawkLink, result: int = 0) -> None:
        """注入 ACK 并排水，模拟飞控对 auto-arm 的应答。"""
        self.inject_arm_ack(link, result)
        self.drain(link)

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
        # 发出只是"在途确认"：ACK 到达前不算完成
        self.assertFalse(link._auto_arm_done)
        self.assertIsNotNone(link._auto_arm_pending_at)
        # initialize_escs 在 arm 前后各跑一轮：通道 5-16 各出现两次，
        # 仅锚点通道（ENSURE_LIGHTS_CHANNEL，功能位非 0）不在直控之列
        servos = self.servo_calls(master)
        expected_channels = set(range(5, 17)) - {PixhawkLink.ENSURE_LIGHTS_CHANNEL}
        channels = {ch for ch, _ in servos}
        self.assertEqual(channels, expected_channels)
        self.assertEqual(len(servos), 2 * len(expected_channels))
        for channel, pwm in servos:
            if channel in (9, 10):
                self.assertEqual(pwm, 1000)
            else:
                self.assertEqual(pwm, 1500)

    def test_ack_result_zero_completes_auto_arm(self) -> None:
        link, _ = self.make_link()
        link._on_link_established()
        self.confirm_auto_arm(link, result=0)
        self.assertTrue(link._auto_arm_done)
        self.assertIsNone(link._auto_arm_pending_at)


class EnsureOutputFunctionsTest(AutoArmTestBase):
    """IOMCU 参数掉电不保持 + AUX 输出常开：链路建立必须重发全部保证参数。"""

    def test_ensure_params_sent_before_arm(self) -> None:
        link, master = self.make_link()
        link._on_link_established()
        # 11 个直控通道清零（SERVO12 除外，见下）
        ensured = {name: value for name, value in master.mav.param_calls}
        for channel in (5, 6, 7, 8, 9, 10, 11, 13, 14, 15, 16):
            self.assertEqual(ensured.get(f"SERVO{channel}_FUNCTION"), 0.0)
        # SERVO12 保持 Lights1(11)：AUX 组需非 None 功能位才留在出站包里
        # （2026-09-30 泵/舵机重接线 AUX1/2/3 后锚点从 SERVO9 挪到 SERVO12）
        self.assertEqual(ensured.get("SERVO12_FUNCTION"), 11.0)
        # BRD_PWM_COUNT=6 随每次连接重申（AUX 输出常开硬规则）
        self.assertEqual(ensured.get("BRD_PWM_COUNT"), 6.0)
        # 泵通道 TRIM/MIN=1000：堵死开机空闲窗口输出 1500 的隐患
        for name in ("SERVO9_TRIM", "SERVO10_TRIM", "SERVO9_MIN", "SERVO10_MIN"):
            self.assertEqual(ensured.get(name), 1000.0)
        self.assertEqual(len(master.mav.param_calls), 17)
        # SERVO1-4 混控功能位不被触碰
        self.assertNotIn("SERVO1_FUNCTION", ensured)
        # 次序：param_set 必须全部先于 ARM 命令（解锁前混控必须已让位）
        self.assertTrue(master.mav.param_calls)
        self.assertTrue(self.arm_commands(master))

    def test_reconnect_reensures_params(self) -> None:
        link, master = self.make_link()
        link._on_link_established()
        first_count = len(master.mav.param_calls)
        self.assertEqual(first_count, 17)
        link._drop_link()
        new_master = FakeMaster()
        link.master = new_master
        link.mavutil = FakeMavutil()
        link._on_link_established()
        ensured = {name for name, _ in new_master.mav.param_calls}
        self.assertIn("SERVO5_FUNCTION", ensured)
        self.assertIn("SERVO16_FUNCTION", ensured)
        self.assertIn("SERVO12_FUNCTION", ensured)
        self.assertIn("BRD_PWM_COUNT", ensured)


class AutoArmRejectedRetryTest(AutoArmTestBase):
    def test_rejected_arm_retried_until_accepted(self) -> None:
        link, master = self.make_link()
        link._on_link_established()
        # 飞控预解锁拒绝（result=5）：确认撤销，进入重试状态
        self.confirm_auto_arm(link, result=5)
        self.assertFalse(link._auto_arm_done)
        self.assertIsNone(link._auto_arm_pending_at)
        self.assertEqual(len(self.arm_commands(master)), 1)
        # 限频窗口内不重发
        link._maybe_retry_auto_arm()
        self.assertEqual(len(self.arm_commands(master)), 1)
        # 越过限频窗口：补发 ARM
        link._last_auto_arm_attempt -= link.AUTO_ARM_RETRY_S + 1.0
        link._maybe_retry_auto_arm()
        self.assertEqual(len(self.arm_commands(master)), 2)
        self.assertFalse(link._auto_arm_done)
        # 这次飞控接受：闭环完成，不再重发
        self.confirm_auto_arm(link, result=0)
        self.assertTrue(link._auto_arm_done)
        link._last_auto_arm_attempt -= link.AUTO_ARM_RETRY_S + 1.0
        link._maybe_retry_auto_arm()
        self.assertEqual(len(self.arm_commands(master)), 2)


class AckLostRetryTest(AutoArmTestBase):
    def test_missing_ack_resends_after_confirm_window(self) -> None:
        link, master = self.make_link()
        link._on_link_established()
        self.assertIsNotNone(link._auto_arm_pending_at)
        # 确认窗口内无 ACK 也不补发
        link._maybe_retry_auto_arm()
        self.assertEqual(len(self.arm_commands(master)), 1)
        # ACK 确认窗口（2s）超时：pending 撤销
        link._auto_arm_pending_at -= link.AUTO_ARM_ACK_CONFIRM_S + 0.1
        link._maybe_retry_auto_arm()
        self.assertIsNone(link._auto_arm_pending_at)
        # 仍在限频窗口内：不立即重发
        link._maybe_retry_auto_arm()
        self.assertEqual(len(self.arm_commands(master)), 1)
        # 越过限频窗口：补发
        link._last_auto_arm_attempt -= link.AUTO_ARM_RETRY_S + 1.0
        link._maybe_retry_auto_arm()
        self.assertEqual(len(self.arm_commands(master)), 2)
        self.assertIsNotNone(link._auto_arm_pending_at)


class DropLinkRearmTest(AutoArmTestBase):
    def test_drop_link_resets_and_relink_rearms(self) -> None:
        link, master = self.make_link()
        link._on_link_established()
        self.confirm_auto_arm(link, result=0)
        self.assertTrue(link._auto_arm_done)
        link._drop_link()
        self.assertFalse(link._auto_arm_done)
        self.assertIsNone(link._auto_arm_pending_at)
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
        self.confirm_auto_arm(link, result=0)
        self.assertTrue(link._auto_arm_done)


class FailedArmRetryTest(AutoArmTestBase):
    def test_failed_arm_retried_without_disconnect(self) -> None:
        link, master = self.make_link(fail_first_arm=True)
        link._on_link_established()
        # 发送抛异常：无在途确认、未完成
        self.assertFalse(link._auto_arm_done)
        self.assertIsNone(link._auto_arm_pending_at)
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
        self.assertFalse(link._auto_arm_done)
        # ACK 确认后完成
        self.confirm_auto_arm(link, result=0)
        self.assertTrue(link._auto_arm_done)
        self.assertIs(master, link.master)


class OperatorDisarmRedLineTest(AutoArmTestBase):
    def test_operator_disarm_not_rearmed_by_retry(self) -> None:
        link, master = self.make_link()
        link._on_link_established()
        self.confirm_auto_arm(link, result=0)
        # 操作员 disarm + 急停：终结 auto-arm 使命
        link.arm(False, force=True)
        link.emergency_stop(disarm=True)
        self.assertTrue(link._auto_arm_done)
        self.assertIsNone(link._auto_arm_pending_at)
        armed_count = len([c for c in self.arm_commands(master) if c[4][0] == 1])
        self.assertEqual(armed_count, 1)
        # 即使越过限频窗口，重试路径也不得重新解锁
        link._last_auto_arm_attempt -= link.AUTO_ARM_RETRY_S + 1.0
        link._maybe_retry_auto_arm()
        armed_count = len([c for c in self.arm_commands(master) if c[4][0] == 1])
        self.assertEqual(armed_count, 1)
        self.assertTrue(link._auto_arm_done)

    def test_disarm_during_pending_window_blocks_later_retries(self) -> None:
        # ACK 未到时操作员就 disarm：绝不能让后续重试重新解锁
        link, master = self.make_link()
        link._on_link_established()
        self.assertFalse(link._auto_arm_done)
        link.arm(False, force=True)
        self.assertTrue(link._auto_arm_done)
        self.assertIsNone(link._auto_arm_pending_at)
        # 操作员的 disarm ACK（result=0）不得被误记为 auto-arm 成功后重发
        link._last_auto_arm_attempt -= link.AUTO_ARM_RETRY_S + 1.0
        link._maybe_retry_auto_arm()
        armed_count = len([c for c in self.arm_commands(master) if c[4][0] == 1])
        self.assertEqual(armed_count, 1)

    def test_operator_disarm_ack_not_misattributed(self) -> None:
        # 在途确认被操作员 disarm 清除后，迟到的 ACK 不改变任何状态
        link, _ = self.make_link()
        link._on_link_established()
        link.arm(False, force=True)
        self.confirm_auto_arm(link, result=0)
        self.assertTrue(link._auto_arm_done)
        self.assertIsNone(link._auto_arm_pending_at)


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
