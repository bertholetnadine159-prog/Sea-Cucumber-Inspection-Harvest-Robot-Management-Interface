#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""RDK X5 链路体检：Ping → TCP → WebSocket 握手 三级检测。

用法：
    python rdkx5/scripts/check_rdk_link.py               # 默认 192.168.127.10:8080
    python rdkx5/scripts/check_rdk_link.py --host H --port P

判定输出（供 test_seaui.bat 使用，退出码 0 = 网关在线）：
    GATEWAY_ONLINE        网关在线（WS hello 握手成功）
    BOARD_UP_NO_GATEWAY   板卡在线但 8080 无 SeaUI 网关应答
    BOARD_UNREACHABLE     板卡不可达
    TUN_SUSPECTED         疑似本机代理 TUN 伪造连通（假阳性，需关代理/插网线）
"""

from __future__ import annotations

import argparse
import asyncio
import json
import socket
import subprocess
import sys
import time

# 一个极大概率无人监听的端口：若对它"连接成功"，说明有 TUN 代理在伪造应答
_CANARY_PORT = 49999


def ping_once(host: str, timeout_ms: int = 1500) -> bool:
    """ICMP 探测（跨平台），仅作参考信号。"""
    param = "-n" if sys.platform == "win32" else "-c"
    wait = "-w" if sys.platform == "win32" else "-W"
    wait_val = str(timeout_ms) if sys.platform == "win32" else str(max(1, timeout_ms // 1000))
    try:
        r = subprocess.run(
            ["ping", param, "1", wait, wait_val, host],
            capture_output=True, timeout=timeout_ms / 1000 + 2,
        )
        return r.returncode == 0
    except Exception:
        return False


def tcp_open(host: str, port: int, timeout: float = 2.0) -> bool:
    s = socket.socket()
    s.settimeout(timeout)
    try:
        s.connect((host, port))
        return True
    except OSError:
        return False
    finally:
        s.close()


async def ws_hello(host: str, port: int, timeout: float = 4.0) -> str | None:
    """尝试 SeaUI 网关 WS 握手，返回 hello 报文或 None。"""
    try:
        import websockets
    except ImportError:
        print("[!] 未安装 websockets：pip install websockets")
        return None
    try:
        async with websockets.connect(f"ws://{host}:{port}", open_timeout=timeout) as ws:
            raw = await asyncio.wait_for(ws.recv(), timeout=timeout)
            msg = json.loads(raw)
            return msg if msg.get("type") == "hello" else None
    except Exception:
        return None


def main() -> int:
    parser = argparse.ArgumentParser(description="RDK X5 链路体检")
    parser.add_argument("--host", default="192.168.127.10")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--timeout", type=float, default=3.0)
    args = parser.parse_args()

    print(f"[1/4] Ping {args.host} ...")
    ping_ok = ping_once(args.host)
    print("      ICMP:", "通" if ping_ok else "不通（部分板卡/防火墙会禁 ping，继续 TCP 检测）")

    print(f"[2/4] TCP {args.host}:{args.port} ...")
    port_ok = tcp_open(args.host, args.port, args.timeout)
    print("      网关端口:", "可连接" if port_ok else "不可达")

    print(f"[3/4] 代理假应答检测（金丝雀端口 {_CANARY_PORT}）...")
    canary_ok = tcp_open(args.host, _CANARY_PORT, args.timeout)
    if canary_ok:
        print("      [!] 一个不应开放的端口也'连接成功'——本机代理 TUN 正在伪造连通！")
        print("          （常见于 Mihomo/Clash TUN 模式）该环境下 TCP 结果不可信。")

    print(f"[4/4] WebSocket 握手 ws://{args.host}:{args.port} ...")
    t0 = time.time()
    hello = asyncio.run(ws_hello(args.host, args.port, args.timeout + 1))
    if hello is not None:
        backend = hello.get("backend", "?")
        print(f"      收到 hello（{time.time() - t0:.1f}s）：backend={backend}")
        print("VERDICT: GATEWAY_ONLINE —— SeaUI 网关在线，可以获取真实数据")
        return 0

    if not port_ok:
        print("      无应答")
        print("VERDICT: BOARD_UNREACHABLE —— 板卡不可达")
        print("  排查：1) 网线是否插好（本机'以太网'应显示已连接）")
        print("        2) 板卡是否上电启动完成")
        print("        3) 本机网卡是否已配 192.168.127.x 网段（rdkx5/scripts/setup_pc_network.ps1 -Check）")
        return 2

    if canary_ok:
        print("      TCP 假通，WS 无应答")
        print("VERDICT: TUN_SUSPECTED —— 板卡大概率未连接，结果被代理伪造")
        print("  排查：关闭 Mihomo/Clash 的 TUN 模式后重试；确认网线与板卡供电")
        return 3

    print("      TCP 可连但无 WS 应答")
    print("VERDICT: BOARD_UP_NO_GATEWAY —— 板卡在线，但 8080 上没有 SeaUI 网关")
    print("  排查：上板执行 cd ~/seaUI_rdk && ./run_robot.sh（或安装 rdkx5/deploy/seaui-gateway.service）")
    return 1


if __name__ == "__main__":
    sys.exit(main())
