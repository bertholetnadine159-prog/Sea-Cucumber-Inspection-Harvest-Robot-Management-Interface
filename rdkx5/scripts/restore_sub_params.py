#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""飞控重刷后按既定清单恢复电机参数（经板上网关 WS correct_param）。

背景：ArduSub 4.1.0 重刷后参数回固件默认——SERVO5-8_FUNCTION=37-40（Motor5-8），
导致 DO_SET_SERVO 5-8 全被拒（"Channel already in use"）、垂推失控。
本脚本按 2026-09-22 真机验证过的清单纠正：

  SERVO5_FUNCTION=0 SERVO6_FUNCTION=0 SERVO7_FUNCTION=0 SERVO8_FUNCTION=0
  DISARM_DELAY=0    FRAME_CLASS=2      BRD_PWM_COUNT=6

注：BRD_PWM_COUNT 写入后需飞控断电重启才生效（AUX5/6 泵通道），
MAVLink 重启命令在此克隆板上无效，需人工拔插 Pixhawk USB。
随后跑 motor_diagnostic 读回全部关键参数核对。

安全：只写参数，不发任何电机转动指令。
"""

from __future__ import annotations

import argparse
import asyncio
import json

import websockets

DEFAULT_WS = "ws://192.168.5.127:8080"

# (param, value, 备注)
PARAM_PLAN = [
    ("SERVO5_FUNCTION", 0, "垂推通道直控（默认 37=Motor5 会吞掉 DO_SET_SERVO）"),
    ("SERVO6_FUNCTION", 0, "同上"),
    ("SERVO7_FUNCTION", 0, "同上"),
    ("SERVO8_FUNCTION", 0, "同上"),
    ("DISARM_DELAY", 0, "禁止自动上锁（解锁待机静音方案依赖）"),
    ("FRAME_CLASS", 2, "ROV 向量 8 推构型"),
    ("BRD_PWM_COUNT", 6, "AUX5/6 泵 PWM（需飞控断电重启生效）"),
]


async def send_command(ws, command: str, params: dict, wait_ack_s: float = 8.0) -> dict:
    await ws.send(json.dumps({"type": "command", "command": command, "params": params}))
    deadline = asyncio.get_event_loop().time() + wait_ack_s
    while True:
        remaining = deadline - asyncio.get_event_loop().time()
        if remaining <= 0:
            return {"type": "ack", "command": command, "success": False, "message": "ack timeout"}
        message = json.loads(await asyncio.wait_for(ws.recv(), timeout=remaining))
        if message.get("type") == "ack" and message.get("command") == command:
            return message
        # 其余消息（遥测推送/hello）忽略


async def main() -> int:
    parser = argparse.ArgumentParser(description="恢复 ArduSub 电机参数")
    parser.add_argument("--ws", default=DEFAULT_WS)
    args = parser.parse_args()

    async with websockets.connect(args.ws, open_timeout=8) as ws:
        hello = json.loads(await asyncio.wait_for(ws.recv(), timeout=8))
        print(f"[ws] hello: device={hello.get('device')} version={hello.get('version')}")

        print("===== 写入参数 =====")
        all_ok = True
        for name, value, note in PARAM_PLAN:
            ack = await send_command(ws, "correct_param", {"name": name, "value": value})
            ok = bool(ack.get("success"))
            all_ok = all_ok and ok
            print(f"  {name}={value} -> success={ok}  # {note}")

        print("===== motor_diagnostic 读回核对 =====")
        ack = await send_command(ws, "motor_diagnostic", {})
        diag = ack.get("diagnostic")
        if isinstance(diag, dict):
            print(json.dumps(diag, ensure_ascii=False, indent=2))
        else:
            print(f"  diagnostic unavailable: {ack}")

        print(f"===== RESULT: params_writes={'ALL_OK' if all_ok else 'SOME_FAILED'} =====")
        return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
