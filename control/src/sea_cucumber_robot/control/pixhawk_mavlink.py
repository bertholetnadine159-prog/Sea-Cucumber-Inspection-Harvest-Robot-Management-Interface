from __future__ import annotations

import logging
import time
from pathlib import Path
from typing import Any


LOGGER = logging.getLogger(__name__)


class PixhawkInterface:
    def connect(self) -> None:
        raise NotImplementedError

    def connected(self) -> bool:
        raise NotImplementedError

    def set_servo_pwm(self, channel: int, pwm: int) -> None:
        raise NotImplementedError

    def set_many_pwm(self, pwm_by_channel: dict[int, int]) -> None:
        for channel, pwm in pwm_by_channel.items():
            self.set_servo_pwm(channel, pwm)

    def reconnect_if_needed(self, retry_interval_s: float = 5.0) -> bool:
        return self.connected()

    def close(self) -> None:
        pass


class SimulatedPixhawk(PixhawkInterface):
    def __init__(self) -> None:
        self.outputs: dict[int, int] = {}
        self._connected = False

    def connect(self) -> None:
        self._connected = True
        LOGGER.info("Simulated Pixhawk connected")

    def connected(self) -> bool:
        return self._connected

    def set_servo_pwm(self, channel: int, pwm: int) -> None:
        if not self._connected:
            raise RuntimeError("simulated Pixhawk is not connected")
        self.outputs[int(channel)] = int(pwm)


