#!/usr/bin/env python3
"""Test heave control v2: arm, wait for armed=True, then send heave."""
import asyncio, json, time, websockets

async def main():
    uri = "ws://192.168.127.10:8080"
    async with websockets.connect(uri) as ws:
        print("[WS] connected")

        async def drain_and_get_telem(timeout=1.0):
            """Read messages, return latest telemetry."""
            latest = None
            deadline = time.time() + timeout
            while time.time() < deadline:
                try:
                    msg = await asyncio.wait_for(ws.recv(), timeout=0.3)
                    data = json.loads(msg)
                    if data.get("type") == "telemetry":
                        latest = data.get("pixhawk", {})
                    elif data.get("type") == "ack":
                        print(f"  ack: {data}")
                except asyncio.TimeoutError:
                    pass
            return latest

        # Wait for initial telemetry
        px = await drain_and_get_telem(2)
        if px:
            print(f"  initial: armed={px.get('armed')} motors={px.get('motors_pwm')}")

        # Arm
        print("[TEST] arming...")
        await ws.send(json.dumps({"type": "command", "command": "arm", "params": {"force": True}}))

        # Wait for armed=True
        armed = False
        deadline = time.time() + 5
        while time.time() < deadline:
            px = await drain_and_get_telem(1)
            if px:
                armed = px.get("armed")
                print(f"  armed={armed} motors={px.get('motors_pwm')}")
                if armed:
                    break

        if not armed:
            print("  WARNING: did not achieve armed=True, continuing anyway")

        # Send heave=0.5
        print("[TEST] sending heave=0.5 (up)...")
        await ws.send(json.dumps({
            "type": "command", "command": "move",
            "params": {"axes": {"surge": 0, "sway": 0, "heave": 0.5, "yaw": 0, "roll": 0, "pitch": 0}}
        }))
        await asyncio.sleep(1)
        px = await drain_and_get_telem(2)
        if px:
            motors = px.get("motors_pwm")
            print(f"  heave=0.5: motors={motors}")
            if motors:
                expected = 1500 + int(0.5 * 400)
                ch5_8 = motors[4:8]
                print(f"  MAIN5-8 = {ch5_8} (expected ~{expected})")

        # Send heave=-0.5
        print("[TEST] sending heave=-0.5 (down)...")
        await ws.send(json.dumps({
            "type": "command", "command": "move",
            "params": {"axes": {"surge": 0, "sway": 0, "heave": -0.5, "yaw": 0, "roll": 0, "pitch": 0}}
        }))
        await asyncio.sleep(1)
        px = await drain_and_get_telem(2)
        if px:
            motors = px.get("motors_pwm")
            print(f"  heave=-0.5: motors={motors}")

        # Stop
        print("[TEST] stop...")
        await ws.send(json.dumps({"type": "command", "command": "stop", "params": {}}))
        await asyncio.sleep(1)
        px = await drain_and_get_telem(2)
        if px:
            print(f"  stop: motors={px.get('motors_pwm')}")

        # Disarm
        print("[TEST] disarm...")
        await ws.send(json.dumps({"type": "command", "command": "disarm", "params": {"force": True}}))
        await asyncio.sleep(1)
        print("[TEST] done")

asyncio.run(main())
