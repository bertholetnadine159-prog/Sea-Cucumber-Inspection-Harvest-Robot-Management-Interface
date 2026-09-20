#!/usr/bin/env python3
"""PC 端 SQLite 数据库：管理员账号、会话、传感器数据、控制日志、设置。

所有管理员与传感器数据都落库。超级管理员在首次启动时自动创建：
    用户名 zmm / 密码 Zmm771023
密码使用 PBKDF2-HMAC-SHA256 加盐哈希，不保存明文。
"""

from __future__ import annotations

import hashlib
import hmac
import os
import secrets
import sqlite3
import time
from pathlib import Path
from typing import Any


DEFAULT_DB_PATH = Path(__file__).resolve().parent / "data" / "seaUI.db"
# 首次启动自动创建的超级管理员；正式部署请用环境变量覆盖或在设置页改密
SUPER_ADMIN_USERNAME = os.environ.get("ROV_SUPER_ADMIN_USERNAME", "zmm")
SUPER_ADMIN_PASSWORD = os.environ.get("ROV_SUPER_ADMIN_PASSWORD", "Zmm771023")
PASSWORD_ITERATIONS = 200_000
SESSION_TTL_SECONDS = 12 * 3600


def _hash_password(password: str, salt: str) -> str:
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), bytes.fromhex(salt), PASSWORD_ITERATIONS)
    return digest.hex()


