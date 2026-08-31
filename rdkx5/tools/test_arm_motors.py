#!/usr/bin/env python3
"""Quick test: connect to RDK X5 gateway, arm Pixhawk, check motor PWM stays at 1500."""
import asyncio
import json
import time
import websockets


async def main():
    uri = "ws://192.168.127.10:8080"
    async with websockets.connect(uri) as ws:
        print("[WS] connected")

        # Collect telemetry for 2 seconds before arming
        print("[TEST] reading pre-arm telemetry...")
        pre_arm_motors = None
        deadline = time.time() + 2
        while time.time() < deadline:
            try:
                msg = await asyncio.wait_for(ws.recv(), timeout=0.5)
                data = json.loads(msg)
                if data.get("type") == "telemetry":
                    px = data.get("pixhawk", {})
                    pre_arm_motors = px.get("motors_pwm")
                    armed = px.get("armed")
                    mode = px.get("mode")
                    print(f"  pre-arm: armed={armed} mode={mode} motors={pre_arm_motors}")
            except asyncio.TimeoutError:
                pass

        # Arm
        print("[TEST] sending arm command (force=True)...")
        await ws.send(json.dumps({"type": "command", "command": "arm", "params": {"force": True}}))

        # Read acks and telemetry
        print("[TEST] reading post-arm telemetry (6s)...")
        post_arm_samples = []
        deadline = time.time() + 6
        while time.time() < deadline:
            try:
                msg = await asyncio.wait_for(ws.recv(), timeout=0.5)
                data = json.loads(msg)
                if data.get("type") == "telemetry":
                    px = data.get("pixhawk", {})
                    motors = px.get("motors_pwm")
                    aux = px.get("aux_pwm")
                    armed = px.get("armed")
                    post_arm_samples.append(motors)
                    if motors:
                        non_neutral = [i + 1 for i, v in enumerate(motors) if v != 1500]
                        print(f"  armed={armed} motors={motors} non-neutral={non_neutral} aux={aux}")
                elif data.get("type") == "ack":
                    print(f"  ack: {data}")
            except asyncio.TimeoutError:
                pass

        # Disarm
        print("[TEST] sending disarm command...")
        await ws.send(json.dumps({"type": "command", "command": "disarm", "params": {"force": True}}))
        try:
            msg = await asyncio.wait_for(ws.recv(), timeout=3)
            print(f"  disarm ack: {json.loads(msg)}")
        except Exception:
            pass

        # Summary
        print()
        print("=== SUMMARY ===")
        print(f"Pre-arm motors:  {pre_arm_motors}")
        if post_arm_samples:
            last = post_arm_samples[-1]
            print(f"Post-arm motors: {last}")
            non_neutral = [i + 1 for i, v in enumerate(last) if v != 1500]
            if non_neutral:
                print(f"WARNING: channels {non_neutral} are NOT at 1500 neutral!")
                for i, v in enumerate(last):
                    if v != 1500:
                        print(f"  MAIN{i + 1} = {v}")
            else:
                print("All 8 motors at 1500 neutral - GOOD")
        else:
            print("No post-arm telemetry received")


if __name__ == "__main__":
    asyncio.run(main())
