#!/bin/bash
# 传感器状态监听：每 60s 记录一次四路状态到 /tmp/sensor_watch.log（保留最近 500 行）
# 用途：硬件接线/上电调试期间，自动记录"哪一刻起声纳有帧/探头被枚举"。
# 启动：nohup bash scripts/sensor_watch.sh >/dev/null 2>&1 &
# 停止：pkill -f sensor_watch.sh
while true; do
    TS=$(date "+%F %T")
    W1=$(ls /sys/devices/w1_bus_master*/28-* 2>/dev/null | wc -l)
    U7=$(timeout 4 python3 /home/sunrise/seaUI_rdk/scripts/uart_probe.py --port /dev/ttyS7 --trigger --hex --seconds 2 2>/dev/null | grep -cE "TRIGGER_OK|RX_ACTIVE")
    U1=$(timeout 4 python3 /home/sunrise/seaUI_rdk/scripts/uart_probe.py --port /dev/ttyS1 --trigger --hex --seconds 2 2>/dev/null | grep -cE "TRIGGER_OK|RX_ACTIVE")
    echo "$TS w1_probes=$W1 uart7_ok=$U7 uart1_ok=$U1" >> /tmp/sensor_watch.log
    tail -n 500 /tmp/sensor_watch.log > /tmp/sensor_watch.tmp 2>/dev/null && mv /tmp/sensor_watch.tmp /tmp/sensor_watch.log
    sleep 60
done
