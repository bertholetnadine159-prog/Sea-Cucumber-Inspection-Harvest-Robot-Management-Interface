#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# [PC side] 一键把 rdkx5/ 部署到 RDK X5，并可选执行硬件自检 / 启动网关。
#
# 依赖：pip install paramiko
# 用法：
#   python deploy_to_board.py --check                       # 上传 + 硬件自检
#   python deploy_to_board.py --check --start-gateway       # 上传 + 自检 + 启动网关
#   python deploy_to_board.py --host 192.168.127.10 --user sunrise --password sunrise
#
# 密码可通过环境变量 RDK_SSH_PASSWORD 覆盖（默认 sunrise）。
# ============================================================================
from __future__ import annotations

import argparse
import os
import socket
import stat
import sys
import time
from pathlib import Path

import paramiko


LOCAL_DIR = Path(__file__).resolve().parent.parent
EXCLUDE_DIRS = {".venv", "__pycache__", ".git", "snapshots", "scripts"}
REMOTE_DIR = "/home/sunrise/seaUI_rdk"


def connect(host: str, user: str, password: str) -> paramiko.SSHClient:
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        host,
        username=user,
        password=password,
        timeout=12,
        look_for_keys=False,
        allow_agent=False,
    )
    return client


def run(client: paramiko.SSHClient, command: str, sudo_password: str | None = None, timeout: int = 120) -> tuple[int, str, str]:
    if sudo_password:
        command = f"echo '{sudo_password}' | sudo -S -p '' {command}"
    _stdin, stdout, stderr = client.exec_command(command, timeout=timeout)
    out = stdout.read().decode(errors="replace")
    err = stderr.read().decode(errors="replace")
    code = stdout.channel.recv_exit_status()
    return code, out, err


def upload(client: paramiko.SSHClient, remote_dir: str) -> int:
    sftp = client.open_sftp()
    count = 0
    try:
        for item in LOCAL_DIR.rglob("*"):
            if not item.is_file():
                continue
            relative = item.relative_to(LOCAL_DIR)
            if any(part in EXCLUDE_DIRS for part in relative.parts):
                continue
            target = f"{remote_dir}/{relative.as_posix()}"
            parent = target.rsplit("/", 1)[0]
            try:
                sftp.stat(parent)
            except FileNotFoundError:
                run(client, f"mkdir -p '{parent}'")
            sftp.put(str(item), target)
            count += 1
        for name in ("gateway.py", "check_hardware.py", "run_robot.sh"):
            run(client, f"chmod +x '{remote_dir}/{name}' 2>/dev/null")
    finally:
        sftp.close()
    return count


def wait_port(host: str, port: int, timeout: float = 20.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection((host, port), timeout=2):
                return True
        except OSError:
            time.sleep(0.5)
    return False


def main() -> None:
    parser = argparse.ArgumentParser(description="[PC side] deploy rdkx5 to RDK X5")
    parser.add_argument("--host", default="192.168.127.10")
    parser.add_argument("--user", default="sunrise")
    parser.add_argument("--password", default=os.getenv("RDK_SSH_PASSWORD", "sunrise"))
    parser.add_argument("--sudo-password", default=None, help="sudo 密码（默认同登录密码）")
    parser.add_argument("--remote-dir", default=REMOTE_DIR)
    parser.add_argument("--install-deps", action="store_true", help="在板卡安装 websockets/pyyaml/pyserial/smbus2/pymavlink")
    parser.add_argument("--add-groups", action="store_true", help="把当前用户加入 dialout,video,i2c 组并重连")
    parser.add_argument("--check", action="store_true", help="上传后运行 check_hardware.py")
    parser.add_argument("--start-gateway", action="store_true", help="上传后后台启动 gateway.py")
    parser.add_argument("--gateway-port", type=int, default=8080)
    args = parser.parse_args()

    client = connect(args.host, args.user, args.password)
    try:
        code, out, _ = run(client, "uname -a && whoami && pwd")
        print(f"[SSH] connected\n{out}")

        run(client, f"mkdir -p '{args.remote_dir}'")
        count = upload(client, args.remote_dir)
        print(f"[UPLOAD] {count} files -> {args.remote_dir}")

        sudo_password = args.sudo_password or args.password
        if args.add_groups:
            code, out, err = run(client, f"usermod -aG dialout,video,i2c {args.user}", sudo_password=sudo_password)
            print(f"[GROUPS] exit={code} {out.strip()} {err.strip()}")
            client.close()
            client = connect(args.host, args.user, args.password)
            print("[SSH] reconnected (group changes applied)")

        if args.install_deps:
            code, out, err = run(
                client,
                "python3 -m pip install --user websockets pyyaml pyserial smbus2 pymavlink",
                timeout=600,
            )
            print(f"[DEPS] exit={code}")
            if code != 0:
                print(err[-500:])

        if args.check:
            code, out, err = run(
                client,
                f"cd '{args.remote_dir}' && python3 check_hardware.py --config config.yaml",
                timeout=180,
            )
            print(f"[CHECK] exit={code}\n{out}")
            if err.strip():
                print(f"[CHECK stderr]\n{err[-500:]}")

        if args.start_gateway:
            # 后台启动网关：不读取 stdout，避免 SSH 通道保持打开导致超时；
            # 启动结果由 wait_port 探测端口确认。
            client.exec_command(
                f"cd '{args.remote_dir}' && setsid nohup python3 gateway.py --config config.yaml > gateway.log 2>&1 < /dev/null &",
                timeout=10,
            )
            ready = wait_port(args.host, args.gateway_port)
            print(f"[GATEWAY] port {args.gateway_port} {'open' if ready else 'NOT open yet'}")
            if not ready:
                _, out, _ = run(client, f"tail -n 30 '{args.remote_dir}/gateway.log'")
                print(out)
    finally:
        client.close()


if __name__ == "__main__":
    main()
