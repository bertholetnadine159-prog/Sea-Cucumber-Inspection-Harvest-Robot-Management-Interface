#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""网关遥测快照：直接连板上网关 WS，打印全部传感器状态。

注意：网关连上即推 hello，随后混推 video frame 与 telemetry 两种消息——
必须循环过滤 type=="telemetry"，不能只取第一条（否则大概率拿到帧消息打印为空）。
"""
import asyncio
import json
import time


async def main():
    import websockets
    async with websockets.connect("ws://127.0.0.1:8080") as ws:
        await ws.recv()  # hello
        deadline = time.time() + 8
        while time.time() < deadline:
            m = json.loads(await asyncio.wait_for(ws.recv(), 4))
            if m.get("type") != "telemetry":
                continue
            print(f"telemetry ts={m.get('ts')}")
            for k, v in m.get("sensors", {}).items():
                print(f"  {k}: ok={v.get('ok')} {json.dumps(v.get('values', {}), ensure_ascii=False)[:80]} {str(v.get('message', ''))[:60]}")
            return
        print("(8s 内未等到 telemetry 消息)")


asyncio.run(main())
