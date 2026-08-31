#!/usr/bin/env python3
"""Full end-to-end test: arm, send heave, verify MAIN5-8 change, stop, disarm."""
import asyncio, json, time, websockets

async def main():
    uri = "ws://192.168.127.10:8080"
    async with websockets.connect(uri) as ws:
        print("[WS] connected")

        async def read_telem(timeout=1.0):
            latest = None
            deadline = time.time() + timeout
            while time.time() < deadline:
                try:
                    msg = await asyncio.wait_for(ws.recv(), timeout=0.3)
                    data = json.loads(msg)
                    if data.get("type") == "telemetry":
                        latest = data.get("pixhawk", {})
                    elif data.get("type") == "ack":
                        print(f"  ack: cmd={data.get('command')} success={data.get('success')}")
                except asyncio.TimeoutError:
                    pass
            return latest

        # Wait for initial telemetry
        px = await read_telem(2)
        if px:
            print(f"  initial: armed={px.get('armed')} motors={px.get('motors_pwm')}")

        # Arm
        print("[1] ARM")
        await ws.send(json.dumps({"type": "command", "command": "arm", "params": {"force": True}}))
        # Wait for armed=True
        for _ in range(5):
            px = await read_telem(1)
            if px and px.get("armed"):
                print(f"  armed=True motors={px.get('motors_pwm')}")
                break

        # Send heave=0.5 continuously for 3 seconds
        print("[2] SEND heave=0.5 (up) continuously for 3s")
        deadline = time.time() + 3
        while time.time() < deadline:
            await ws.send(json.dumps({
                "type": "command", "command": "move",
                "params": {"axes": {"surge": 0, "sway": 0, "heave": 0.5, "yaw": 0, "roll": 0, "pitch": 0}}
            }))
            px = await read_telem(0.3)
            if px:
                motors = px.get("motors_pwm")
                if motors:
                    ch5_8 = motors[4:8]
                    print(f"  motors={motors}  MAIN5-8={ch5_8}")

        # Stop
        print("[3] STOP")
        await ws.send(json.dumps({"type": "command", "command": "stop", "params": {}}))
        px = await read_telem(1)
        if px:
            print(f"  motors={px.get('motors_pwm')}")

        # Disarm
        print("[4] DISARM")
        await ws.send(json.dumps({"type": "command", "command": "disarm", "params": {"force": True}}))
        await asyncio.sleep(1)
        print("[DONE]")

asyncio.run(main())
