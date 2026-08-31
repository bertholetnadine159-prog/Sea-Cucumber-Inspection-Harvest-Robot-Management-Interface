# ============================================================================
# [RDK X5 side] Pixhawk 2.4.8 控制链路
# 运行在 RDK X5 上，负责把 PC 下发的运动/吸捕/舵机命令转成 MAVLink，
# 并把 Pixhawk 的状态读回来。
#
# 控制链：SeaUI(PC) --WebSocket--> RDK X5 gateway --MAVLink/UART--> Pixhawk 2.4.8
#
# 两种控制模式（config.yaml -> pixhawk.control_mode）：
#   manual_control : ArduSub MANUAL_CONTROL（推荐）
#                    x=前后 y=左右 z=垂直 r=偏航，飞控保留稳定回路
#   servo_pwm      : MAV_CMD_DO_SET_SERVO 直通 PWM（兼容 PX4/任意固件）
#
# 安全：deadman 看门狗，超时未收到运动指令立即输出中立值。
# ============================================================================
from __future__ import annotations

import logging
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


LOGGER = logging.getLogger("rdkx5.pixhawk")


@dataclass
class Telemetry:
    connected: bool = False
    armed: bool = False
    mode: str = ""
    battery_v: float | None = None
    battery_remaining: int | None = None
    attitude_deg: dict[str, float] = field(default_factory=lambda: {"roll": 0.0, "pitch": 0.0, "yaw": 0.0})
    alt_m: float | None = None
    motors_pwm: list[int] = field(default_factory=lambda: [0] * 8)
    aux_pwm: list[int] = field(default_factory=lambda: [0] * 8)
    vcc_v: float | None = None
    vservo_v: float | None = None
    sensors_health: int = 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "connected": self.connected,
            "armed": self.armed,
            "mode": self.mode,
            "battery_v": self.battery_v,
            "battery_remaining": self.battery_remaining,
            "attitude_deg": dict(self.attitude_deg),
            "alt_m": self.alt_m,
            "motors_pwm": list(self.motors_pwm),
            "aux_pwm": list(self.aux_pwm),
            "vcc_v": self.vcc_v,
            "vservo_v": self.vservo_v,
            "sensors_health": self.sensors_health,
        }


class SimulatedPixhawk:
    """PC 端测试替身，不依赖任何硬件。"""

    def __init__(self) -> None:
        self.connected = True
        self.armed = False
        self.mode = "MANUAL"
        self.outputs: dict[int, int] = {}
        self.last_axes: dict[str, float] = {}

    def start(self) -> None:
        LOGGER.info("Simulated Pixhawk started")

    def set_deadman_ms(self, ms: float) -> None:
        self.deadman_ms = max(0.0, float(ms))

    def set_axes(self, axes: dict[str, float]) -> None:
        self.last_axes = dict(axes)

    def set_pwm(self, channel: int, pwm: int) -> None:
        self.outputs[int(channel)] = int(pwm)

    def arm(self, enable: bool, force: bool = False) -> None:
        self.armed = bool(enable)

    def set_mode(self, mode: str) -> None:
        self.mode = str(mode)

    def initialize_escs(self) -> None:
        for ch in range(1, 17):
            self.outputs[ch] = 1000 if ch in (13, 14) else 1500

    def read_param(self, name: str, timeout: float = 2.0) -> float | None:
        defaults = {"MOT_PWM_TYPE": 0, "BRD_PWM_COUNT": 4, "BRD_SAFETYENABLE": 0,
                        "FRAME_CLASS": 2, "DISARM_DELAY": 0, "RC3_TRIM": 1500}
        defaults.update({f"SERVO{i}_FUNCTION": 32 + i for i in range(1, 9)})
        return defaults.get(name)

    def correct_param(self, name: str, value: float) -> bool:
        return True

    def verify_motor_config(self) -> dict[str, Any]:
       return {"simulated": True, "params": {}, "issues": []}

    def esc_calibrate(self, channels=None):
        return {"simulated": True, "channels": channels or list(range(1, 9))}

    def calibrate_one_way(self, channels=None):
        return {"simulated": True, "channels": channels or list(range(1, 9))}

    def snapshot(self) -> Telemetry:
        telemetry = Telemetry(connected=True, armed=self.armed, mode=self.mode)
        telemetry.battery_v = 12.4
        telemetry.battery_remaining = 88
        return telemetry

    def close(self) -> None:
        pass


