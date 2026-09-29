#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""泵测试控制台（PC 上直接运行，含急停）。

用法：
    python rdkx5/scripts/pump_test_console.py                 # 交互模式
    python rdkx5/scripts/pump_test_console.py --once 1425 2   # 单次：爬升到1425保持2秒后自动停
    python rdkx5/scripts/pump_test_console.py --max 1600      # 放宽上限到1600（默认1550安全帽）

命令（交互模式）：
    1425        爬升到 1425，保持 2 秒（默认），回落+硬停
    1425 4      保持 4 秒（最长 5 秒）
    s / 急停     立即急停（任何时候）
    q           退出（退出前自动急停）

安全设计（实测踩坑换来的，见 docs/PITFALLS_pixhawk_pump_debug.md）：
    ① 只用平滑斜坡驱动（阶跃会被驱动器当毛刺忽略，坑 8）
    ② 动作全程按任意键 = 立即急停（950 低于量程硬停脉冲 + 1000 双保险）
    ③ 每次动作前 10 秒倒计时（可按回车立即开始）；倒计时中按键 = 取消
    ④ 上限默认 1550（1600 实测 2 秒发热）；保持时间最长 5 秒
    ⑤ Ctrl+C / 任何异常 / 退出 → 都会先急停再退出
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import time

import websockets

DEFAULT_WS = "ws://192.168.5.127:8080"
DEFAULT_CHANNEL = 13          # AUX5（泵 1 当前接线）
DEFAULT_CAP = 1550            # 安全上限（1600 实测过热）
HARD_STOP_PWM = 950           # 低于量程硬停脉冲
STOP_PWM = 1000               # 停止值
MAX_HOLD_S = 5.0              # 电机全速 2 秒即发热，保持最长 5 秒
RAMP_STEP = 20                # 每步 ≤20us
RAMP_INTERVAL = 0.03          # 间隔 ≥30ms


def key_pressed() -> bool:
    """非阻塞检测任意按键（Windows msvcrt / POSIX select）。"""
    try:
        import msvcrt
        return msvcrt.kbhit()
    except ImportError:
        import select
        return bool(select.select([sys.stdin], [], [], 0)[0])


class PumpConsole:
    def __init__(self, ws, channel: int, cap: int) -> None:
        self.ws = ws
        self.ch = channel
        self.cap = cap

    async def cmd(self, command: str, params: dict, timeout: float = 3.0):
        await self.ws.send(json.dumps({"type": "command", "command": command, "params": params}))
        deadline = time.monotonic() + timeout
        while True:
            remain = deadline - time.monotonic()
            if remain <= 0:
                return None
            try:
                msg = json.loads(await asyncio.wait_for(self.ws.recv(), timeout=remain))
            except (asyncio.TimeoutError, TimeoutError):
                return None
            if msg.get("type") == "ack" and msg.get("command") == command:
                return msg

    async def hard_stop(self) -> None:
        """急停：950 硬停脉冲 → 1000 停止值（双保险，无视一切状态）。"""
        try:
            await self.cmd("servo", {"channel": self.ch, "pwm": HARD_STOP_PWM}, timeout=2)
            await asyncio.sleep(0.4)
            await self.cmd("servo", {"channel": self.ch, "pwm": STOP_PWM}, timeout=2)
            print("  [急停完成] 950 硬停脉冲已发，通道回 1000 停止值")
        except Exception as exc:  # noqa: BLE001
            print(f"  [急停发送异常] {exc} —— 请直接断泵电源！")

    async def countdown(self, seconds: int = 10) -> bool:
        """动作前倒计时；倒计时中按键=取消。返回 False 表示取消。"""
        print(f"  倒计时 {seconds} 秒（按回车立即开始，其它任意键取消）...")
        for remain in range(seconds, 0, -1):
            print(f"    {remain} ...")
            t0 = time.monotonic()
            while time.monotonic() - t0 < 1.0:
                if key_pressed():
                    import msvcrt
                    try:
                        k = msvcrt.getwch()
                    except Exception:  # noqa: BLE001
                        k = "\r"
                    if k in ("\r", "\n"):
                        print("    [跳过倒计时，立即开始]")
                        return True
                    print("    [已取消]")
                    return False
                await asyncio.sleep(0.05)
        return True

    async def run_test(self, target: int, hold_s: float) -> None:
        target = max(STOP_PWM, min(self.cap, int(target)))
        hold_s = min(hold_s, MAX_HOLD_S)
        print(f"=== 测试：{target}us × {hold_s:.1f}s（上限 {self.cap}）===")
        if not await self.countdown():
            return
        try:
            cur = STOP_PWM
            print("  爬升（任意键急停）...")
            while cur < target:
                cur = min(target, cur + RAMP_STEP)
                await self.cmd("servo", {"channel": self.ch, "pwm": cur})
                await asyncio.sleep(RAMP_INTERVAL)
                if key_pressed():
                    print("  !! 急停触发")
                    await self.hard_stop()
                    return
            print(f"  保持 {target}（任意键急停）...")
            t0 = time.monotonic()
            while time.monotonic() - t0 < hold_s:
                await asyncio.sleep(0.1)
                if key_pressed():
                    print("  !! 急停触发")
                    await self.hard_stop()
                    return
            print("  回落...")
            while cur > STOP_PWM:
                cur = max(STOP_PWM, cur - RAMP_STEP)
                await self.cmd("servo", {"channel": self.ch, "pwm": cur})
                await asyncio.sleep(RAMP_INTERVAL)
                if key_pressed():
                    print("  !! 急停触发")
                    await self.hard_stop()
                    return
            await self.hard_stop()
            print("=== 完成（已硬停）===")
        except Exception as exc:  # noqa: BLE001
            print(f"  !! 异常：{exc} —— 立即急停")
            await self.hard_stop()


