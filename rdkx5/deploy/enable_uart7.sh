#!/bin/bash
# RDK X5 UART7 使能（40-pin 11脚=TXD/GPIO17，13脚=RXD/GPIO27，3.3V 电平）
#
# 原理：本机固件没有现成的 uart7 overlay，基础设备树里 serial7 节点默认关闭。
# 本脚本在板上动态探测 serial7 的设备树节点路径与 pinmux 符号，生成
# dtoverlay_uart7.dtbo 装入 /boot/overlays/，并在 /boot/config.txt 加一行
# dtoverlay=dtoverlay_uart7（u-boot 的 boot.scr 会解析该文件应用 overlay）。
#
# 用法（板上 root 执行，完成后自动重启）：
#   sudo bash enable_uart7.sh
set -e

echo "== 1. 探测 serial7 设备树节点 =="
NODE=""
for f in /proc/device-tree/__symbols__/*uart7* /proc/device-tree/__symbols__/*serial7*; do
  [ -e "$f" ] || continue
  cand=$(tr -d '\0' < "$f")
  case "$cand" in
    */serial@*) NODE="$cand"; echo "  符号 $(basename "$f") -> $cand" ;;
  esac
done
if [ -z "$NODE" ]; then
  NODE=$(tr -d '\0' < /proc/device-tree/aliases/serial7 2>/dev/null || true)
  [ -n "$NODE" ] && echo "  aliases/serial7 -> $NODE"
fi
if [ -z "$NODE" ]; then
  echo "未找到 serial7 节点：请把下面两条命令的输出发回："
  echo "  ls /proc/device-tree/__symbols__ | grep -iE 'serial|uart'"
  echo "  cat /proc/device-tree/aliases/serial*"
  exit 1
fi
echo "  serial7 节点: $NODE"
echo "  当前 status: $(tr -d '\0' < "$NODE/status" 2>/dev/null || echo '无 status 属性')"
ALIAS_OK="no"
[ -e "/proc/device-tree/aliases/serial7" ] && ALIAS_OK="yes"
echo "  aliases/serial7 存在: $ALIAS_OK"

echo "== 2. 探测 uart7 pinmux 组符号 =="
PINCTRL_LABEL=""
for f in /proc/device-tree/__symbols__/*uart7*; do
  [ -e "$f" ] || continue
  name=$(basename "$f")
  path=$(tr -d '\0' < "$f")
  case "$path" in
    *pinctrl*|*pinmux*) PINCTRL_LABEL="$name"; echo "  pinmux 符号: $name -> $path" ;;
  esac
done
[ -n "$PINCTRL_LABEL" ] || echo "  (未找到 pinmux 符号，先只置 status=okay，端口打不开再迭代)"

echo "== 3. 生成并安装 overlay =="
command -v dtc >/dev/null 2>&1 || apt-get install -y device-tree-compiler
DTS=/tmp/dtoverlay_uart7.dts
{
  echo '/dts-v1/; /plugin/;'
  echo '/ {'
  echo '  fragment@0 { target-path = "'"$NODE"'"; __overlay__ { status = "okay"; }; };'
  if [ "$ALIAS_OK" = "no" ]; then
    echo '  fragment@1 { target-path = "/aliases"; __overlay__ { serial7 = "'"$NODE"'"; }; };'
    FRAG=2
  else
    FRAG=1
  fi
  if [ -n "$PINCTRL_LABEL" ]; then
    echo '  fragment@'"$FRAG"' { target-path = "'"$NODE"'"; __overlay__ { pinctrl-names = "default"; pinctrl-0 = <&'"$PINCTRL_LABEL"'>; }; };'
  fi
  echo '};'
} > "$DTS"
cat "$DTS"
dtc -q -@ -I dts -O dtb -o /boot/overlays/dtoverlay_uart7.dtbo "$DTS"
cp "$DTS" /boot/overlays/dtoverlay_uart7.dts

echo "== 4. 写入 /boot/config.txt =="
grep -q "^dtoverlay=dtoverlay_uart7" /boot/config.txt 2>/dev/null \
  || echo "dtoverlay=dtoverlay_uart7" >> /boot/config.txt
echo "config.txt 末尾："
tail -3 /boot/config.txt

echo "== 5. 重启生效（10 秒后重启，Ctrl+C 取消）=="
sync
sleep 10
reboot
