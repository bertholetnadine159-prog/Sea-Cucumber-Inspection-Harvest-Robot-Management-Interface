#!/bin/bash
# =====================================================================
# 1-Wire 总线电平诊断：解绑 w1-gpio → 读 DQ 电平 → 重绑
# 判定：稳定高电平=上拉在线（探头应能枚举）；稳定低电平=无上拉/对地短路
# 用法：bash scripts/w1_line_diag.sh
# =====================================================================
probe_bus() {
    local name="$1" dev="$2" soc="$3"
    echo "$dev" > /sys/bus/platform/drivers/w1-gpio/unbind 2>/dev/null
    sleep 0.3
    echo "$soc" > /sys/class/gpio/export 2>/dev/null
    echo "in" > "/sys/class/gpio/gpio$soc/direction" 2>/dev/null
    sleep 0.05
    v1=$(cat "/sys/class/gpio/gpio$soc/value" 2>/dev/null)
    sleep 0.3
    v2=$(cat "/sys/class/gpio/gpio$soc/value" 2>/dev/null)
    echo "$soc" > /sys/class/gpio/unexport 2>/dev/null
    echo "$dev" > /sys/bus/platform/drivers/w1-gpio/bind 2>/dev/null
    sleep 0.3
    if [ "$v1" = "1" ] && [ "$v2" = "1" ]; then
        echo "$name: 稳定高电平 —— 上拉在线、总线空闲正常（探头应能枚举）"
    elif [ "$v1" = "0" ] && [ "$v2" = "0" ]; then
        echo "$name: 稳定低电平 —— 无上拉 / DQ 对地短路 / 探头未接"
    else
        echo "$name: 电平波动 $v1->$v2 —— 线路浮空（无上拉）"
    fi
}

probe_bus "总线1（37脚，探头1，lsio线22/SOC401）" "onewire-0" "401"
probe_bus "总线2（15脚，探头2，lsio线9/SOC388）" "onewire-1" "388"

echo "slaves: master1=$(cat /sys/devices/w1_bus_master1/w1_master_slaves 2>/dev/null) | master2=$(cat /sys/devices/w1_bus_master2/w1_master_slaves 2>/dev/null)"
