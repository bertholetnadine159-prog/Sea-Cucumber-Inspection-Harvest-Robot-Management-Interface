#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""全电机逐台测试（PC 侧，经板上网关 WS motor_test）。

用户约束（2026-09-29）：测试转速上限 20%。
  主推（双向，1500 中性）：20% = 1660us（约定 1580us=10%，80us/10%）
  泵（单向，1000=停，量程 1000-2000）：20% = 1200us

MAIN1-4 为混控通道（SERVO1-4_FUNCTION=33-36，DO_SET_SERVO 会被拒）：
先翻 0 → 逐台测试 → 无论成败必须恢复 33/34/35/36。
MAIN5-8 / 泵 13/14 功能位已是 0，直接测。

每个通道：发 motor_test（3s 窗口，网关 4Hz 重发、结束自动回停止值），
窗口中段采样遥测 SERVO_OUTPUT_RAW，记录该通道实际输出 PWM 作为
"飞控真的在输出"的证据（物理转动由用户现场目视确认）。
"""

from __future__ import annotations

import argparse
import asyncio
import json
import time

import websockets

DEFAULT_WS = "ws://192.168.5.127:8080"
MAIN_PWM_20PCT = 1660
PUMP_PWM_20PCT = 1200
TEST_SECONDS = 3.0

# (channel, pwm, 标签)
MAIN_1_4 = [(c, MAIN_PWM_20PCT, f"MAIN{c}（水平）") for c in (1, 2, 3, 4)]
MAIN_5_8 = [(c, MAIN_PWM_20PCT, f"MAIN{c}（垂直）") for c in (5, 6, 7, 8)]
PUMPS = [(13, PUMP_PWM_20PCT, "泵1（AUX5/ch13）"), (14, PUMP_PWM_20PCT, "泵2（AUX6/ch14）")]
SERVO_FUNCTION_RESTORE = {1: 33, 2: 34, 3: 35, 4: 36}


class GatewayClient:
    def __init__(self, uri: str) -> None:
        self.uri = uri
        self.ws = None
        self.latest_telemetry: dict | None = None

    async def connect(self) -> None:
        self.ws = await websockets.connect(self.uri, open_timeout=8)
        hello = json.loads(await asyncio.wait_for(self.ws.recv(), 8))
        print(f"[ws] hello: {hello.get('device')} v{hello.get('version')}")

    async def command(self, command: str, params: dict, timeout: float = 8.0) -> dict:
        await self.ws.send(json.dumps({"type": "command", "command": command, "params": params}))
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return {"success": False, "message": "ack timeout"}
            message = json.loads(await asyncio.wait_for(self.ws.recv(), timeout=remaining))
            if message.get("type") == "telemetry":
                self.latest_telemetry = message.get("data", message)
                continue
            if message.get("type") == "ack" and message.get("command") == command:
                return message

    async def pump_telemetry(self, seconds: float) -> None:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            try:
                message = json.loads(await asyncio.wait_for(self.ws.recv(), timeout=deadline - time.monotonic()))
            except (asyncio.TimeoutError, TimeoutError):
                return
            if message.get("type") == "telemetry":
                self.latest_telemetry = message.get("data", message)

    def channel_pwm(self, channel: int) -> int | None:
        data = self.latest_telemetry or {}
        pix = data.get("pixhawk") or data
        motors = pix.get("motors_pwm") or []
        aux = pix.get("aux_pwm") or []
        if 1 <= channel <= 8 and len(motors) >= channel:
            return int(motors[channel - 1])
        if channel >= 9 and len(aux) >= channel - 8:
            return int(aux[channel - 9])
        return None


async def main() -> int:
    parser = argparse.ArgumentParser(description="全电机逐台测试（20% 上限）")
    parser.add_argument("--ws", default=DEFAULT_WS)
    parser.add_argument("--seconds", type=float, default=TEST_SECONDS)
    args = parser.parse_args()

    client = GatewayClient(args.ws)
    await client.connect()

    # ---------- 预检 ----------
    await client.pump_telemetry(2.5)
    pix = (client.latest_telemetry or {}).get("pixhawk") or client.latest_telemetry or {}
    connected = pix.get("connected")
    armed = pix.get("armed")
    print(f"[preflight] pixhawk connected={connected} armed={armed} mode={pix.get('mode')}")
    if not connected:
        print("[abort] 飞控未连接，拒绝测试")
        return 2
    if not armed:
        ack = await client.command("arm", {"force": False})
        print(f"[preflight] 解锁: {ack.get('success')}")
        await asyncio.sleep(1.5)
        await client.pump_telemetry(1.0)
        pix = (client.latest_telemetry or {}).get("pixhawk") or {}
        print(f"[preflight] armed={pix.get('armed')}")

    plan = MAIN_1_4 + MAIN_5_8 + PUMPS
    print("=" * 62)
    print("即将逐台转动以下电机（转速 20%，每台 3 秒）:")
    for channel, pwm, label in plan:
        print(f"  ch{channel:<2d} {label:<16s} 目标 {pwm}us")
    print("=" * 62)
    for remain in range(10, 0, -1):
        print(f"  倒计时 {remain} ...")
        await asyncio.sleep(1.0)
    print(">>> 开始测试 <<<")

    results: list[dict] = []
    try:
        # ---------- 阶段 A：MAIN1-4 翻功能位 ----------
        print("\n[A] 临时 SERVO1-4_FUNCTION -> 0（混控通道让位直控）")
        for ch in (1, 2, 3, 4):
            ack = await client.command("correct_param", {"name": f"SERVO{ch}_FUNCTION", "value": 0})
            print(f"    SERVO{ch}_FUNCTION=0 success={ack.get('success')}")
        await asyncio.sleep(0.5)

        for channel, pwm, label in MAIN_1_4:
            results.append(await test_one(client, channel, pwm, label, args.seconds))

        # ---------- 阶段 A 收尾：必须恢复功能位 ----------
        print("\n[A] 恢复 SERVO1-4_FUNCTION -> 33/34/35/36（混控）")
        for ch, value in SERVO_FUNCTION_RESTORE.items():
            ack = await client.command("correct_param", {"name": f"SERVO{ch}_FUNCTION", "value": value})
            print(f"    SERVO{ch}_FUNCTION={value} success={ack.get('success')}")
        await asyncio.sleep(0.5)

        # ---------- 阶段 B/C ----------
        for channel, pwm, label in MAIN_5_8 + PUMPS:
            results.append(await test_one(client, channel, pwm, label, args.seconds))
    finally:
        # 兜底：任何异常也要恢复功能位（幂等）
        try:
            for ch, value in SERVO_FUNCTION_RESTORE.items():
                await client.command("correct_param", {"name": f"SERVO{ch}_FUNCTION", "value": value})
        except Exception as exc:  # noqa: BLE001
            print(f"[finally] 功能位恢复失败（需手动）: {exc}")

    # ---------- 汇总 ----------
    print("\n===== 结果汇总（20% 转速） =====")
    print(f"{'通道':<6}{'标签':<18}{'目标':>6}{'实测输出':>10}{'判定':>8}")
    for row in results:
        observed = row["observed"]
        if observed is None:
            verdict = "无遥测"
        elif abs(observed - row["pwm"]) <= 30 or abs(observed - row["stop"]) <= 30:
            # 窗口内至少出现过目标值附近才算确认输出；回中值=窗口已结束
            verdict = "已输出" if abs(observed - row["pwm"]) <= 30 else "疑似过晚"
        else:
            verdict = f"异常({observed})"
        print(f"ch{row['channel']:<4}{row['label']:<18}{row['pwm']:>6}{str(observed):>10}{verdict:>8}")
    print("\n注：实测输出=窗口中段遥测 SERVO_OUTPUT_RAW 值；物理转动请以现场目视为准。")
    return 0


async def test_one(client: GatewayClient, channel: int, pwm: int, label: str, seconds: float) -> dict:
    stop = 1000 if channel in (13, 14) else 1500
    ack = await client.command("motor_test", {"channel": channel, "pwm": pwm, "duration_s": seconds})
    ok = bool(ack.get("success"))
    print(f"\n[ch{channel}] {label} 目标 {pwm}us x {seconds:.0f}s ack={ok}")
    # 窗口中段多次采样取该通道最大读数（避免单帧错过）
    observed = None
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline - 0.4:
        await client.pump_telemetry(0.35)
        value = client.channel_pwm(channel)
        if value is not None and (observed is None or abs(value - pwm) < abs(observed - pwm)):
            observed = value
    print(f"    遥测输出={observed}us")
    # 等窗口收尾（网关自动恢复停止值）
    await asyncio.sleep(0.6)
    return {"channel": channel, "label": label, "pwm": pwm, "stop": stop, "observed": observed, "ack": ok}


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
