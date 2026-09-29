#!/bin/bash
# =====================================================================
# SeaUI 传感器超级查询（板卡上一键执行）
#   bash scripts/super_query.sh
# 覆盖：UART7/UART1 声纳（触发+被动）、1-Wire 双总线、I2C 全总线、网关遥测
# 输出末尾有 VERDICT 汇总，直接发给上位排查即可。
# =====================================================================
cd "$(dirname "$0")/.."

echo "===== [1/5] UART7 前视声纳（L08-V3.0 受控型：115200 + RX 拉低 40ms 触发） ====="
python3 scripts/l08_probe.py --port /dev/ttyS7 --rounds 4

echo "===== [2/5] UART1 下视声纳（L08-V3.0 受控型） ====="
python3 scripts/l08_probe.py --port /dev/ttyS1 --rounds 4

echo "===== [3/5] 1-Wire 双总线（DS18B20） ====="
for d in /sys/devices/w1_bus_master1 /sys/devices/w1_bus_master2; do
    echo "== $d slaves: $(cat $d/w1_master_slaves 2>/dev/null)"
done
if ls /sys/devices/w1_bus_master*/28-* >/dev/null 2>&1; then
    grep -H . /sys/devices/w1_bus_master*/28-*/w1_slave
fi

echo "===== [4/5] I2C 全总线（0x74/0x76/0x77/0x10 目标） ====="
python3 - <<'PYEOF'
import subprocess
WANT = {"0x74", "0x76", "0x77", "0x10"}
for bus in range(7):
    try:
        grid = subprocess.run(["i2cdetect", "-y", "-r", str(bus)],
                              capture_output=True, text=True, timeout=15).stdout
    except Exception as exc:
        print(f"bus {bus}: 扫描失败 {exc}")
        continue
    devs = []
    for line in grid.splitlines():
        if ":" not in line or len(line) < 10:
            continue
        prefix = line.split(":")[0].strip()
        for idx, cell in enumerate(line.split(":")[1].split()):
            if cell not in ("--", ""):
                devs.append(int(prefix, 16) + idx)
    hit = [f"0x{d:02x}" for d in devs if f"0x{d:02x}" in WANT]
    others = [f"0x{d:02x}" for d in devs if f"0x{d:02x}" not in WANT]
    msg = f"bus {bus}: 命中 {hit}" if hit else f"bus {bus}: 目标地址无应答"
    if others:
        msg += f"（其他设备 {others}）"
    print(msg)
PYEOF

echo "===== [5/5] 网关遥测快照 ====="
python3 - <<'PYEOF'
import asyncio, json, time
async def main():
    try:
        import websockets
    except ImportError:
        print("websockets 未安装"); return
    try:
        async with websockets.connect("ws://127.0.0.1:8080") as ws:
            await ws.recv()
            deadline = time.time() + 6
            while time.time() < deadline:
                m = json.loads(await asyncio.wait_for(ws.recv(), 3))
                if m.get("type") == "telemetry":
                    for k, v in m["sensors"].items():
                        print(f"  {k}: ok={v.get('ok')} {json.dumps(v.get('values', {}), ensure_ascii=False)[:80]} {str(v.get('message',''))[:50]}")
                    return
    except Exception as e:
        print(f"  网关未连上: {e}")
asyncio.run(main())
PYEOF

echo "===== 汇总 ====="
S1=$(ls /sys/devices/w1_bus_master*/28-* 2>/dev/null | wc -l)
echo "DS18B20 探头枚举数: $S1（应为 2）"
echo "声纳：见上方 [1][2] 的 VERDICT（TRIGGER_OK/RX_ACTIVE 为正常，回波 00 00 00 00 = 声纳未驱动 TX）"
