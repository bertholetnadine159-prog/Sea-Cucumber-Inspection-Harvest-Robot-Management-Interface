#!/usr/bin/env python3
"""Test heave control: arm, send heave=0.5, verify MAIN5-8 change, then neutralize."""
import asyncio, json, time, websockets

async def main():
    uri = "ws://192.168.127.10:8080"
    async with websockets.connect(uri) as ws:
        print("[WS] connected")

        # Arm
        print("[TEST] arming...")
        await ws.send(json.dumps({"type": "command", "command": "arm", "params": {"force": True}}))
        await asyncio.sleep(2)

        # Read telemetry to confirm armed and neutral
        async def read_telem(timeout=1.0):
            deadline = time.time() + timeout
            while time.time() < deadline:
                try:
                    msg = await asyncio.wait_for(ws.recv(), timeout=0.3)
                    data = json.loads(msg)
                    if data.get("type") == "telemetry":
                        return data.get("pixhawk", {})
                except asyncio.TimeoutError:
                    pass
            return None

        px = await read_telem(2)
        if px:
            print(f"  armed={px.get('armed')} motors={px.get('motors_pwm')}")

        # Send heave=0.5 (up)
        print("[TEST] sending move heave=0.5 (up)...")
        await ws.send(json.dumps({
            "type": "command", "command": "move",
            "params": {"axes": {"surge": 0, "sway": 0, "heave": 0.5, "yaw": 0, "roll": 0, "pitch": 0}}
        }))
        await asyncio.sleep(1)

        px = await read_telem(2)
        if px:
            motors = px.get("motors_pwm")
            print(f"  heave=0.5: motors={motors}")
            if motors:
                expected = 1500 + int(0.5 * 400)  # 1700
                ch5_8 = motors[4:8]
                if all(abs(v - expected) <= 10 for v in ch5_8):
                    print(f"  MAIN5-8 = {ch5_8} (expected ~{expected}) - CORRECT!")
                else:
                    print(f"  MAIN5-8 = {ch5_8} (expected ~{expected}) - MISMATCH")

        # Stop
        print("[TEST] sending stop...")
        await ws.send(json.dumps({"type": "command", "command": "stop", "params": {}}))
        await asyncio.sleep(1)

        px = await read_telem(2)
        if px:
            motors = px.get("motors_pwm")
            print(f"  stop: motors={motors}")

        # Disarm
        print("[TEST] disarming...")
        await ws.send(json.dumps({"type": "command", "command": "disarm", "params": {"force": True}}))
        await asyncio.sleep(1)
        print("[TEST] done")

asyncio.run(main())
