#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""网关遥测快照：直接连板上网关 WS，打印全部传感器状态。"""
import asyncio
import json


async def main():
    import websockets
    async with websockets.connect("ws://127.0.0.1:8080") as ws:
        await ws.recv()
        m = json.loads(await asyncio.wait_for(ws.recv(), 6))
        for k, v in m.get("sensors", {}).items():
            print(f"  {k}: ok={v.get('ok')} {json.dumps(v.get('values', {}), ensure_ascii=False)[:80]} {str(v.get('message', ''))[:60]}")


asyncio.run(main())
