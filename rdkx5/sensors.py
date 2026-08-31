# ============================================================================
# [RDK X5 side] 传感器读取
# 所有传感器都接在 RDK X5 上：VEML7700 光照、MS5837 压力/深度、
# DS18B20 水温、LO81MTW 水下超声波测距。
# 数据由 gateway 打包进 telemetry，通过 WebSocket 回传 PC。
# ============================================================================
from __future__ import annotations

import logging
import math
import threading
import time
from pathlib import Path
from typing import Any


LOGGER = logging.getLogger("rdkx5.sensors")


class Reading:
    def __init__(self, ok: bool, values: dict[str, Any] | None = None, message: str = ""):
        self.ok = ok
        self.values = values or {}
        self.message = message

    def to_dict(self) -> dict[str, Any]:
        return {"ok": self.ok, "values": self.values, "message": self.message}


class VEML7700:
    REG_ALS_CONF = 0x00
    REG_ALS = 0x04
    REG_WHITE = 0x05

    def __init__(self, name: str, config: dict[str, Any], simulation: bool = False):
        self.name = name
        self.config = config
        self.simulation = simulation
        self.bus = None
        self._phase = 0.0

    def open(self) -> None:
        if self.simulation:
            return
        from smbus2 import SMBus

        self.bus = SMBus(int(self.config["bus"]))
        address = int(self.config["address"])
        self.bus.write_word_data(address, self.REG_ALS_CONF, 0x0000)

    def read(self) -> Reading:
        if self.simulation:
            self._phase += 0.12
            lux = 180.0 + 40.0 * math.sin(self._phase)
            return Reading(True, {"lux": lux, "als_raw": int(lux / 0.0576), "white_raw": int(lux / 0.069)})
        if self.bus is None:
            return Reading(False, message="not open")
        try:
            address = int(self.config["address"])
            als_raw = int(self.bus.read_word_data(address, self.REG_ALS)) & 0xFFFF
            white_raw = int(self.bus.read_word_data(address, self.REG_WHITE)) & 0xFFFF
            return Reading(True, {"lux": als_raw * 0.0576, "als_raw": als_raw, "white_raw": white_raw})
        except Exception as exc:  # noqa: BLE001
            return Reading(False, message=str(exc))

    def close(self) -> None:
        if self.bus is not None:
            try:
                self.bus.close()
            except Exception:
                pass
        self.bus = None


