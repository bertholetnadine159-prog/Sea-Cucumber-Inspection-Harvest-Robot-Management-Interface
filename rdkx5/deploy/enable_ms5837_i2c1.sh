#!/bin/bash
# ⚠️ 已弃用（2026-09-29）：MS5837 已按板上实测迁移到 I2C5（3脚SDA/5脚SCL，bus 5，0x76），
# 见 rdkx5/config.yaml ms5837 注释与 docs/PINMAP.md §5.7。本脚本保留仅为历史记录；
# 板卡 /boot/config.txt 若仍有 dtoverlay=dtoverlay_ms5837_i2c1（占 32/33 垫作 I2C1），
# 经实机确认 bus5 应答后可移除该行停用旧方案。勿再执行本脚本开新部署。
# RDK X5 I2C1 使能（MS5837-30BA 深度计专用：40-pin 32脚=SCL、33脚=SDA，bus 1，地址 0x76/备用 0x77）
#
# 原理：i2c1 控制器默认已注册（/dev/i2c-1 存在），但 32/33 脚默认功能是
# PWM6/PWM7，pinmux 不切到 I2C 就永远扫不到设备（"隐藏"的 MS5837）。
# 本脚本动态探测 i2c1 节点路径，生成 overlay 挂上 pinctrl_i2c1 复用组
# （LSIO_I2C1_SCL/SDA），装入 /boot/overlays/ 并写 /boot/config.txt。
#
# 用法（板上 root 执行，完成后自动重启）：
#   sudo bash enable_ms5837_i2c1.sh
set -e

echo "== 1. 探测 i2c1 设备树节点 =="
NODE=""
for f in /proc/device-tree/__symbols__/i2c1 /proc/device-tree/__symbols__/*i2c1*; do
  [ -e "$f" ] || continue
  cand=$(tr -d '\0' < "$f")
  case "$cand" in
    */i2c@*) NODE="$cand"; echo "  符号 $(basename "$f") -> $cand"; break ;;
  esac
done
if [ -z "$NODE" ]; then
  NODE=$(tr -d '\0' < /proc/device-tree/aliases/i2c1 2>/dev/null || true)
  [ -n "$NODE" ] && echo "  aliases/i2c1 -> $NODE"
fi
if [ -z "$NODE" ]; then
  echo "未找到 i2c1 节点，请发回：ls /proc/device-tree/__symbols__ | grep i2c"
  exit 1
fi
echo "  i2c1 节点: $NODE"
echo "  当前 status: $(tr -d '\0' < "$NODE/status" 2>/dev/null || echo '无 status 属性(默认okay)')"

echo "== 2. 确认 pinctrl_i2c1 符号 =="
[ -e /proc/device-tree/__symbols__/pinctrl_i2c1 ] || { echo "无 pinctrl_i2c1 符号，无法继续"; exit 1; }
echo "  pinctrl_i2c1 -> $(tr -d '\0' < /proc/device-tree/__symbols__/pinctrl_i2c1)"

echo "== 3. 生成并安装 overlay =="
command -v dtc >/dev/null 2>&1 || apt-get install -y device-tree-compiler
DTS=/tmp/dtoverlay_ms5837_i2c1.dts
cat > "$DTS" <<EOF
/dts-v1/; /plugin/;
/ {
  fragment@0 {
    target-path = "$NODE";
    __overlay__ {
      pinctrl-names = "default";
      pinctrl-0 = <&pinctrl_i2c1>;
      status = "okay";
    };
  };
};
EOF
cat "$DTS"
dtc -q -@ -I dts -O dtb -o /boot/overlays/dtoverlay_ms5837_i2c1.dtbo "$DTS"
cp "$DTS" /boot/overlays/dtoverlay_ms5837_i2c1.dts

echo "== 4. 写入 /boot/config.txt =="
grep -q "^dtoverlay=dtoverlay_ms5837_i2c1" /boot/config.txt 2>/dev/null \
  || echo "dtoverlay=dtoverlay_ms5837_i2c1" >> /boot/config.txt
echo "config.txt 末尾："
tail -4 /boot/config.txt

echo "== 5. 重启生效（10 秒后重启，Ctrl+C 取消）=="
sync
sleep 10
reboot
