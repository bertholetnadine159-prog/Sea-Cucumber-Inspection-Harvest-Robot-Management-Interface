# Pixhawk 输出无信号排查（推进器电调持续"滴——滴——滴"）

> 适用现象：软件侧全部正常（`motors_pwm=1500`、`sensors_health` 电机输出位已置位、
> `vservo_v≈4.5V`），但 8 个推进器电调都按"无信号"节奏报警（约每 2 秒一声）。

## 已确认的软件侧事实

- Pixhawk 固件 ArduSub，`FRAME_CONFIG=2`，MAIN1–8 均配置为 Motor1–8。
- `BRD_SAFETYENABLE=0`：安全开关不拦截输出。
- 上锁后 `surge=+0.5` 时，SERVO_OUTPUT_RAW 实测 MAIN1/2=1400、MAIN3/4=1600，stop 后回 1500。
- AUX4 直通 1500→1800→1200 的命令均返回 `COMMAND_ACK result=0`（已接受）。

## 软件侧已修复的缺陷（2026-08-15）

以下三个软件缺陷可能直接或间接导致 ESC 异响，已全部修复：

### 缺陷 1：`servo_pwm` 模式下发送无效 `DO_SET_SERVO`（channel=0, pwm=0）

**文件**：`rdkx5/pixhawk_link.py` → `_send_servo_pwm()`

原代码在设置各通道实际 PWM 之前，先发送了一个**全零**的
`MAV_CMD_DO_SET_SERVO` 命令（param1=0 即 channel=0，param2=0 即 pwm=0）。
channel=0 是非法通道号，Pixhawk 会返回 `MAV_RESULT_DENIED`，
但更严重的是某些 ArduSub 旧固件在收到非法 SERVO 命令后会出现短暂输出中断，
刚好让 ESC 捕获到"无信号"窗口。

**修复**：删除该全零命令，直接逐通道发送正确的 `DO_SET_SERVO`。

### 缺陷 2：吸捕单向电调收到 1500（"油门不在低位"报警）

**文件**：`rdkx5/pixhawk_link.py` → `emergency_stop()` / `arm()`

原代码 `emergency_stop` 对**所有**通道（包括 AUX5/AUX6 吸捕电机）都发送 1500。
但吸捕电机是**单向电调**，停止值是 1000；收到 1500 会触发持续快速"油门不在低位"报警。
虽然吸捕 ESC 与推进器 ESC 的报警节奏不同（快速连响 vs 每 2s 一声），
但大量异常 MAVLink 命令会干扰 Pixhawk 输出节拍。

**修复**：
- 新增 `initialize_escs()` 方法，按通道类型发送正确中性值：
  MAIN1–8 → 1500（双向推进器）、AUX5/AUX6 → 1000（单向吸捕电调）。
- `arm(enable=True)` 后自动调用 `initialize_escs()`。
- `emergency_stop` 改用 `initialize_escs()` 而非全通道 1500。
- `config.yaml` 新增 `suction_neutral_pwm: 1000` 配置项。

### 缺陷 3：`RC3_TRIM=1100` 异常值未自动修正

ArduSub 的 RC3（油门）trim 应为 1500（双向电调中性），
实测值为 1100，会导致混控输出不对称并可能触发 pilot input failsafe。

**修复**：新增 `verify_motor_config()` 方法，自动读取并报告以下关键参数：
`MOT_PWM_TYPE`、`BRD_PWM_COUNT`、`BRD_SAFETYENABLE`、`FRAME_CLASS`、
`DISARM_DELAY`、`RC3_TRIM`、`SERVO1-8_FUNCTION`，以及
SYS_STATUS 电机输出健康位。
新增 `correct_param()` 方法可通过 `correct_param` 命令远程修正参数。
新增 `init_escs` 和 `motor_diagnostic` 命令到网关。

## 诊断流程（更新后）

在板卡上运行网关后，通过 PC 端下发命令即可诊断，无需 SSH：

```bash
# 1. 读取所有电机参数并自动比对预期值
curl -X POST http://127.0.0.1:5000/api/command \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"command": "motor_diagnostic", "params": {}}'

# 2. 不解锁的情况下给所有 ESC 发送正确中性值（静音测试）
curl -X POST http://127.0.0.1:5000/api/command \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"command": "init_escs", "params": {}}'

# 3. 修正 RC3_TRIM（如有必要）
curl -X POST http://127.0.0.1:5000/api/command \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"command": "correct_param", "params": {"name": "RC3_TRIM", "value": 1500}}'
```

`motor_diagnostic` 返回示例：
```json
{
  "connected": true,
  "params": {
    "MOT_PWM_TYPE": {"value": 0, "expected": 0, "ok": true},
    "BRD_PWM_COUNT": {"value": 4, "expected": 4, "ok": true},
    "RC3_TRIM": {"value": 1100, "expected": 1500, "ok": false},
    "SERVO1_FUNCTION": {"value": 33, "expected": 33, "ok": true}
  },
  "issues": ["RC3_TRIM=1100 (expected 1500): RC3 (throttle) trim is not 1500..."]
}
```

## 第 1 步：AUX4 舵机判定（零改线）

用已接在 AUX4 的抓取舵机做参考：

