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

    def to_dict(self) -> dict[str, Any]:
        return {
            "connected": self.connected,
            "armed": self.armed,
            "mode": self.mode,
            "battery_v": self.battery_v,
            "battery_remaining": self.battery_remaining,
            "attitude_deg": dict(self.attitude_deg),
            "alt_m": self.alt_m,
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

    def set_axes(self, axes: dict[str, float]) -> None:
        self.last_axes = dict(axes)

    def set_pwm(self, channel: int, pwm: int) -> None:
        self.outputs[int(channel)] = int(pwm)

    def arm(self, enable: bool, force: bool = False) -> None:
        self.armed = bool(enable)

    def set_mode(self, mode: str) -> None:
        self.mode = str(mode)

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
            int(force),
            0,
            0,
            0,
            0,
            0,
        )
        LOGGER.info("[RDK X5] arm=%s force=%s sent", enable, force)

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

    def emergency_stop(self, disarm: bool = False) -> None:
        self.neutralize()
        if disarm:
            try:
                self.arm(False, force=True)
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("[RDK X5] emergency disarm failed: %s", exc)
        if not self.simulation and self.master is not None:
            try:
                neutral = int(self.config.get("neutral_pwm", 1500))
                for channel in range(1, 17):
                    self.set_pwm(channel, neutral)
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("[RDK X5] emergency neutral PWM failed: %s", exc)

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
        while not self._stop_event.wait(interval):
            if self.master is None or self.mavutil is None:
                # 启动时未连上（或中途掉线）：周期重连，期间不发送任何指令
                now = time.monotonic()
                if now - self._last_reconnect_attempt >= 3.0:
                    self._last_reconnect_attempt = now
                    try:
                        self._connect()
                    except Exception as exc:  # noqa: BLE001
                        LOGGER.warning("[RDK X5] Pixhawk reconnect failed: %s", exc)
                continue
            self._drain_messages()
            axes = self._effective_axes()
            if self._control_mode == "manual_control":
                self._send_manual_control(axes)
            else:
                self._send_servo_pwm(axes)

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
                elif mtype == "ATTITUDE":
                    with self._telemetry_lock:
                        self._telemetry.attitude_deg = {
                            "roll": message.roll,
                            "pitch": message.pitch,
                            "yaw": message.yaw,
                        }
                elif mtype == "VFR_HUD":
                    with self._telemetry_lock:
                        self._telemetry.alt_m = message.alt
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("[RDK X5] MAVLink drain error: %s", exc)

        if time.monotonic() - self._last_heartbeat > heartbeat_timeout:
            with self._telemetry_lock:
                self._telemetry.connected = False

    def _send_manual_control(self, axes: dict[str, float]) -> None:
        if self.master is None:
            return
        # ArduSub 约定：x=前后，y=左右，z=垂直，r=偏航；范围 -1000..1000。
        x = int(axes["surge"] * 1000)
        y = int(axes["sway"] * 1000)
        z = int(axes["heave"] * 1000)
        r = int(axes["yaw"] * 1000)
        buttons = 0
        try:
            self.master.mav.manual_control_send(self.target_system, x, y, z, r, buttons)
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("[RDK X5] manual_control_send failed: %s", exc)

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
        try:
            self.master.mav.command_long_send(
                self.target_system,
                self.target_component,
                self.mavutil.mavlink.MAV_CMD_DO_SET_SERVO,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
            )
        except Exception:
            pass
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
