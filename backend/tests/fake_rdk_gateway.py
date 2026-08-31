"""本地回环测试用的假 RDK X5 网关：按 rdkx5/PROTOCOL.md 推送帧与遥测。"""

import asyncio
import base64
import json
import time

import cv2
import numpy as np
import websockets


def make_jpeg() -> bytes:
    frame = np.zeros((360, 640, 3), dtype=np.uint8)
    frame[:, :] = (60, 90, 40)
    cv2.putText(frame, "FAKE RDK X5", (20, 60), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (255, 255, 255), 3)
    ok, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 80])
    return buf.tobytes() if ok else b""


async def handler(websocket) -> None:
    await websocket.send(json.dumps({
        "type": "hello",
        "device": "fake_rdk_x5",
        "version": "test",
        "caps": ["video", "sensors", "pixhawk"],
    }))
    seq = 0
    async def pump() -> None:
        nonlocal seq
        while True:
            seq += 1
            await websocket.send(json.dumps({
                "type": "frame",
                "seq": seq,
                "ts": time.time(),
                "width": 640,
                "height": 360,
                "jpeg": base64.b64encode(make_jpeg()).decode(),
                "detections": [{"class_id": 0, "label": "sea_cucumber", "confidence": 0.92}],
                "inference_ms": 8.2,
                "fps": 15.0,
            }))
            if seq % 5 == 0:
                await websocket.send(json.dumps({
                    "type": "telemetry",
                    "ts": time.time(),
                    "sensors": {
                        "ms5837_depth": {"ok": True, "values": {"pressure_mbar": 1019.0, "temperature_c": 18.4, "depth_m": 0.51}},
                        "veml7700_front_light": {"ok": True, "values": {"lux": 173.0}},
                    },
                    "pixhawk": {"connected": True, "armed": False, "mode": "MANUAL", "battery_v": 12.4},
                    "link": {"fps": 15.0},
                }))
            await asyncio.sleep(0.1)

    task = asyncio.create_task(pump())
    try:
        async for raw in websocket:
            message = json.loads(raw)
            if message.get("type") == "command":
                await websocket.send(json.dumps({
                    "type": "ack",
                    "command": message.get("command"),
                    "success": True,
                }))
            elif message.get("type") == "get_telemetry":
                await websocket.send(json.dumps({
                    "type": "telemetry",
                    "ts": time.time(),
                    "sensors": {
                        "ms5837_depth": {"ok": True, "values": {"pressure_mbar": 1019.0, "temperature_c": 18.4, "depth_m": 0.51}},
                        "veml7700_front_light": {"ok": True, "values": {"lux": 173.0}},
                    },
                    "pixhawk": {"connected": True, "armed": False, "mode": "MANUAL", "battery_v": 12.4},
                    "link": {"fps": 15.0},
                }))
    finally:
        task.cancel()


async def main(port: int = 18080) -> None:
    async with websockets.serve(handler, "127.0.0.1", port):
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