1. 让软件发 `servo channel=11 pwm=1800`，再发 `1200`，观察舵机是否转动。
2. 结果分支：
   - **舵机动了** → Pixhawk 输出级正常，问题在推进器接线（见第 2 步）。
   - **舵机没动** → 输出级/舵机排供电问题（见第 3 步）。

## 第 2 步：推进器接线检查（舵机动的情况）

1. 确认电调信号线插在 **MAIN OUT 排（通常标 1–8 的下排）**，而不是“RC/输入”排。
2. 三根线顺序：信号（白/黄）在上、正极（红）在中间、地（黑/棕）在下；至少信号+地必须都接。
3. 确认电调电池地与 Pixhawk 地共地（用万用表导通档测电调地线与 Pixhawk GND）。
4. 逐路测试：把 1 号推进器电调信号线临时插到 **AUX4**（刚才舵机验证过的通道），
   软件发 1100/1500/1900，观察该电调是否从“无信号报警”变为正常并响应。

## 第 3 步：输出排电气检查（舵机没动的情况）

1. 万用表直流档：黑笔接 Pixhawk GND，红笔接 MAIN1 信号脚。1500 PWM 正常时平均值约
   `0.3V`；完全 0V 说明该排没有脉冲。
2. 检查舵机排供电：Pixhawk 2.4.8 的 MAIN/AUX 输出排需要外部 5V（或电调 BEC 供电）。
   即使 USB 给飞控供电，输出排也不一定有驱动能力；给舵机排中间脚接一个独立 5V BEC 再测。
3. 检查该板 IO 副处理器是否工作（重启时注意启动蜂鸣/黄灯状态）；必要时换一块 Pixhawk 交叉验证。

## 第 4 步：电调类型确认

- ArduSub 的推进器混控假设**双向电调**（1500=停、1100/1900=正反转）。
- 普通单向电调在 1500 上电会持续“油门不在低位”快速报警，且永远不会转动；
  若是单向电调，需要换成双向电调，或把控制方式改回直通 PWM 并单独做零油门初始化。
- 吸捕电机（AUX5/AUX6）是单向电调：停止值应为 1000，上电前先让软件发
  `suction power_percent=0`（输出 1000）再给吸捕电调供电，避免油门高位报警。

## 判定表

| 现象 | 结论 | 处理 |
| --- | --- | --- |
| AUX4 舵机不响应扫描 | 输出排无驱动 | 查舵机排 5V 供电 / IO 板 / 换板 |
| 舵机响应，但推进器仍无信号 | 推进器插错排或未共地 | 按第 2 步逐路迁移到 AUX4 验证 |
| 舵机响应，推进器插 AUX4 也动 | 原 MAIN1–8 对应接线有断路 | 检查排针/杜邦线/电调信号线 |
| 全部响应，但仍快速连响 | 电调是单向类型 | 更换双向电调或改直通 PWM 方案 |

## 待机异响根因与修复（2026-08-28）

### 根因

"待机会响"（每约 2 秒一声）是电调的 **无信号报警**：未解锁（disarmed）状态下，
ArduSub 会把 Motor 功能通道（MAIN1–4）的输出置为**无脉冲**，DO_SET_SERVO 也
改变不了 Motor 功能通道；电调收不到有效帧，就按"无信号"节奏报警。

此前的修复把静音建立在了"保持解锁"上（禁用 FS_PILOT_INPUT 自动上锁、
`DISARM_DELAY=0` 禁止自动 disarmed），但**上电后的待机阶段仍是未解锁状态**：
网关只在 `arm()` 与 `emergency_stop()` 时发一轮中性 PWM，飞控一上电、一重启，
MAIN1–4 就是无脉冲，电调必然报警，直到有人手动解锁。

### 软件修复（已在网关实现）

1. **自动解锁**（`config.yaml → pixhawk.auto_arm`，默认开启）：
   链路建立（含掉线重连）后自动 `ARM_DISARM(1, force=21196)`。
   无 RC 场景下解锁后中性输出不转桨，MAIN1–4 恢复 1500，报警即停。
   若要保留手动解锁流程，把 `auto_arm` 改为 `false`。
2. **待机 PWM 保活**（`pixhawk.standby_keepalive_s`，默认 1.0 秒，0 关闭）：
   周期重发各通道**最近一次命令值**（不是固定中性值），因此不会覆盖已下发的
   吸捕/舵机/垂推 PWM；覆盖未解锁、急停等没有持续控制流的阶段，防止任何一路
   输出断流后电调重新报警。
3. 顺序为：链路建立 → `initialize_escs()`（MAIN/AUX 全通道发正确中性值：
   MAIN 1500、吸捕 1000）→ 自动解锁 → 进入 1Hz 保活循环。

### 判别：报警 ≠ 电机故障

| 待机异响形态 | 含义 | 处理 |
| --- | --- | --- |
| 每约 2 秒一声 | 无信号/无脉冲 | 上述 auto_arm + keepalive，或手动解锁 |
| 快速连响（吸捕电机） | 单向电调收到 1500 | 确认 `suction_neutral_pwm: 1000` 已下发 |
| 解锁后中性仍有细微电流声 | 电调线性模式中性特性 | 硬件特性，用电调编程卡关"刹车/缓启动"，软件无法消除 |
| 舵机（AUX4）持续嗡嗡 | 舵机带载寻位 | 机械卸载或改为动作前再上电 |