class MS5837:
    CMD_RESET = 0x1E
    CMD_ADC_READ = 0x00
    CMD_CONVERT_D1_8192 = 0x4A
    CMD_CONVERT_D2_8192 = 0x5A
    CMD_PROM_READ_BASE = 0xA0
    GRAVITY_M_S2 = 9.80665

    def __init__(self, name: str, config: dict[str, Any], simulation: bool = False):
        self.name = name
        self.config = config
        self.simulation = simulation
        self.bus = None
        self.coefficients: list[int] = []
        self.surface_pressure_mbar: float | None = None

    def open(self) -> None:
        if self.simulation:
            self.surface_pressure_mbar = 1013.25
            return
        from smbus2 import SMBus

        self.bus = SMBus(int(self.config["bus"]))
        address = int(self.config["address"])
        self.bus.write_byte(address, self.CMD_RESET)
        time.sleep(0.02)
        self.coefficients = []
        for index in range(8):
            data = list(self.bus.read_i2c_block_data(address, self.CMD_PROM_READ_BASE + index * 2, 2))
            self.coefficients.append((data[0] << 8) | data[1])
        if all(value == 0 for value in self.coefficients[1:7]):
            raise RuntimeError("MS5837 PROM C1-C6 are all zero")
        pressure_mbar, _ = self._read_pressure_temperature()
        self.surface_pressure_mbar = pressure_mbar

    def _read_pressure_temperature(self) -> tuple[float, float]:
        assert self.bus is not None
        address = int(self.config["address"])

        def convert(command: int) -> int:
            self.bus.write_byte(address, command)
            time.sleep(0.02)
            data = list(self.bus.read_i2c_block_data(address, self.CMD_ADC_READ, 3))
            return (data[0] << 16) | (data[1] << 8) | data[2]

        d1 = convert(self.CMD_CONVERT_D1_8192)
        d2 = convert(self.CMD_CONVERT_D2_8192)
        c = self.coefficients
        dt = d2 - c[5] * 256.0
        temp = 2000.0 + dt * c[6] / 8388608.0
        off = c[2] * 65536.0 + c[4] * dt / 128.0
        sens = c[1] * 32768.0 + c[3] * dt / 256.0
        if temp < 2000.0:
            ti = 3.0 * dt * dt / 8589934592.0
            offi = 3.0 * (temp - 2000.0) ** 2 / 2.0
            sensi = 5.0 * (temp - 2000.0) ** 2 / 8.0
            if temp < -1500.0:
                offi += 7.0 * (temp + 1500.0) ** 2
                sensi += 4.0 * (temp + 1500.0) ** 2
            temp -= ti
            off -= offi
            sens -= sensi
        pressure_mbar = ((d1 * sens / 2097152.0 - off) / 8192.0) / 10.0
        return pressure_mbar, temp / 100.0

    def read(self) -> Reading:
        if self.simulation:
            return Reading(True, {"pressure_mbar": 1018.7, "temperature_c": 18.4, "depth_m": 0.54})
        if self.bus is None:
            return Reading(False, message="not open")
        try:
            pressure_mbar, temperature_c = self._read_pressure_temperature()
            surface = self.surface_pressure_mbar or pressure_mbar
            density = float(self.config.get("fluid_density_kg_m3", 1029.0))
            depth_m = max(0.0, (pressure_mbar - surface) * 100.0 / (density * self.GRAVITY_M_S2))
            return Reading(True, {
                "pressure_mbar": pressure_mbar,
                "temperature_c": temperature_c,
                "depth_m": depth_m,
            })
        except Exception as exc:  # noqa: BLE001
            return Reading(False, message=str(exc))

    def close(self) -> None:
        if self.bus is not None:
            try:
                self.bus.close()
            except Exception:
                pass
        self.bus = None


class DS18B20:
    def __init__(self, name: str, config: dict[str, Any], simulation: bool = False):
        self.name = name
        self.config = config
        self.simulation = simulation
        self.device_file: Path | None = None

    def open(self) -> None:
        if self.simulation:
            return
        root = Path(self.config.get("sysfs_root", "/sys/bus/w1/devices"))
        device_id = self.config.get("device_id")
        candidate = root / str(device_id) / "w1_slave" if device_id else None
        if candidate is None or not candidate.exists():
            matches = sorted(root.glob("28-*/w1_slave"))
            candidate = matches[0] if matches else root / "missing" / "w1_slave"
        if not candidate.exists():
            raise FileNotFoundError(f"DS18B20 sysfs not found for {self.name}: {candidate}")
        self.device_file = candidate

    def read(self) -> Reading:
        if self.simulation:
            return Reading(True, {"temperature_c": 18.8})
        if self.device_file is None:
            return Reading(False, message="not open")
        try:
            lines = self.device_file.read_text(encoding="utf-8").splitlines()
            if len(lines) < 2 or not lines[0].strip().endswith("YES"):
                return Reading(False, message="CRC not ready")
            marker = "t="
            if marker not in lines[1]:
                return Reading(False, message="temperature marker missing")
            milli_c = int(lines[1].split(marker, 1)[1])
            return Reading(True, {"temperature_c": milli_c / 1000.0})
        except Exception as exc:  # noqa: BLE001
            return Reading(False, message=str(exc))

    def close(self) -> None:
        self.device_file = None


