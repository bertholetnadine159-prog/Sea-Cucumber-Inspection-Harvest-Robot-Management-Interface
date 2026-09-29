#!/bin/bash
# 在 RDK X5 板上执行：编译并启用双路 1-Wire overlay（DS18B20 两路独立总线）
# 用法：把整个 deploy/ 目录同步到板上后，sudo bash setup_1wire.sh && sudo reboot
set -e
cd "$(dirname "$0")"

command -v dtc >/dev/null 2>&1 || apt-get install -y device-tree-compiler

dtc -q -@ -I dts -O dtb -o dtoverlay_1_wire.dtbo dtoverlay_1_wire.dts
cp dtoverlay_1_wire.dtbo /boot/overlays/
grep -q "dtoverlay_1_wire" /boot/config.txt 2>/dev/null \
  || echo "dtoverlay=dtoverlay_1_wire" >> /boot/config.txt

# w1-gpio/w1-therm 内核模块开机自动加载（否则 overlay 应用了也不会出现 w1_bus_master）
printf 'w1_gpio\nw1_therm\n' > /etc/modules-load.d/w1.conf
modprobe w1_gpio 2>/dev/null || true
modprobe w1_therm 2>/dev/null || true

echo "overlay 已安装。sudo reboot 后验证："
echo "  ls /sys/devices/w1_bus_master1/   # 应有 28-xxx（探头1，40-pin 37脚=lsio线22/SOC401）"
echo "  ls /sys/devices/w1_bus_master2/   # 应有 28-xxx（探头2，40-pin 15脚=lsio线9/SOC388）"
echo "  cat /sys/devices/w1_bus_master*/28-*/w1_slave   # 末行 t=xxxx 即温度"