class Database:
    def __init__(self, path: str | Path = DEFAULT_DB_PATH):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA foreign_keys=ON")
        return connection

    def _initialize(self) -> None:
        with self._connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS users (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    username TEXT UNIQUE NOT NULL,
                    password_hash TEXT NOT NULL,
                    salt TEXT NOT NULL,
                    role TEXT NOT NULL DEFAULT 'admin',
                    real_name TEXT NOT NULL DEFAULT '',
                    enabled INTEGER NOT NULL DEFAULT 1,
                    created_at TEXT NOT NULL,
                    last_login_at TEXT
                );

                CREATE TABLE IF NOT EXISTS sessions (
                    token TEXT PRIMARY KEY,
                    user_id INTEGER NOT NULL,
                    created_at TEXT NOT NULL,
                    expires_at REAL NOT NULL,
                    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
                );

                CREATE TABLE IF NOT EXISTS sensor_readings (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    ts REAL NOT NULL,
                    source TEXT NOT NULL DEFAULT 'rdk_x5',
                    name TEXT NOT NULL,
                    value REAL,
                    unit TEXT NOT NULL DEFAULT '',
                    extra TEXT NOT NULL DEFAULT '{}'
                );
                CREATE INDEX IF NOT EXISTS idx_sensor_ts ON sensor_readings(ts);

                CREATE TABLE IF NOT EXISTS control_logs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    ts REAL NOT NULL,
                    username TEXT NOT NULL DEFAULT '',
                    command TEXT NOT NULL,
                    params TEXT NOT NULL DEFAULT '{}',
                    ok INTEGER NOT NULL DEFAULT 1
                );
                CREATE INDEX IF NOT EXISTS idx_control_ts ON control_logs(ts);

                CREATE TABLE IF NOT EXISTS settings (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );
                """
            )
            self._seed_super_admin(connection)

    def _seed_super_admin(self, connection: sqlite3.Connection) -> None:
        row = connection.execute("SELECT COUNT(*) FROM users").fetchone()
        if row is not None and row[0] > 0:
            return
        self._create_user(connection, SUPER_ADMIN_USERNAME, SUPER_ADMIN_PASSWORD, "super_admin", "超级管理员")

    @staticmethod
    def _create_user(connection: sqlite3.Connection, username: str, password: str, role: str, real_name: str) -> int:
        salt = secrets.token_hex(16)
        password_hash = _hash_password(password, salt)
        cursor = connection.execute(
            """
            INSERT INTO users (username, password_hash, salt, role, real_name, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (username, password_hash, salt, role, real_name, time.strftime("%Y-%m-%dT%H:%M:%S%z")),
        )
        return int(cursor.lastrowid)

    # ------------------------------------------------------------------ users
    def verify_credentials(self, username: str, password: str) -> dict[str, Any] | None:
        if not username or not password:
            return None
        with self._connect() as connection:
            row = connection.execute(
                "SELECT * FROM users WHERE username = ? AND enabled = 1", (username,)
            ).fetchone()
        if row is None:
            return None
        expected = _hash_password(password, row["salt"])
        if not hmac.compare_digest(expected, row["password_hash"]):
            return None
        with self._connect() as connection:
            connection.execute(
                "UPDATE users SET last_login_at = ? WHERE id = ?",
                (time.strftime("%Y-%m-%dT%H:%M:%S%z"), row["id"]),
            )
        return {
            "id": row["id"],
            "username": row["username"],
            "role": row["role"],
            "real_name": row["real_name"],
        }

    def must_change_password(self, user: dict[str, Any], password: str) -> bool:
        """契约 §4：super_admin 仍使用初始口令（ROV_SUPER_ADMIN_PASSWORD 环境变量当前值，
        未设置时回退到内置默认口令）时返回 True，UI 据此强制弹出改密对话框。"""
        if user.get("role") != "super_admin":
            return False
        initial = os.environ.get("ROV_SUPER_ADMIN_PASSWORD", SUPER_ADMIN_PASSWORD)
        return hmac.compare_digest(str(password), initial)

    def create_session(self, user_id: int) -> tuple[str, float]:
        token = secrets.token_hex(32)
        now = time.time()
        with self._connect() as connection:
            connection.execute(
                "INSERT INTO sessions (token, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)",
                (token, user_id, time.strftime("%Y-%m-%dT%H:%M:%S%z"), now + SESSION_TTL_SECONDS),
            )
        return token, now + SESSION_TTL_SECONDS

    def validate_session(self, token: str) -> dict[str, Any] | None:
        if not token:
            return None
        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT u.*, s.expires_at
                FROM sessions s
                JOIN users u ON u.id = s.user_id
                WHERE s.token = ? AND u.enabled = 1
                """,
                (token,),
            ).fetchone()
        if row is None or row["expires_at"] < time.time():
            return None
        return {
            "id": row["id"],
            "username": row["username"],
            "role": row["role"],
            "real_name": row["real_name"],
            # WS auth 沿用 token 登录时需要回传会话到期时刻（app.handle_auth_message）；
            # 其余调用方只读身份/角色字段，新增键为纯增量，不影响既有行为。
            "expires_at": row["expires_at"],
        }

    def revoke_session(self, token: str) -> None:
        with self._connect() as connection:
            connection.execute("DELETE FROM sessions WHERE token = ?", (token,))

    def list_users(self) -> list[dict[str, Any]]:
        with self._connect() as connection:
            rows = connection.execute("SELECT id, username, role, real_name, enabled, created_at, last_login_at FROM users").fetchall()
        return [dict(row) for row in rows]

    def create_user(self, username: str, password: str, role: str = "admin", real_name: str = "") -> int:
        username = username.strip()
        if not username or not password:
            raise ValueError("username and password are required")
        with self._connect() as connection:
            return self._create_user(connection, username, password, role, real_name)

    def update_user(self, user_id: int, role: str | None = None, real_name: str | None = None, enabled: bool | None = None) -> None:
        fields: list[str] = []
        values: list[Any] = []
        if role is not None:
            fields.append("role = ?")
            values.append(role)
        if real_name is not None:
            fields.append("real_name = ?")
            values.append(real_name)
        if enabled is not None:
            fields.append("enabled = ?")
            values.append(1 if enabled else 0)
        if not fields:
            return
        values.append(user_id)
        with self._connect() as connection:
            connection.execute(f"UPDATE users SET {', '.join(fields)} WHERE id = ?", values)

    def change_password(self, user_id: int, new_password: str) -> None:
        if not new_password:
            raise ValueError("password cannot be empty")
        salt = secrets.token_hex(16)
        password_hash = _hash_password(new_password, salt)
        with self._connect() as connection:
            connection.execute(
                "UPDATE users SET password_hash = ?, salt = ? WHERE id = ?",
                (password_hash, salt, user_id),
            )
            connection.execute("DELETE FROM sessions WHERE user_id = ?", (user_id,))

    def delete_user(self, user_id: int, protected_username: str = SUPER_ADMIN_USERNAME) -> bool:
        with self._connect() as connection:
            row = connection.execute("SELECT username FROM users WHERE id = ?", (user_id,)).fetchone()
            if row is None or row["username"] == protected_username:
                return False
            connection.execute("DELETE FROM users WHERE id = ?", (user_id,))
            return True

    # ------------------------------------------------------------------ data
    def log_sensor(self, name: str, value: float, unit: str = "", source: str = "rdk", extra: dict[str, Any] | None = None) -> None:
        import json

        with self._connect() as connection:
            connection.execute(
                "INSERT INTO sensor_readings (ts, source, name, value, unit, extra) VALUES (?, ?, ?, ?, ?, ?)",
                (time.time(), source, name, value, unit, json.dumps(extra or {}, ensure_ascii=False)),
            )

    def log_sensor_snapshot(self, readings: dict[str, dict[str, Any]], source: str = "rdk") -> None:
        """把一次遥测里的标量数值批量入库（source 由调用方按后端模式打标：rdk/local/sim）。"""
        for name, reading in readings.items():
            if not isinstance(reading, dict) or not reading.get("ok"):
                continue
            values = reading.get("values", {})
            for key, value in values.items():
                if isinstance(value, (int, float)) and not isinstance(value, bool):
                    self.log_sensor(f"{name}.{key}", float(value), source=source)

    def log_control(self, username: str, command: str, params: dict[str, Any], ok: bool) -> None:
        import json

        with self._connect() as connection:
            connection.execute(
                "INSERT INTO control_logs (ts, username, command, params, ok) VALUES (?, ?, ?, ?, ?)",
                (time.time(), username, command, json.dumps(params, ensure_ascii=False), 1 if ok else 0),
            )

    def get_sensor_readings(self, limit: int = 500) -> list[dict[str, Any]]:
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT ts, source, name, value, unit, extra FROM sensor_readings ORDER BY id DESC LIMIT ?",
                (max(1, min(limit, 5000)),),
            ).fetchall()
        return [dict(row) for row in rows]

    def get_stats(self) -> dict[str, Any]:
        """管理面板统计（契约 §2）。传感器指标只统计 source='rdk' 的真实链路数据，sim 不计入。"""
        now = time.time()
        day_ago = now - 86400
        with self._connect() as connection:
            users = connection.execute("SELECT COUNT(*) AS n FROM users").fetchone()["n"]
            sessions_active = connection.execute(
                "SELECT COUNT(*) AS n FROM sessions WHERE expires_at >= ?", (now,)
            ).fetchone()["n"]
            control_logs_24h = connection.execute(
                "SELECT COUNT(*) AS n FROM control_logs WHERE ts >= ?", (day_ago,)
            ).fetchone()["n"]
            sensor_readings_24h = connection.execute(
                "SELECT COUNT(*) AS n FROM sensor_readings WHERE ts >= ? AND source = 'rdk'", (day_ago,)
            ).fetchone()["n"]
        try:
            db_size_mb = round(self.path.stat().st_size / (1024 * 1024), 2)
        except OSError:
            db_size_mb = 0.0
        return {
            "users": int(users),
            "sessions_active": int(sessions_active),
            "control_logs_24h": int(control_logs_24h),
            "sensor_readings_24h": int(sensor_readings_24h),
            "db_size_mb": float(db_size_mb),
        }

    def query_sensor_series(
        self,
        source: str = "rdk",
        names: list[str] | None = None,
        from_ts: float | None = None,
        to_ts: float | None = None,
        limit: int = 500,
    ) -> list[dict[str, Any]]:
        """按条件查询传感器原始行（时间倒序，最多 limit 条，上限 5000），供 /api/sensors 组装。"""
        sql = "SELECT ts, source, name, value, unit, extra FROM sensor_readings WHERE source = ?"
        params: list[Any] = [source]
        if names:
            placeholders = ", ".join("?" for _ in names)
            sql += f" AND name IN ({placeholders})"
            params.extend(names)
        if from_ts is not None:
            sql += " AND ts >= ?"
            params.append(float(from_ts))
        if to_ts is not None:
            sql += " AND ts <= ?"
            params.append(float(to_ts))
        sql += " ORDER BY ts DESC, id DESC LIMIT ?"
        params.append(max(1, min(int(limit), 5000)))
        with self._connect() as connection:
            rows = connection.execute(sql, params).fetchall()
        return [dict(row) for row in rows]

    def get_control_logs(self, limit: int = 500) -> list[dict[str, Any]]:
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT ts, username, command, params, ok FROM control_logs ORDER BY id DESC LIMIT ?",
                (max(1, min(limit, 5000)),),
            ).fetchall()
        return [dict(row) for row in rows]

    # --------------------------------------------------------------- settings
    def get_setting(self, key: str, default: str = "") -> str:
        with self._connect() as connection:
            row = connection.execute("SELECT value FROM settings WHERE key = ?", (key,)).fetchone()
        return str(row["value"]) if row is not None else default

    def set_setting(self, key: str, value: str) -> None:
        with self._connect() as connection:
            connection.execute(
                "INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                (key, value),
            )