class Ultrasonic:
    UART_HEADER = 0xFF
    OUT_OF_WATER = 0xFFFB

    def __init__(self, name: str, config: dict[str, Any], simulation: bool = False):
        self.name = name
        self.config = config
        self.simulation = simulation
        self.serial = None
        self._sim_distance = 0.35

    @staticmethod
    def checksum(data_h: int, data_l: int) -> int:
        return (Ultrasonic.UART_HEADER + data_h + data_l) & 0xFF

    @classmethod
    def parse_ff_uart(cls, raw: bytes) -> tuple[float | None, str]:
        if len(raw) < 4:
            return None, "short frame"
        for index in range(len(raw) - 3):
            if raw[index] != cls.UART_HEADER:
                continue
            frame = raw[index:index + 4]
            _, data_h, data_l, checksum = frame
            if cls.checksum(data_h, data_l) != checksum:
                continue
            distance_mm = data_h * 256 + data_l
            if distance_mm == cls.OUT_OF_WATER:
                return None, "out of water value"
            if distance_mm <= 0:
                return None, f"invalid distance {distance_mm} mm"
            return distance_mm / 1000.0, "ok"
        return None, "valid FF frame not found"

    def open(self) -> None:
        if self.simulation:
            return
        import serial

        self.serial = serial.Serial(
            port=str(self.config["port"]),
            baudrate=int(self.config.get("baudrate", 9600)),
            timeout=float(self.config.get("timeout_s", 0.08)),
        )

    def read(self) -> Reading:
        if self.simulation:
            self._sim_distance = max(0.05, self._sim_distance - 0.002)
            return Reading(True, {"distance_m": self._sim_distance})
        if self.serial is None:
            return Reading(False, message="not open")
        try:
            raw = self.serial.read(8)
            distance_m, message = self.parse_ff_uart(raw)
            if distance_m is None:
                return Reading(False, message=message)
            min_valid = float(self.config.get("min_valid_m", 0.03))
            max_valid = float(self.config.get("max_valid_m", 4.5))
            if not (min_valid <= distance_m <= max_valid):
                return Reading(False, message=f"out of range: {distance_m:.3f} m")
            return Reading(True, {"distance_m": distance_m, "protocol": "ff_uart"})
        except Exception as exc:  # noqa: BLE001
            return Reading(False, message=str(exc))

    def close(self) -> None:
        if self.serial is not None:
            try:
                self.serial.close()
            except Exception:
                pass
        self.serial = None


class SensorHub:
    """统一管理 RDK X5 上所有传感器。"""

    def __init__(self, config: dict[str, Any], simulation: bool = False):
        self.simulation = simulation
        self._readers: dict[str, Any] = {}
        self._readings: dict[str, Reading] = {}
        self._lock = threading.Lock()

        def add_reader(key: str, name: str, factory) -> None:
            cfg = config.get(key)
            if cfg and cfg.get("enabled", True):
                self._readers[name] = factory(name, cfg, simulation)

        add_reader("veml7700_front", "veml7700_front_light", VEML7700)
        add_reader("veml7700_down", "veml7700_down_light", VEML7700)
        add_reader("ms5837", "ms5837_depth", MS5837)
        add_reader("ds18b20_1", "ds18b20_water_1", DS18B20)
        add_reader("ds18b20_2", "ds18b20_water_2", DS18B20)
        add_reader("ultrasonic_front", "ultrasonic_front_suction_mouth", Ultrasonic)
        add_reader("ultrasonic_downward", "ultrasonic_downward_altitude", Ultrasonic)

    def open_all(self) -> None:
        for name, reader in self._readers.items():
            try:
                reader.open()
                LOGGER.info("[RDK X5] sensor opened: %s", name)
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("[RDK X5] sensor %s failed to open: %s", name, exc)

    def read_all(self) -> dict[str, dict[str, Any]]:
        readings: dict[str, Reading] = {}
        for name, reader in self._readers.items():
            try:
                readings[name] = reader.read()
            except Exception as exc:  # noqa: BLE001
                readings[name] = Reading(False, message=str(exc))
        with self._lock:
            self._readings = readings
        return {name: reading.to_dict() for name, reading in readings.items()}

    def latest(self) -> dict[str, dict[str, Any]]:
        with self._lock:
            return {name: reading.to_dict() for name, reading in self._readings.items()}

    def close_all(self) -> None:
        for reader in self._readers.values():
            reader.close()
