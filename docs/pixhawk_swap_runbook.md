# Pixhawk 换飞控恢复手册（Sunrise5 / SeaUI）

> 背景：2026-09-29 现役 Pixhawk 2.4.8 克隆板（序列号 28004F000551333531353632）出现两处
> 板级缺陷——① IOMCU 参数掉电不保持（每次重启 SERVO5-8_FUNCTION 回默认 37-40，解锁后
> ArduSub 4.1 混控缺陷使垂推满推 1900）；② AUX 输出组自 boot#C 起永久失效（BRD_PWM_COUNT
> 读数正常但引脚无输出，跨重刷固件/全默认参数/冷启动断电均无法复活，泵 AUX5/6 不可用）。
> 网关已内置自愈（①每次连上重发功能位；②aux_output_active 遥测暴露②），主推不受影响。
> 用户决策（2026-09-29）：换飞控。

## 新飞控到手后操作（约 10 分钟，全部工具已入库）

> ⚠️ **第一课（2026-09-30 实测踩坑）：先辨板型再刷！** Pixhawk 2.4.8 有两种闪存版：
> - **FMUv3（2MB）**：Bootloader 报 `PX4_BL_FMU_v3.x`（bootloader rev 5）→ 用完整版固件；
> - **FMUv2（1MB）**：Bootloader 报 `PX4_BL_FMU_v2.x`（bootloader rev 4）→ **必须用 Pixhawk1-1M 版**（869KB）。
> 误把 1.27MB 完整版刷进 1MB 板：erase 后 program 失败、板子留在崩溃循环
> （USB 枚举层 error -110/-62，dmesg 可见），此时唯一解法 = **直连 PC 刷**：
>   python rdkx5/firmware/uploader.py --port <新COM> rdkx5/firmware/ardusub_410_pixhawk1_1m.apj
> （板卡 USB 集线器抓不到崩溃循环里的枚举窗口；直连 PC 通常可以。）

1. **接线**：新飞控插板卡 USB（网关 systemd 自启，3 秒内自动重连并 auto-arm）。
   ⚠️ 换飞控期间动力电（电调电源）保持断开。
2. **刷固件**（若新飞控出厂/旧机已有 ArduSub 4.1.0 可跳过）：
   ```
   python rdkx5/scripts/flash_ardusub_bootloader.py            # FMUv3 板
   python rdkx5/scripts/flash_ardusub_bootloader.py --board v2 # FMUv2/1MB 板
   ```
   （自动：停网关 → Bootloader 刷写 ArduSub 4.1.0 Pixhawk1 → 重启网关）
3. **恢复参数**（网关自愈会自动做大部分；保险起见再跑一遍落盘）：
   ```
   python rdkx5/scripts/restore_sub_params.py
   ```
   关键参数清单：SERVO5-8_FUNCTION=0（垂推直控）、SERVO9_FUNCTION=11（Lights1，
   保 AUX 组在出站包内）、SERVO13/14_FUNCTION=0（泵直控）、DISARM_DELAY=0、
   FRAME_CLASS=2、BRD_PWM_COUNT=6。
   注：SERVO5-8 属 IOMCU 参数——新飞控若存储正常则一次落盘永久保持；
   网关自愈（连上即重发）作为双保险始终存在。
4. **验证**（不转任何电机）：
   - `journalctl -u seaul-gateway -o cat | grep -E 'ensured|auto-arm done'`
   - 遥测（SeaUI 或 WS）：`motors_pwm=[1500×8]`、`armed=true`、`aux_output_active=true`
   - `aux_output_active=true` 即 AUX/泵通道恢复的直接判据。
5. **泵电调自校**：给泵电调上电（网关此时在发 1000 停止信号，上电自校抓对中点）。
6. **泵复测**（倒计时 10 秒流程）：
   `python rdkx5/scripts/test_all_motors.py`（全电机 20%）或单独泵测。
7. **主推联检**：MAIN1-4 混控（前进/转向小幅度）+ MAIN5-8 垂推，UI 或 motor_test 均可。

## 旧飞控故障定性（返厂/退换/报废依据）

- 现象：IOMCU 侧参数（SERVOx_FUNCTION）每次重启丢失；FMU AUX 输出组自某次重启后
  永久不激活（SERVO_OUTPUT_RAW 仅剩 port=0 的 8 字段）。
- 已排除：固件（重刷 ArduSub 4.1.0 Pixhawk1 无效）、参数（BRD_PWM_COUNT 改值/重写/
  延迟落盘均正确读回但引脚不激活）、供电（冷启动断电无效）、软件路径（disarm 后 246、
  刷机路径重启均试过）。
- 证据命令：`udevadm info -n /dev/ttyACM0`（身份）、`rdkx5/scripts/ch13_probe.py`
  （AUX 激活判定）、`rdkx5/scripts/pixhawk_param_tool.py --mode read`（参数）。

## 相关工具

| 工具 | 用途 |
|---|---|
| flash_ardusub_bootloader.py | Bootloader 重刷 ArduSub 4.1.0 |
| restore_sub_params.py | 恢复电机参数清单（WS correct_param） |
| test_all_motors.py | 全电机 20% 逐台测试（内置 10 秒倒计时） |
| ch13_probe.py | AUX 激活判定（板上运行） |
| board_control_diag.py | 板端链路一键诊断 |
| pixhawk_raw_probe.py | 串口/参数/伺服出站裸探针（板上运行） |