class MavlinkPixhawk(PixhawkInterface):
    ARM_FORCE_MAGIC = 21196

    def __init__(self, config: dict[str, Any]) -> None:
        self.config = config
        self.master = None
        self.target_system = 1
        self.target_component = 1
        self._last_heartbeat_s = 0.0
        self._last_reconnect_attempt_s = 0.0
        # manual_control：ArduSub MANUAL_CONTROL（推荐，保留飞控稳定回路）
        # servo_pwm：MAV_CMD_DO_SET_SERVO 直通 PWM（兼容 PX4/任意固件）
        self.control_mode = str(config.get("control_mode", "servo_pwm")).lower()
        self._telemetry: dict[str, Any] = {
            "connected": False,
            "armed": False,
            "mode": "",
            "battery_v": None,
            "battery_remaining": None,
            "attitude_deg": {"roll": 0.0, "pitch": 0.0, "yaw": 0.0},
            "alt_m": None,
        }

    def connect(self) -> None:
        try:
            from pymavlink import mavutil
        except Exception as exc:
            raise RuntimeError("pymavlink is required for Pixhawk control") from exc
        self.mavutil = mavutil
        connection = self._resolve_connection()
        self.master = mavutil.mavlink_connection(
            connection,
            baud=int(self.config.get("baud", 115200)),
        )
        LOGGER.info("Waiting for Pixhawk heartbeat on %s", connection)
        self.master.wait_heartbeat(timeout=float(self.config.get("heartbeat_timeout_s", 3.0)))
        self.target_system = self.master.target_system
        self.target_component = self.master.target_component
        self._last_heartbeat_s = time.monotonic()
        self._telemetry["connected"] = True
        LOGGER.info("Pixhawk heartbeat received system=%s component=%s", self.target_system, self.target_component)

    def _resolve_connection(self) -> str:
        """按配置路径优先；不存在时用 /dev/serial/by-id 定位 ArduPilot/Pixhawk，
        再退化为第一个 /dev/ttyACM*，避免 Pixhawk 掉电重插后改号失联。"""
        configured = str(self.config.get("connection", "/dev/ttyACM0"))
        if Path(configured).exists():
            return configured
        by_id = Path("/dev/serial/by-id")
        if by_id.exists():
            for candidate in sorted(by_id.glob("usb-*")):
                lowered = candidate.name.lower()
                if "pixhawk" in lowered or "ardupilot" in lowered:
                    LOGGER.info("Pixhawk resolved by-id: %s", candidate)
                    return str(candidate)
        acm = sorted(Path("/dev").glob("ttyACM*"))
        if acm:
            LOGGER.info("Pixhawk resolved to first ACM device: %s", acm[0])
            return str(acm[0])
        return configured

    def reconnect_if_needed(self, retry_interval_s: float = 5.0) -> bool:
        """Pixhawk 掉线（掉电重插改号 / 通信中断）后自动恢复连接。"""
        if self.connected():
            return True
        now = time.monotonic()
        if now - self._last_reconnect_attempt_s < retry_interval_s:
            return False
        self._last_reconnect_attempt_s = now
        self.close()
        try:
            self.connect()
            return self.connected()
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("Pixhawk reconnect failed: %s", exc)
            return False

    def connected(self) -> bool:
        if self.master is None:
            return False
        timeout = float(self.config.get("heartbeat_timeout_s", 3.0))
        message = self.master.recv_match(type="HEARTBEAT", blocking=False)
        if message is not None:
            self._last_heartbeat_s = time.monotonic()
        return time.monotonic() - self._last_heartbeat_s <= timeout

    def set_servo_pwm(self, channel: int, pwm: int) -> None:
        if self.master is None:
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

    def arm(self, enable: bool, force: bool = False) -> None:
        """解锁 / 锁定 Pixhawk。"""
        if self.master is None:
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

    def set_mode(self, mode: str) -> None:
        """切换飞行模式（如 MANUAL / STABILIZE）。"""
        if self.master is None:
            raise RuntimeError("Pixhawk is not connected")
        mode_id = self.master.mode_mapping().get(mode.upper())
        if mode_id is None:
            raise ValueError(f"Unknown Pixhawk mode: {mode}")
        self.master.mav.set_mode_send(
            self.target_system,
            self.mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED,
            mode_id,
        )

    def manual_control(self, x: float, y: float, z: float, r: float, buttons: int = 0) -> None:
        """ArduSub 虚拟摇杆：x 前后 / y 左右 / z 垂直 / r 偏航，范围 -1000..1000。"""
        if self.master is None:
            raise RuntimeError("Pixhawk is not connected")
        self.master.mav.manual_control_send(
            self.target_system,
            int(max(-1000, min(1000, x))),
            int(max(-1000, min(1000, y))),
            int(max(-1000, min(1000, z))),
            int(max(-1000, min(1000, r))),
            int(buttons),
        )

    def drain_messages(self, max_messages: int = 20) -> None:
        """非阻塞读取状态消息，刷新 telemetry 快照。"""
        if self.master is None:
            return
        for _ in range(max_messages):
            message = self.master.recv_match(blocking=False)
            if message is None:
                break
            mtype = message.get_type()
            if mtype == "HEARTBEAT":
                self._last_heartbeat_s = time.monotonic()
                self._telemetry["connected"] = True
                self._telemetry["armed"] = bool(
                    message.base_mode & self.mavutil.mavlink.MAV_MODE_FLAG_SAFETY_ARMED
                )
                self._telemetry["mode"] = str(
                    getattr(self.master, "flightmode", "") or ""
                )
            elif mtype == "SYS_STATUS":
                self._telemetry["battery_v"] = message.voltage_battery / 1000.0
                self._telemetry["battery_remaining"] = message.battery_remaining
            elif mtype == "ATTITUDE":
                self._telemetry["attitude_deg"] = {
                    "roll": message.roll,
                    "pitch": message.pitch,
                    "yaw": message.yaw,
                }
            elif mtype == "VFR_HUD":
                self._telemetry["alt_m"] = message.alt

    def telemetry_snapshot(self) -> dict[str, Any]:
        self.drain_messages()
        return dict(self._telemetry)

    def close(self) -> None:
        if self.master is not None:
            try:
                self.master.close()
            except Exception:
                pass
        self.master = None


def create_pixhawk(config: dict[str, Any], simulation: bool = False) -> PixhawkInterface:
    if simulation or config.get("simulation", False) or not config.get("enabled", True):
        return SimulatedPixhawk()
    return MavlinkPixhawk(config)