class PixhawkLink:
    """RDK X5 上通过 pymavlink 连接 Pixhawk 2.4.8。"""

    AXIS_NAMES = ("surge", "sway", "heave", "roll", "pitch", "yaw")
    # ArduPilot treats only param2 == 21196 as "force" for arm/disarm.
    ARM_FORCE_MAGIC = 21196

    def __init__(self, config: dict[str, Any], simulation: bool = False) -> None:
        self.config = config
        self.simulation = simulation
        self.master = None
        self.mavutil = None
        self.target_system = 1
        self.target_component = 1
        self._telemetry = Telemetry()
        self._telemetry_lock = threading.Lock()
        self._last_heartbeat = 0.0
        self._last_reconnect_attempt = 0.0

        self._control_mode = str(config.get("control_mode", "manual_control")).lower()
        self._control_hz = float(config.get(
            "manual_control_hz" if self._control_mode == "manual_control" else "servo_pwm_hz",
            25,
        ))
        self._deadman_ms = float(config.get("deadman_ms", 1000))
        self._current_axes = {axis: 0.0 for axis in self.AXIS_NAMES}
        self._axes_lock = threading.Lock()
        self._last_command_at = 0.0
        # 待机静音：自动解锁 + 周期重发最近 PWM，避免待机断流触发 ESC"无信号"报警
        self._auto_arm = bool(config.get("auto_arm", True))
        self._auto_arm_done = False
        self._standby_keepalive_s = float(config.get("standby_keepalive_s", 1.0))
        self._last_keepalive_at = 0.0
        self._latched_pwm: dict[int, int] = {}
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None

    # ------------------------------------------------------------------ setup
    def start(self) -> None:
        if self.simulation or not self.config.get("enabled", True):
            self._telemetry.connected = True
            self._telemetry.mode = "SIM"
            self._thread = threading.Thread(target=self._run_sim_loop, daemon=True)
        else:
            try:
                self._connect()
                self._on_link_established()
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("[RDK X5] Pixhawk connect failed (gateway continues without MAVLink): %s", exc)
            self._thread = threading.Thread(target=self._run_loop, daemon=True)
        self._thread.start()

    def _connect(self) -> None:
        try:
            from pymavlink import mavutil
        except Exception as exc:
            raise RuntimeError("pymavlink is required on RDK X5") from exc
        self.mavutil = mavutil
        connection = self._resolve_connection()
        baud = int(self.config.get("baud", 115200))
        LOGGER.info("[RDK X5] Connecting Pixhawk %s @ %d", connection, baud)
        self.master = mavutil.mavlink_connection(connection, baud=baud)
        self.master.wait_heartbeat(timeout=float(self.config.get("heartbeat_timeout_s", 3.0)))
        self.target_system = self.master.target_system
        self.target_component = self.master.target_component
        self._last_heartbeat = time.monotonic()
        # 注意：不要主动请求 RC_CHANNELS/ALL 等数据流。板载 ArduSub（旧固件）在
        # 高频率 SERVO_OUTPUT_RAW/RC 流请求下会触发 watchdog 崩溃重启循环；
        # 遥测沿用固件默认流即可，稳定性优先。
        LOGGER.info(
            "[RDK X5] Pixhawk heartbeat OK system=%s component=%s",
            self.target_system,
            self.target_component,
        )

    def _resolve_connection(self) -> str:
        """解析 Pixhawk 串口：配置路径存在则直接用；否则按 by-id 找 ArduPilot/Pixhawk；
        再退化为第一个 /dev/ttyACM*，避免 Pixhawk 掉电重插后改号失联。"""
        configured = str(self.config.get("connection", "/dev/ttyACM0"))
        if Path(configured).exists():
            return configured
        by_id = Path("/dev/serial/by-id")
        if by_id.exists():
            for candidate in sorted(by_id.glob("usb-*")):
                lowered = candidate.name.lower()
                if "pixhawk" in lowered or "ardupilot" in lowered:
                    LOGGER.info("[RDK X5] Pixhawk resolved by-id: %s", candidate)
                    return str(candidate)
        acm = sorted(Path("/dev").glob("ttyACM*"))
        if acm:
            LOGGER.info("[RDK X5] Pixhawk resolved to first ACM device: %s", acm[0])
            return str(acm[0])
        return configured

    # ------------------------------------------------------------------ input
    def set_axes(self, axes: dict[str, float]) -> None:
        with self._axes_lock:
            for axis in self.AXIS_NAMES:
                self._current_axes[axis] = max(-1.0, min(1.0, float(axes.get(axis, 0.0))))
            self._last_command_at = time.monotonic()

    def set_deadman_ms(self, ms: float) -> None:
        self._deadman_ms = max(0.0, float(ms))

    def neutralize(self) -> None:
        with self._axes_lock:
            for axis in self.AXIS_NAMES:
                self._current_axes[axis] = 0.0

    def arm(self, enable: bool, force: bool = False) -> None:
        if self.simulation:
            self._telemetry.armed = enable
            return
        if self.master is None or self.mavutil is None:
            raise RuntimeError("Pixhawk is not connected")
        self.master.mav.command_long_send(
            self.target_system,
            self.target_component,
            self.mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM,
            0,
            1 if enable else 0,
            self.ARM_FORCE_MAGIC if force else 0,
            0,
            0,
            0,
            0,
            0,
        )
        LOGGER.info("[RDK X5] arm=%s force=%s sent", enable, force)
        if enable:
            self.initialize_escs()

    def set_mode(self, mode: str) -> None:
        if self.simulation:
            self._telemetry.mode = mode
            return
        if self.master is None or self.mavutil is None:
            raise RuntimeError("Pixhawk is not connected")
        mode_id = self.master.mode_mapping().get(mode.upper())
        if mode_id is None:
            raise ValueError(f"Unknown Pixhawk mode: {mode}")
        self.master.mav.set_mode_send(
            self.target_system,
            self.mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED,
            mode_id,
        )
        LOGGER.info("[RDK X5] set_mode=%s", mode)

    def set_pwm(self, channel: int, pwm: int) -> None:
        if self.simulation:
            return
        if self.master is None or self.mavutil is None:
            raise RuntimeError("Pixhawk is not connected")
        self.master.mav.command_long_send(
            self.target_system,
            self.target_component,
            self.mavutil.mavlink.MAV_CMD_DO_SET_SERVO,
            0,
            float(channel),
            float(pwm),
            0,
            0,
            0,
            0,
            0,
        )
        self._latched_pwm[int(channel)] = int(pwm)

    def emergency_stop(self, disarm: bool = False) -> None:
        self.neutralize()
        if disarm:
            try:
                self.arm(False, force=True)
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("[RDK X5] emergency disarm failed: %s", exc)
        if not self.simulation and self.master is not None:
            try:
                self.initialize_escs()
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("[RDK X5] emergency neutral PWM failed: %s", exc)

    # ---------------------------------------------------------- esc init
    def _suction_neutral_pwm(self) -> int:
        """One-way suction ESCs use 1000 = stopped, not 1500."""
        return int(self.config.get("suction_neutral_pwm", 1000))

    def _channel_neutral_pwm(self, channel: int) -> int:
        """Return correct neutral PWM for a given output channel.

        MAIN1-8 (bidirectional thrusters) -> 1500
        AUX5/AUX6 (one-way suction ESCs)  -> 1000
        All other AUX channels            -> 1500
        """
        suction_channels = [int(c) for c in self.config.get("suction_channels", [])]
        if channel in suction_channels:
            return self._suction_neutral_pwm()
        return int(self.config.get("neutral_pwm", 1500))

    def initialize_escs(self) -> None:
        """Send correct neutral PWM to MAIN5-8 and AUX output channels.

        ArduSub 4.1.0 motor mixer outputs 1900 (full throttle) on MAIN5-8
        (vertical thrusters) when armed at neutral throttle, instead of 1500.
        We work around this by setting SERVO5-8_FUNCTION=0 (None) on the
        Pixhawk, which bypasses the mixer for those channels. They are then
        controlled directly via DO_SET_SERVO.

        MAIN1-4 remain as Motor1-4 (controlled by the mixer via MANUAL_CONTROL).
        MAIN5-8 are Function=None (controlled by DO_SET_SERVO in this class).
        AUX9-16 are for suction/servo/lights (also DO_SET_SERVO).
        """
        if self.simulation:
            return
        if self.master is None or self.mavutil is None:
            LOGGER.warning("[RDK X5] initialize_escs: Pixhawk not connected")
            return
        neutral = int(self.config.get("neutral_pwm", 1500))
        suction_neutral = self._suction_neutral_pwm()
        suction_channels = [int(c) for c in self.config.get("suction_channels", [])]
        # MAIN5-8: set to neutral via DO_SET_SERVO (FUNCTION=None, so it works)
        for channel in range(5, 9):
            try:
                self.set_pwm(channel, neutral)
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("[RDK X5] init MAIN channel %d failed: %s", channel, exc)
        # AUX9-16: suction/servo/lights
        for channel in range(9, 17):
            pwm = suction_neutral if channel in suction_channels else neutral
            try:
                self.set_pwm(channel, pwm)
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("[RDK X5] init AUX channel %d failed: %s", channel, exc)
        LOGGER.info(
            "[RDK X5] ESCs initialized: MAIN5-8=%d AUX suction=%d servo=%d",
            neutral,
            suction_neutral,
            neutral,
        )
    # ---------------------------------------------------------- esc calibrate
    def esc_calibrate(self, channels: list[int] | None = None) -> dict[str, Any]:
        """Standard bidirectional ESC throttle-range calibration.

        Sequence:
            1. Send MAX PWM (1900) - ESC enters calibration mode, beeps once
            2. Wait 3 seconds for ESC to acknowledge full throttle
            3. Send NEUTRAL PWM (1500) - ESC learns mid-point, beeps confirmation
            4. Wait 2 seconds

        After this the ESC knows 1900=full forward, 1500=stop, 1100=full reverse.
        This silences the "3-beep, first descending" alarm which means the ESC
        sees a signal but does not recognize 1500 as its stop position.
        """
        if self.simulation:
            return {"simulated": True, "channels": channels or list(range(1, 9))}
        if self.master is None or self.mavutil is None:
            return {"error": "Pixhawk not connected"}
        target_channels = channels or list(range(1, 9))
        max_pwm = int(self.config.get("pwm_max", 1900))
        neutral = int(self.config.get("neutral_pwm", 1500))
        LOGGER.info("[RDK X5] ESC calibrate START channels=%s", target_channels)
        for ch in target_channels:
            self.set_pwm(ch, max_pwm)
        LOGGER.info("[RDK X5] ESC calibrate: sent MAX=%d, waiting 3s", max_pwm)
        time.sleep(3.0)
        for ch in target_channels:
            self.set_pwm(ch, neutral)
        LOGGER.info("[RDK X5] ESC calibrate: sent NEUTRAL=%d, waiting 2s", neutral)
        time.sleep(2.0)
        LOGGER.info("[RDK X5] ESC calibrate DONE")
        return {
            "channels": target_channels,
            "max_pwm": max_pwm,
            "neutral_pwm": neutral,
            "status": "calibration_complete",
        }

    def calibrate_one_way(self, channels: list[int] | None = None) -> dict[str, Any]:
        """Calibrate one-way ESCs (1000=stop, 2000=full).

        One-way ESCs do not reverse. Their stop position is 1000 (min throttle).
        If the ESC beeps 3 tones when receiving 1500, it is likely a one-way
        ESC that sees 1500 as throttle not at zero.
        """
        if self.simulation:
            return {"simulated": True, "channels": channels or list(range(1, 9))}
        if self.master is None or self.mavutil is None:
            return {"error": "Pixhawk not connected"}
        target_channels = channels or list(range(1, 9))
        LOGGER.info("[RDK X5] one-way ESC calibrate START channels=%s", target_channels)
        for ch in target_channels:
            self.set_pwm(ch, 2000)
        LOGGER.info("[RDK X5] one-way: sent 2000, waiting 3s")
        time.sleep(3.0)
        for ch in target_channels:
            self.set_pwm(ch, 1000)
        LOGGER.info("[RDK X5] one-way: sent 1000, waiting 2s")
        time.sleep(2.0)
        LOGGER.info("[RDK X5] one-way ESC calibrate DONE")
        return {
            "channels": target_channels,
            "stop_pwm": 1000,
            "full_pwm": 2000,
            "status": "one_way_calibration_complete",
        }

    # ---------------------------------------------------- param diagnostics
    def read_param(self, name: str, timeout: float = 2.0) -> float | None:
        """Read a single Pixhawk parameter value via MAVLink."""
        if self.simulation or self.master is None or self.mavutil is None:
            return None
        try:
            self.master.mav.param_request_read_send(
                self.target_system, self.target_component, name.encode("ascii"), -1,
            )
            message = self.master.recv_match(type="PARAM_VALUE", blocking=True, timeout=timeout)
            if message is not None and message.param_id.rstrip("\x00") == name:
                return float(message.param_value)
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("[RDK X5] read_param(%s) failed: %s", name, exc)
        return None

    def correct_param(self, name: str, value: float) -> bool:
        """Set a Pixhawk parameter to a corrected value."""
        if self.simulation or self.master is None or self.mavutil is None:
            return False
        try:
            self.master.mav.param_set_send(
                self.target_system,
                self.target_component,
                name.encode("ascii"),
                float(value),
                self.mavutil.mavlink.MAV_PARAM_TYPE_REAL32,
            )
            LOGGER.info("[RDK X5] param %s set to %s", name, value)
            return True
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("[RDK X5] correct_param(%s) failed: %s", name, exc)
            return False

    def verify_motor_config(self) -> dict[str, Any]:
        """Read and verify critical Pixhawk motor-output parameters.

        Returns a diagnostic dict with each parameter's current value, the
        expected value, and whether it matches.  This is the software-side
        root-cause check for ESC "no signal" beeping.
        """
        if self.simulation:
            return {"simulated": True, "params": {}, "issues": []}
        if self.master is None or self.mavutil is None:
            return {"connected": False, "issues": ["Pixhawk not connected"]}

        # (param_name, expected_value, human_readable_issue_if_mismatch)
        checks = [
            ("MOT_PWM_TYPE", 0, "ESC protocol is not normal PWM (0). If DShot/OneShot is set, "
                                    "standard PWM ESCs will report 'no signal'."),
            ("BRD_PWM_COUNT", 4, "MAIN OUT channel count. If 0, the IO coprocessor will not "
                                    "drive MAIN1-8 pins at all."),
            ("BRD_SAFETYENABLE", 0, "Safety switch is enabled. Outputs are blocked until the "
                                    "switch is pressed."),
            ("FRAME_CLASS", 2, "Frame class is not ROV (2). Motor mixing will be wrong."),
            ("DISARM_DELAY", 0, "Auto-disarm timer is active. If the vehicle disarms, MAIN OUT "
                                "goes to 0 and ESCs beep 'no signal'."),
            ("RC3_TRIM", 1500, "RC3 (throttle) trim is not 1500. For bidirectional ESCs the "
                                "neutral must be 1500; 1100 will cause asymmetric output."),
        ]
        # SERVO1-4: Motor1-4 (controlled by ArduSub mixer via MANUAL_CONTROL)
        for i in range(1, 5):
            checks.append((
                f"SERVO{i}_FUNCTION", 32 + i,
                f"SERVO{i} is not set to Motor{i}. The mixer needs this to drive "
                f"horizontal thrusters via MANUAL_CONTROL.",
            ))
        # SERVO5-8: Function=0 (None). We bypass the ArduSub 4.1 vertical motor
        # mixer because it outputs 1900 at neutral throttle. These channels are
        # controlled directly via DO_SET_SERVO in _send_manual_control().
        for i in range(5, 9):
            checks.append((
                f"SERVO{i}_FUNCTION", 0,
                f"SERVO{i} must be 0 (None). If set to Motor{i} ({32+i}), the ArduSub "
                f"4.1 mixer will output 1900 at neutral throttle, causing ESC beeping.",
            ))
        params: dict[str, Any] = {}
        issues: list[str] = []
        for name, expected, issue_text in checks:
            value = self.read_param(name)
            params[name] = {"value": value, "expected": expected, "ok": value == expected}
            if value is None:
                issues.append(f"{name}: could not read (timeout)")
            elif value != expected:
                issues.append(f"{name}={value} (expected {expected}): {issue_text}")

        # Also read the IO coprocessor health from the latest telemetry
        snapshot = self.snapshot()
        motor_health_bit = bool(snapshot.sensors_health & (1 << 7))
        params["motor_output_health_bit"] = {"value": motor_health_bit, "expected": True, "ok": motor_health_bit}
        if not motor_health_bit:
            issues.append("SYS_STATUS motor-output health bit is CLEAR. The IO coprocessor "
                            "may not be driving the MAIN OUT pins.")

        return {"connected": True, "params": params, "issues": issues}

    # ------------------------------------------------------------------ loops
    def _axes_are_stale(self) -> bool:
        if self._deadman_ms <= 0:
            return False
        return (time.monotonic() - self._last_command_at) * 1000.0 > self._deadman_ms

    def _effective_axes(self) -> dict[str, float]:
        if self._axes_are_stale():
            return {axis: 0.0 for axis in self.AXIS_NAMES}
        with self._axes_lock:
            return dict(self._current_axes)

    def _run_sim_loop(self) -> None:
        interval = 1.0 / max(1.0, self._control_hz)
        while not self._stop_event.wait(interval):
            self._telemetry.battery_v = 12.4 + (self._telemetry.battery_v or 0.0) * 0.0
            self._telemetry.battery_remaining = 88
            self._telemetry.attitude_deg["yaw"] = (self._telemetry.attitude_deg["yaw"] + 0.1) % 360.0

    def _run_loop(self) -> None:
        interval = 1.0 / max(1.0, self._control_hz)
        last_gcs_heartbeat = 0.0
        while not self._stop_event.wait(interval):
            if self.master is None or self.mavutil is None:
                # 启动时未连上（或中途掉线）：周期重连，期间不发送任何指令
                now = time.monotonic()
                if now - self._last_reconnect_attempt >= 3.0:
                    self._last_reconnect_attempt = now
                    try:
                        self._connect()
                        self._on_link_established()
                    except Exception as exc:  # noqa: BLE001
                        LOGGER.warning("[RDK X5] Pixhawk reconnect failed: %s", exc)
                continue
            self._drain_messages()
            now = time.monotonic()
            if now - last_gcs_heartbeat >= 1.0:
                last_gcs_heartbeat = now
                self._send_gcs_heartbeat()
            axes = self._effective_axes()
            if self._control_mode == "manual_control":
                self._send_manual_control(axes)
            elif self._control_mode == "rc_override":
                self._send_rc_override(axes)
            else:
                self._send_servo_pwm(axes)
            self._send_keepalive()

    def _on_link_established(self) -> None:
        """链路建立（含掉线重连）后：先发一轮各通道正确中性值，再按配置自动解锁。

        未解锁时 ArduSub 会把 Motor 功能通道（MAIN1-4）输出置为无脉冲，
        电调随即按"无信号"节奏报警；无 RC 场景下上电解锁后中性输出即静音。
        """
        try:
            self.initialize_escs()
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("[RDK X5] initial ESC neutral failed: %s", exc)
        if not self._auto_arm or self._auto_arm_done:
            return
        try:
            self.arm(enable=True, force=True)
            self._auto_arm_done = True
            LOGGER.info("[RDK X5] auto-arm done (standby silencing, pixhawk.auto_arm=true)")
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("[RDK X5] auto-arm failed: %s", exc)

    def _send_keepalive(self) -> None:
        """周期重发各通道最近一次 PWM（待机保活）。

        重发的是"最近命令值"而不是固定中性值，因此不会覆盖已下发的
        吸捕/舵机/垂推 PWM；主要覆盖待机、急停等无持续控制流的阶段，
        防止任何一路输出断流让电调重新进入"无信号"报警。
        """
        if self._standby_keepalive_s <= 0 or not self._latched_pwm:
            return
        now = time.monotonic()
        if now - self._last_keepalive_at < self._standby_keepalive_s:
            return
        self._last_keepalive_at = now
        for channel, pwm in list(self._latched_pwm.items()):
            try:
                self.set_pwm(channel, pwm)
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("[RDK X5] keepalive ch%d failed: %s", channel, exc)

    def _send_gcs_heartbeat(self) -> None:
        """RDK X5 以 GCS 身份定期发心跳，避免 Pixhawk 判定 GCS 失联。"""
        if self.master is None or self.mavutil is None:
            return
        try:
            self.master.mav.heartbeat_send(
                self.mavutil.mavlink.MAV_TYPE_GCS,
                self.mavutil.mavlink.MAV_AUTOPILOT_INVALID,
                0,
                0,
                0,
            )
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("[RDK X5] GCS heartbeat send failed: %s", exc)

    def _drain_messages(self) -> None:
        if self.master is None or self.mavutil is None:
            return
        heartbeat_timeout = float(self.config.get("heartbeat_timeout_s", 3.0))
        try:
            while True:
                message = self.master.recv_match(blocking=False)
                if message is None:
                    break
                mtype = message.get_type()
                if mtype == "HEARTBEAT":
                    self._last_heartbeat = time.monotonic()
                    with self._telemetry_lock:
                        self._telemetry.connected = True
                        self._telemetry.armed = bool(message.base_mode & self.mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED)
                        mode = self.master.flightmode if hasattr(self.master, "flightmode") else ""
                        self._telemetry.mode = str(mode)
                elif mtype == "SYS_STATUS":
                    with self._telemetry_lock:
                        self._telemetry.battery_v = message.voltage_battery / 1000.0
                        self._telemetry.battery_remaining = message.battery_remaining
                        self._telemetry.sensors_health = int(message.onboard_control_sensors_health)
                elif mtype == "POWER_STATUS":
                    with self._telemetry_lock:
                        self._telemetry.vcc_v = message.Vcc / 1000.0
                        self._telemetry.vservo_v = message.Vservo / 1000.0
                elif mtype == "ATTITUDE":
                    with self._telemetry_lock:
                        self._telemetry.attitude_deg = {
                            "roll": message.roll,
                            "pitch": message.pitch,
                            "yaw": message.yaw,
                        }
                elif mtype == "SERVO_OUTPUT_RAW":
                    self._store_motors_pwm(message)
                elif mtype == "VFR_HUD":
                    with self._telemetry_lock:
                        self._telemetry.alt_m = message.alt
                elif mtype == "COMMAND_ACK":
                    LOGGER.info(
                        "[RDK X5] COMMAND_ACK cmd=%s result=%s",
                        message.command,
                        message.result,
                    )
                elif mtype == "STATUSTEXT":
                    LOGGER.info(
                        "[RDK X5] STATUSTEXT sev=%s: %s",
                        message.severity,
                        message.text,
                    )
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("[RDK X5] MAVLink drain error; dropping link for reconnect: %s", exc)
            self._drop_link()
            return

        if time.monotonic() - self._last_heartbeat > heartbeat_timeout:
            LOGGER.warning("[RDK X5] Pixhawk heartbeat timeout; dropping link for reconnect")
            self._drop_link()

    def _store_motors_pwm(self, message) -> None:
        outputs = [int(getattr(message, f"servo{index}_raw", 0) or 0) for index in range(1, 17)]
        with self._telemetry_lock:
            self._telemetry.motors_pwm = outputs[:8]
            self._telemetry.aux_pwm = outputs[8:]

    def _drop_link(self) -> None:
        with self._telemetry_lock:
            self._telemetry.connected = False
        if self.master is not None:
            try:
                self.master.close()
            except Exception:  # noqa: BLE001
                pass
        self.master = None

    def _send_manual_control(self, axes: dict[str, float]) -> None:
        if self.master is None:
            return
        # RC_CHANNELS_OVERRIDE (all 1500) resets ArduSub pilot input failsafe.
        # Without a physical RC receiver, MANUAL_CONTROL alone does not reset
        # FS_PILOT_INPUT; timeout kills IO output and ESCs beep "no signal".
        self._send_rc_override_keepalive()
        # MANUAL_CONTROL for horizontal movement: x=surge, y=sway, r=yaw.
        # z is forced to 500 (neutral) because the ArduSub 4.1 mixer maps
        # z=500 (RC3=1500) to 1900 on MAIN5-8. Vertical thrust is instead
        # sent directly via DO_SET_SERVO on channels 5-8 below.
        x = int(axes["surge"] * 1000)
        y = int(axes["sway"] * 1000)
        z = 500
        r = int(axes["yaw"] * 1000)
        buttons = 0
        try:
            self.master.mav.manual_control_send(self.target_system, x, y, z, r, buttons)
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("[RDK X5] manual_control_send failed: %s", exc)
        # Direct PWM control for vertical thrusters (MAIN5-8).
        # SERVO5-8_FUNCTION=0 (None), so DO_SET_SERVO drives these channels
        # directly, bypassing the broken ArduSub 4.1 vertical motor mixer.
        span = int(self.config.get("pwm_span", 400))
        neutral = int(self.config.get("neutral_pwm", 1500))
        heave_pwm = max(1100, min(1900, neutral + int(axes["heave"] * span)))
        for channel in (5, 6, 7, 8):
            try:
                self.set_pwm(channel, heave_pwm)
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("[RDK X5] heave DO_SET_SERVO ch%d failed: %s", channel, exc)

    def _rc_channels_override(self, channels: list[int]) -> None:
        """Send RC_CHANNELS_OVERRIDE, handling both old and new pymavlink."""
        if self.master is None or self.mavutil is None:
            return
        ch = list(channels) + [65535] * max(0, 16 - len(channels))
        try:
            self.master.mav.rc_channels_override_send(
                self.target_system, self.target_component,
                ch[0], ch[1], ch[2], ch[3], ch[4], ch[5], ch[6], ch[7],
                ch[8], ch[9], ch[10], ch[11], ch[12], ch[13], ch[14], ch[15],
            )
        except TypeError:
            try:
                self.master.mav.rc_channels_override_send(
                    self.target_system, self.target_component,
                    ch[0], ch[1], ch[2], ch[3], ch[4], ch[5], ch[6], ch[7],
                )
            except Exception as exc:
                LOGGER.warning("[RDK X5] rc_override 8ch failed: %s", exc)
        except Exception as exc:
            LOGGER.warning("[RDK X5] rc_override failed: %s", exc)

    def _send_rc_override_keepalive(self) -> None:
        """Send all-1500 RC_CHANNELS_OVERRIDE to reset pilot input failsafe."""
        self._rc_channels_override([1500] * 16)

    def _send_rc_override(self, axes: dict[str, float]) -> None:
        """无遥控接收机时的标准做法：用 RC_CHANNELS_OVERRIDE 作为驾驶员输入。
        它同时会重置 ArduSub 的 Pilot Input Failsafe（FS_PILOT_INPUT），
        避免失去 MANUAL_CONTROL 后约数秒被自动 disarm（输出中断导致电调报警）。"""
        if self.master is None or self.mavutil is None:
            return
        channel_of_axis = {"roll": 1, "pitch": 2, "heave": 3, "yaw": 4, "surge": 5, "sway": 6}
        trims = {
            "roll": int(self.config.get("rc_trim_roll", 1500)),
            "pitch": int(self.config.get("rc_trim_pitch", 1500)),
            # 双向电调 RC3 中性必须是 1500；旧值 1100 是单向电调的，会导致输出不对称。
            "heave": int(self.config.get("rc_trim_heave", 1500)),
            "yaw": int(self.config.get("rc_trim_yaw", 1500)),
            "surge": int(self.config.get("rc_trim_surge", 1500)),
            "sway": int(self.config.get("rc_trim_sway", 1500)),
        }
        span = int(self.config.get("pwm_span", 400))
        channels = [65535] * 16
        for axis, channel in channel_of_axis.items():
            value = trims[axis] + int(round(axes.get(axis, 0.0) * span))
            channels[channel - 1] = max(1000, min(2000, value))
        self._rc_channels_override(channels)

    def _send_servo_pwm(self, axes: dict[str, float]) -> None:
        if self.master is None:
            return
        channel_map = self.config.get("channel_map", {})
        neutral = int(self.config.get("neutral_pwm", 1500))
        span = int(self.config.get("pwm_span", 400))
        pwm_by_channel: dict[int, int] = {}
        for axis in ("surge", "sway", "heave", "roll", "pitch", "yaw"):
            channel = int(channel_map.get(axis, 0))
            if channel <= 0:
                continue
            pwm_by_channel[channel] = max(
                1000,
                min(2000, neutral + int(round(axes[axis] * span))),
            )
        for channel in sorted(set(channel_map.values())):
            pwm_by_channel.setdefault(int(channel), neutral)
        for channel, pwm in pwm_by_channel.items():
            self.set_pwm(channel, pwm)

    # --------------------------------------------------------------- telemetry
    def snapshot(self) -> Telemetry:
        with self._telemetry_lock:
            return Telemetry(
                connected=self._telemetry.connected,
                armed=self._telemetry.armed,
                mode=self._telemetry.mode,
                battery_v=self._telemetry.battery_v,
                battery_remaining=self._telemetry.battery_remaining,
                attitude_deg=dict(self._telemetry.attitude_deg),
                alt_m=self._telemetry.alt_m,
                motors_pwm=list(self._telemetry.motors_pwm),
                aux_pwm=list(self._telemetry.aux_pwm),
                vcc_v=self._telemetry.vcc_v,
                vservo_v=self._telemetry.vservo_v,
                sensors_health=self._telemetry.sensors_health,
            )

    # ------------------------------------------------------------------ close
    def close(self) -> None:
        self._stop_event.set()
        if self._thread is not None:
            self._thread.join(timeout=2.0)
        if self.master is not None:
            try:
                self.master.close()
            except Exception:
                pass
        self.master = None
