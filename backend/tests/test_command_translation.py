"""translate_ui_command 命令映射单元测试（吸泵开/关 → suction）。

直接导入 app 模块测纯函数；ROV_DB_PATH 指到临时目录，
避免单元测试触碰真实数据库。
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
os.environ["ROV_DB_PATH"] = os.path.join(tempfile.mkdtemp(prefix="seaul_test_"), "translate.sqlite3")
sys.path.insert(0, str(BACKEND_DIR))

import app  # noqa: E402


class PumpCommandTranslationTest(unittest.TestCase):
    """泵开关命令必须落到真实 suction 通道，力度口径与抓取/释放一致。"""

    def test_pump_on_carries_thruster_power_percent(self) -> None:
        command, params = app.translate_ui_command("pumpOn", {"power_percent": 65})
        self.assertEqual(command, "suction")
        self.assertEqual(params, {"power_percent": 65})

    def test_pump_on_defaults_to_full_power(self) -> None:
        command, params = app.translate_ui_command("pumpOn", {})
        self.assertEqual(command, "suction")
        self.assertEqual(params, {"power_percent": 100})

    def test_pump_off_stops_suction_regardless_of_params(self) -> None:
        command, params = app.translate_ui_command("pumpOff", {"power_percent": 99})
        self.assertEqual(command, "suction")
        self.assertEqual(params, {"power_percent": 0})

    def test_pump_on_clamps_out_of_range_percent(self) -> None:
        _, params = app.translate_ui_command("pumpOn", {"power_percent": 150})
        self.assertEqual(params, {"power_percent": 100})
        _, params = app.translate_ui_command("pumpOn", {"power_percent": -5})
        self.assertEqual(params, {"power_percent": 0})

    def test_pump_on_rejects_non_numeric_percent_as_full_power(self) -> None:
        _, params = app.translate_ui_command("pumpOn", {"power_percent": "abc"})
        self.assertEqual(params, {"power_percent": 100})

    def test_grab_release_mapping_unchanged(self) -> None:
        self.assertEqual(
            app.translate_ui_command("grab", {}),
            ("suction", {"power_percent": 100}),
        )
        self.assertEqual(
            app.translate_ui_command("release", {}),
            ("suction", {"power_percent": 0}),
        )


if __name__ == "__main__":
    unittest.main()
