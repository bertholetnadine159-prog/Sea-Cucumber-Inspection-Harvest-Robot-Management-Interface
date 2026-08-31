import os
import tempfile
import unittest

from database import Database


class DatabaseTest(unittest.TestCase):
    def setUp(self) -> None:
        fd, self.db_path = tempfile.mkstemp(suffix=".sqlite3")
        os.close(fd)
        os.unlink(self.db_path)
        self.db = Database(self.db_path)

    def tearDown(self) -> None:
        for suffix in ("", "-wal", "-shm"):
            try:
                os.remove(self.db_path + suffix)
            except FileNotFoundError:
                pass
            except OSError:
                # Windows 下 SQLite 句柄未完全释放时允许测试继续
                pass

    def test_super_admin_seeded_and_verified(self) -> None:
        user = self.db.verify_credentials("zmm", "Zmm771023")
        self.assertIsNotNone(user)
        self.assertEqual(user["role"], "super_admin")

    def test_wrong_or_missing_credentials_blocked(self) -> None:
        self.assertIsNone(self.db.verify_credentials("zmm", "wrong"))
        self.assertIsNone(self.db.verify_credentials("", ""))
        self.assertIsNone(self.db.verify_credentials("zmm", ""))
        self.assertIsNone(self.db.verify_credentials("nobody", "Zmm771023"))

    def test_password_is_not_stored_in_plaintext(self) -> None:
        raw = open(self.db_path, "rb").read()
        self.assertNotIn(b"Zmm771023", raw)

    def test_session_flow(self) -> None:
        user = self.db.verify_credentials("zmm", "Zmm771023")
        token, _ = self.db.create_session(user["id"])
        session_user = self.db.validate_session(token)
        self.assertEqual(session_user["username"], "zmm")
        self.db.revoke_session(token)
        self.assertIsNone(self.db.validate_session(token))

    def test_user_crud_and_super_admin_protection(self) -> None:
        user_id = self.db.create_user("op1", "secret123", "admin", "操作员甲")
        users = self.db.list_users()
        self.assertEqual(len(users), 2)
        self.assertIsNotNone(self.db.verify_credentials("op1", "secret123"))

        self.db.change_password(user_id, "newpass")
        self.assertIsNone(self.db.verify_credentials("op1", "secret123"))
        self.assertIsNotNone(self.db.verify_credentials("op1", "newpass"))

        super_id = self.db.verify_credentials("zmm", "Zmm771023")["id"]
        self.assertFalse(self.db.delete_user(super_id))
        self.assertTrue(self.db.delete_user(user_id))

    def test_sensor_and_control_logs(self) -> None:
        self.db.log_sensor_snapshot({
            "ms5837_depth": {"ok": True, "values": {"depth_m": 0.42, "temperature_c": 18.6}},
            "broken": {"ok": False, "message": "n/a"},
        })
        readings = self.db.get_sensor_readings()
        names = [row["name"] for row in readings]
        self.assertIn("ms5837_depth.depth_m", names)
        self.assertNotIn("broken", names)

        self.db.log_control("zmm", "forward", {"speed": 1.0}, True)
        logs = self.db.get_control_logs()
        self.assertEqual(logs[0]["command"], "forward")

    def test_settings_roundtrip(self) -> None:
        self.db.set_setting("rdk_host", "192.168.127.10")
        self.assertEqual(self.db.get_setting("rdk_host"), "192.168.127.10")
        self.db.set_setting("rdk_host", "192.168.127.20")
        self.assertEqual(self.db.get_setting("rdk_host"), "192.168.127.20")


if __name__ == "__main__":
    unittest.main()
