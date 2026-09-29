#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""[RDK X5 side] 单路电机测试（motor_test）单元测试。

核心契约：测试窗口内运行循环必须让出被测通道——
  1. RC override 保活对被测通道发 65535（不覆盖），其余通道仍 1500
     （保活不能停，否则 FS_PILOT_INPUT 失控保护会打断输出）；
  2. 垂推 heave DO_SET_SERVO 跳过被测通道；
  3. keepalive 跳过被测通道；
  4. motor_test_spin 以 4Hz 重发目标 PWM，结束后恢复该通道停止值并注销。

不 import pymavlink、不访问真实串口：手工注入 fake master/mavutil。
运行：cd rdkx5 && python -m unittest discover -s tests -v
"""

import threading
import time
import unittest

from pixhawk_link import PixhawkLink

MAV_CMD_DO_SET_SERVO = 183


class FakeMavCommands:
    def __init__(self) -> None:
        self.command_calls: list[tuple[int, int, int, tuple[int, ...]]] = []
        self.rc_override_calls: list[tuple[int, ...]] = []

    def command_long_send(self, target_system, target_component, command,
                          confirmation, *params) -> None:
        self.command_calls.append((target_system, target_component, command, tuple(params)))

    def rc_channels_override_send(self, target_system, target_component, *chans) -> None:
        self.rc_override_calls.append(tuple(chans))


class FakeMaster:
    def __init__(self) -> None:
        self.mav = FakeMavCommands()
        self.target_system = 1
        self.target_component = 1

    def close(self) -> None:
        pass


class FakeMavutil:
    class mavlink:  # noqa: N801 - 与 pymavlink 的属性名保持一致
        MAV_CMD_DO_SET_SERVO = MAV_CMD_DO_SET_SERVO


class MotorTestBase(unittest.TestCase):
    def make_link(self, simulation: bool = False) -> tuple[PixhawkLink, FakeMaster]:
        link = PixhawkLink(
            {
                "control_mode": "manual_control",
                "suction_channels": [13, 14],
                "suction_neutral_pwm": 1000,
                "auto_arm": False,
            },
            simulation=simulation,
        )
        master = FakeMaster()
        link.master = master
        link.mavutil = FakeMavutil()
        return link, master

    @staticmethod
    def servo_calls(master: FakeMaster) -> list[tuple[int, int]]:
        return [
            (c[3][0], c[3][1])
            for c in master.mav.command_calls
            if c[2] == MAV_CMD_DO_SET_SERVO
        ]


class RcOverrideKeepaliveTest(MotorTestBase):
    def test_all_1500_without_test_channels(self) -> None:
        link, master = self.make_link()
        link._send_rc_override_keepalive()
        self.assertEqual(master.mav.rc_override_calls[-1], (1500,) * 16)

    def test_test_channel_gets_65535_others_stay_1500(self) -> None:
        link, master = self.make_link()
        link._test_channels.add(5)
        link._send_rc_override_keepalive()
        channels = master.mav.rc_override_calls[-1]
        self.assertEqual(len(channels), 16)
        self.assertEqual(channels[4], 65535)  # ch5 让出
        for i, value in enumerate(channels):
            if i != 4:
                self.assertEqual(value, 1500, f"ch{i + 1} 应保持 1500")


class HeaveSkipTest(MotorTestBase):
    def test_heave_do_set_servo_skips_test_channels(self) -> None:
        link, master = self.make_link()
        link._test_channels.update({5})
        axes = {"surge": 0.0, "sway": 0.0, "heave": 0.2, "roll": 0.0, "pitch": 0.0, "yaw": 0.0}
        link._send_manual_control(axes)
        channels = {ch for ch, _ in self.servo_calls(master)}
        self.assertNotIn(5, channels)
        self.assertEqual(channels, {6, 7, 8})
        for channel, pwm in self.servo_calls(master):
            self.assertEqual(pwm, 1580)  # 1500 + 0.2*400


class KeepaliveSkipTest(MotorTestBase):
    def test_keepalive_skips_test_channels(self) -> None:
        link, master = self.make_link()
        link._latched_pwm = {5: 1580, 6: 1500}
        link._test_channels.add(5)
        link._last_keepalive_at = 0.0
        link._send_keepalive()
        self.assertEqual(self.servo_calls(master), [(6, 1500)])


class ServoPwmModeSkipTest(MotorTestBase):
    def test_servo_pwm_mode_skips_test_channels(self) -> None:
        link, master = self.make_link()
        link.config["channel_map"] = {
            "surge": 1, "sway": 2, "heave": 5, "roll": 3, "pitch": 4, "yaw": 6,
        }
        link._test_channels.add(1)
        axes = {axis: 0.0 for axis in ("surge", "sway", "heave", "roll", "pitch", "yaw")}
        link._send_servo_pwm(axes)
        channels = {ch for ch, _ in self.servo_calls(master)}
        self.assertNotIn(1, channels)


class MotorTestSpinRealTest(MotorTestBase):
    """真实模式：worker 线程 4Hz 重发目标 PWM，结束恢复停止值并注销。"""

    def test_spin_sends_pwm_and_restores_stop(self) -> None:
        link, master = self.make_link()
        before = len(master.mav.command_calls)
        link.motor_test_spin(13, 1600, duration_s=0.6)
        deadline = time.monotonic() + 5.0
        while 13 in link._test_channels and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertNotIn(13, link._test_channels)
        calls = self.servo_calls(master)[before:]
        self.assertTrue(calls)
        # 目标 PWM 至少发过一次；最后一条是单向电调停止值 1000
        self.assertIn((13, 1600), calls)
        self.assertEqual(calls[-1], (13, 1000))

    def test_pwm_and_duration_clamped(self) -> None:
        link, _ = self.make_link(simulation=True)
        link.motor_test_spin(99, 5000, duration_s=999)
        self.assertEqual(
            link._sim_motor_tests,
            [{"channel": 99, "pwm": 2000, "duration_s": 30.0}],
        )


class MotorTestSpinSimTest(MotorTestBase):
    def test_simulation_records_without_thread(self) -> None:
        link, master = self.make_link(simulation=True)
        link.motor_test_spin(5, 1580, 3.0)
        self.assertEqual(
            link._sim_motor_tests,
            [{"channel": 5, "pwm": 1580, "duration_s": 3.0}],
        )
        self.assertEqual(master.mav.command_calls, [])
        self.assertEqual(link._test_channels, set())


class ConcurrencySanityTest(MotorTestBase):
    def test_two_channels_can_be_tested_sequentially(self) -> None:
        link, master = self.make_link()
        link.motor_test_spin(5, 1580, duration_s=0.5)
        # 立即测下一路：两路窗口短暂重叠也不互相影响
        link.motor_test_spin(6, 1560, duration_s=0.5)
        deadline = time.monotonic() + 6.0
        while link._test_channels and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertEqual(link._test_channels, set())
        calls = dict(self.servo_calls(master))
        self.assertEqual(calls.get(5), 1500)
        self.assertEqual(calls.get(6), 1500)


class PixhawkRebootTest(MotorTestBase):
    def test_reboot_sends_cmd_246_reboot_only(self) -> None:
        link, master = self.make_link()
        link.reboot()
        reboot_calls = [c for c in master.mav.command_calls if c[2] == 246]
        self.assertEqual(len(reboot_calls), 1)
        self.assertEqual(reboot_calls[0][3][0], 1.0)  # param1=1 重启飞控

    def test_reboot_sim_noop(self) -> None:
        link, master = self.make_link(simulation=True)
        link.reboot()
        self.assertEqual(master.mav.command_calls, [])


class ServoOutputRawPortTest(MotorTestBase):
    """SERVO_OUTPUT_RAW port 字段语义：ArduPilot 两包复用 servo1-8 字段。"""

    @staticmethod
    def make_msg(port, first8, second8=None):
        second8 = second8 or [0] * 8
        msg = type("Msg", (), {"port": port})()
        for i in range(8):
            setattr(msg, f"servo{i + 1}_raw", first8[i])
            setattr(msg, f"servo{i + 9}_raw", second8[i])
        return msg

    def test_port1_maps_first8_to_aux(self) -> None:
        link, _ = self.make_link()
        link._store_motors_pwm(self.make_msg(1, [1500, 1500, 1500, 1500, 1600, 1600, 1500, 1500]))
        self.assertEqual(link.snapshot().aux_pwm[4], 1600)   # AUX5=ch13
        self.assertEqual(link.snapshot().motors_pwm, [0] * 8)

    def test_port0_maps_first8_to_main(self) -> None:
        link, _ = self.make_link()
        link._store_motors_pwm(self.make_msg(0, [1580, 1500, 1500, 1500, 1500, 1500, 1500, 1500]))
        self.assertEqual(link.snapshot().motors_pwm[0], 1580)

    def test_port0_with_second8_populates_aux(self) -> None:
        link, _ = self.make_link()
        link._store_motors_pwm(self.make_msg(0, [1500] * 8, [1500] * 6 + [1600, 1000]))
        self.assertEqual(link.snapshot().aux_pwm[6], 1600)
        self.assertEqual(link.snapshot().aux_pwm[7], 1000)


class CalibrateWindowTest(MotorTestBase):
    """电调校准窗口：让出通道并按序列重发 PWM，结束恢复中性并注销。"""

    def test_window_yields_channels_and_replays_sequence(self) -> None:
        link, master = self.make_link()
        link._calibrate_window([5, 6], [(1900, 0.6), (1500, 0.6)])
        self.assertEqual(link._test_channels, set())  # 结束后注销
        calls = self.servo_calls(master)
        channels = {ch for ch, _ in calls}
        self.assertEqual(channels, {5, 6})
        pwms = {pwm for _, pwm in calls}
        self.assertEqual(pwms, {1900, 1500})
        # 序列末尾是 NEUTRAL，且最后一条是中性值
        self.assertEqual(calls[-1][1], 1500)

    def test_window_released_on_error(self) -> None:
        link, _ = self.make_link()
        link._send_do_set_servo = lambda ch, pwm: (_ for _ in ()).throw(RuntimeError("boom"))
        with self.assertRaises(RuntimeError):
            link._calibrate_window([7], [(1900, 0.3)])
        self.assertEqual(link._test_channels, set())


if __name__ == "__main__":
    unittest.main()