async def main() -> int:
    parser = argparse.ArgumentParser(description="泵测试控制台（含急停）")
    parser.add_argument("--ws", default=DEFAULT_WS)
    parser.add_argument("--channel", type=int, default=DEFAULT_CHANNEL, help="泵通道（默认 13=AUX5）")
    parser.add_argument("--max", type=int, default=DEFAULT_CAP, help="PWM 安全上限（默认 1550）")
    parser.add_argument("--once", nargs=2, metavar=("PWM", "HOLD_S"), help="单次测试后退出")
    args = parser.parse_args()

    async with websockets.connect(args.ws, open_timeout=8) as ws:
        hello = json.loads(await asyncio.wait_for(ws.recv(), 8))
        print(f"已连接板卡网关：{hello.get('device')} v{hello.get('version')}")
        console = PumpConsole(ws, args.channel, args.max)
        await console.hard_stop()  # 启动即确保停止态

        if args.once:
            await console.run_test(int(args.once[0]), float(args.once[1]))
            await console.hard_stop()
            return 0

        print(
            f"\n泵测试台（通道 ch{args.channel}/AUX{args.channel-8}，上限 {args.max}）\n"
            "  输入 PWM 值测试（如 1425 或 1425 3）；s=急停；q=退出\n"
            "  动作期间按任意键立即急停（950 硬停）\n"
        )
        while True:
            try:
                line = input("泵> ").strip()
            except (EOFError, KeyboardInterrupt):
                print("\n退出 —— 先急停")
                await console.hard_stop()
                return 0
            if not line:
                continue
            if line in ("q", "quit", "exit"):
                await console.hard_stop()
                return 0
            if line in ("s", "stop", "e", "急停"):
                await console.hard_stop()
                continue
            parts = line.split()
            try:
                target = int(parts[0])
                hold = float(parts[1]) if len(parts) > 1 else 2.0
            except ValueError:
                print("  格式：PWM [保持秒数]，如 1425 2")
                continue
            if not STOP_PWM <= target <= 2000:
                print(f"  PWM 必须在 {STOP_PWM}-2000 之间")
                continue
            await console.run_test(target, hold)


if __name__ == "__main__":
    try:
        raise SystemExit(asyncio.run(main()))
    except KeyboardInterrupt:
        print("\nCtrl+C —— 已退出（退出前请确认泵已停，必要时断泵电源）")
        raise SystemExit(130)
