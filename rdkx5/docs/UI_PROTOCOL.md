# SeaUI UI 通信协议（PC ↔ Flutter WS，RDK X5 网关实现）

> 本文以代码实际行为为准，事实源：`rdkx5/stream_server.py`、`rdkx5/vision.py`、
> `rdkx5/pixhawk_link.py`、`rdkx5/sensors.py`（更新日期：2026-09-19，对应网关版本 2.0.0）。
> 传输层：WebSocket，JSON 文本帧，默认 `ws://<rdk_ip>:8080`（`config.yaml -> server` 段可改）。
> PC 端后端连接本协议后向 Flutter 转发，`frame`/`telemetry`/`ack` 字段保持一致。

## 1. 连接与握手

PC 连上后网关立即推送一条 `hello`，随后网关主动持续推送 `frame` 与 `telemetry`；
PC 随时可发上行命令，每条命令恰好收到一条 `ack`。

```json
{
  "type": "hello",
  "device": "rdk_x5",
  "version": "2.0.0",
  "caps": ["video", "sensors", "pixhawk"],
  "cameras": ["camera_1", "camera_2"]
}
```

## 2. 下行消息

### 2.1 `frame`（视频帧，按活动摄像头 fps 推送）

```json
{
  "type": "frame",
  "seq": 1024,
  "ts": 1789123456.123,
  "sent_ts": 1789123456.125,
  "camera_id": "camera_1",
  "width": 1280,
  "height": 720,
  "jpeg": "<base64>",
  "detections": [
    {"class_id": 0, "label": "sea_cucumber", "confidence": 0.83,
     "x": 512, "y": 300, "width": 96, "height": 54}
  ],
  "inference_ms": 18.5,
  "fps": 14.9
}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `seq` | int | 帧序号，单调递增，用于去重 |
| `ts` | float | **帧采集时刻**（epoch 秒） |
| `sent_ts` | float | **网关发送时刻**（epoch 秒，消息出站序列化瞬间取值） |
| `camera_id` | str | 采集来源摄像头（`camera_1` 前视 / `camera_2` 吸口近距） |
| `width`/`height` | int | 实际编码分辨率（像素），受 `set_video` 热更新影响 |
| `jpeg` | str | 标注后 JPEG 的 base64（含检测框/掩膜渲染） |
| `detections` | array | BPU YOLO11 分割结果；无模型/无检出时为 `[]` |
| `detections[].x/y/width/height` | int | 目标框，像素坐标（无框时省略该组字段） |
| `inference_ms` | float | BPU 推理耗时（毫秒） |
| `fps` | float | 实际推流帧率（EMA 平滑） |

**端到端时延口径**：`时延 ≈ (接收时刻 − sent_ts)`，单位秒，乘 1000 得毫秒。
`接收时刻`取后端转发时刻或前端接收时刻（本地 `Date.now()/1000` 等 epoch 秒时钟，
要求收发两端 NTP 对时）。UI 标注为"≈链路时延"。同一帧内 `ts ≤ sent_ts`，
`sent_ts − ts` 即网关内部采集→发送的排队/编码耗时，可用于区分板内时延与链路时延。

### 2.2 `telemetry`（遥测，默认 5Hz，`config.yaml -> telemetry.hz`）

```json
{
  "type": "telemetry",
  "ts": 1789123456.200,
  "sensors": { "...": "见 2.2.1" },
  "pixhawk": { "...": "见 2.2.2" },
  "link": {"fps": 14.9}
}
```

#### 2.2.1 `sensors`（每项：`ok` 是否读到、`values` 数值、`message` 失败原因）

| 键 | values 字段 |
| --- | --- |
| `veml7700_front_light` | `lux`, `als_raw`, `white_raw` |
| `veml7700_down_light` | `lux`, `als_raw`, `white_raw` |
| `ms5837_depth` | `pressure_mbar`(mbar), `temperature_c`(°C), `depth_m`(m) |
| `ds18b20_water_1` | `temperature_c`(°C) |
| `ds18b20_water_2` | `temperature_c`(°C) |
| `ultrasonic_front_suction_mouth` | `distance_m`(m)（实机另有 `protocol:"ff_uart"`） |
| `ultrasonic_downward_altitude` | `distance_m`(m)（同上） |

```json
{
  "ms5837_depth": {"ok": true, "values": {"pressure_mbar": 1021.4, "temperature_c": 18.6, "depth_m": 0.42}, "message": ""}
}
```

#### 2.2.2 `pixhawk`（全字段，来源 `pixhawk_link.Telemetry.to_dict`）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `connected` | bool | MAVLink 链路是否建立（心跳超时自动置 false） |
| `armed` | bool | 解锁状态 |
| `mode` | str | 飞控模式（如 `MANUAL`） |
| `battery_v` | float \| null | 电池电压（V，SYS_STATUS） |
| `battery_remaining` | int \| null | 电池余量（%） |
| `attitude_deg` | object | `{roll, pitch, yaw}`（ATTITUDE 原始值，弧度） |
| `alt_m` | float \| null | 深度/高度（m，VFR_HUD.alt） |
| `motors_pwm` | int[8] | MAIN1-8 输出 PWM（µs，SERVO_OUTPUT_RAW servo1-8） |
| `aux_pwm` | int[8] | AUX1-8 输出 PWM（µs，servo9-16；吸捕/舵机/灯在此） |
| `vcc_v` | float \| null | 飞控供电电压（V，POWER_STATUS.Vcc） |
| `vservo_v` | float \| null | 舵机供电电压（V，POWER_STATUS.Vservo） |
| `sensors_health` | int | 板载传感器健康位掩码（SYS_STATUS.onboard_control_sensors_health） |

### 2.3 `ack`（命令应答；错误语义）

每条上行命令回一条。**本协议没有独立的 `error` 消息类型，错误一律用
`ack.success=false` + `message` 表达**：

```json
{"type": "ack", "command": "set_mode", "success": false, "message": "Unknown Pixhawk mode: FOO"}
```

- 成功：`success=true`，可携带命令相关附加字段（各命令见 §3）；
- 失败：`success=false` + `message`（参数越界/目标不存在/硬件异常/未知命令）；
- 未知命令：`{"command": "<原命令>", "success": false, "message": "unknown command: <原命令>"}`；
- 非法 JSON：`{"type":"ack","command":"?","success":false,"message":"invalid json"}`；
- 未知消息类型：`command` 回退为原 `type`，`success=false`。

## 3. 上行命令

除注明外均为 `{"type": "command", "command": "<名>", "params": {...}}`。

| command | params | 成功 ack 附加字段 | 行为 |
| --- | --- | --- | --- |
| `move` | `axes{surge,sway,heave,roll,pitch,yaw}`（[-1,1]），`deadman_ms`（默认 1000） | — | 设置 6 自由度速度 + 刷新看门狗；超时自动回中 |
| `stop` | — | — | 立即回中 |
| `arm` / `disarm` | `force`（bool，默认 false） | — | 解锁/上锁 Pixhawk；`arm` 后自动初始化 ESC 中性值 |
| `set_mode` | `mode`（str，必填） | — | 切换飞控模式 |
| `set_camera` | `camera_id`（`camera_1`/`camera_2`） | `camera_id`（实际激活值） | 切换活动摄像头；未知 id 回失败 ack |
| `suction` | `power_percent`（0-100，越界截断） | `pwm` | 吸捕电机 PWM = 1000 + percent×10，写到吸捕通道 |
| `servo` | `channel`（默认配置舵机通道），`pwm`（默认 1500） | — | 直通 PWM |
| `light_on` / `light_off` | — | `on` | 灯通道 PWM 1900/1100 |
| `sonar_on` / `sonar_off` | — | `on` | 声呐开关（状态标志） |
| `laser_on` / `laser_off` | — | `on` | 激光定位开关（状态标志） |
| `auto_cruise` | `enabled`（bool，默认 false） | `enabled` | 自动巡航开关 |
| `snapshot` | — | `path` | 把最近一帧 JPEG 存到 `rdkx5/snapshots/rdk_<秒>.jpg`；无帧回失败 |
| `emergency_stop` | — | — | 立即回中；`safety.emergency_stop_disarm=true` 时同时上锁 |
| `init_escs` | — | — | 向 MAIN5-8/AUX9-16 发送正确中性 PWM |
| `motor_diagnostic` | — | `diagnostic` | 逐项读取关键参数，返回 `{connected, params{name:{value,expected,ok}}, issues[]}` |
| `esc_calibrate` | `channels`（int 数组，默认 1-8） | `result` | 双向电调油门行程标定（MAX 1900 → 3s → NEUTRAL 1500 → 2s） |
| `calibrate_one_way` | `channels`（int 数组，默认 1-8） | `result` | 单向电调标定（2000 → 3s → 1000 → 2s） |
| `correct_param` | `name`（参数名），`value`（float） | `param`, `value` | 写飞控参数；`success` 取决于写入是否成功 |
| `reset_position` | — | — | 坐标归零（当前为占位，直接成功） |
| `list_snapshots` | — | `ok`, `snapshots` | 见 §3.1 |
| `fetch_snapshot` | `name` | `ok`, `name`, `size`, `jpeg` | 见 §3.1 |
| `set_video`（顶层 type） | `width`, `height`, `fps`, `jpeg_quality` | `width`, `height`, `fps`, `jpeg_quality` | 见 §3.2 |
| `get_telemetry`（顶层 type） | — | — | 兼容保留：仅回成功 ack，遥测由推送循环下发 |

### 3.1 快照命令（新增）

**`list_snapshots`** — 列出 `rdkx5/snapshots/` 下的 jpg 快照（按文件名排序）：

```json
{"type": "ack", "command": "list_snapshots", "success": true, "ok": true,
 "snapshots": [{"name": "rdk_1789123456.jpg", "size": 84213, "ts": 1789123461.2}]}
```

`ts` 为文件 mtime（epoch 秒）；目录不存在时返回空数组。

**`fetch_snapshot`** — `params: {"name": "rdk_1789123456.jpg"}`：

```json
{"type": "ack", "command": "fetch_snapshot", "success": true, "ok": true,
 "name": "rdk_1789123456.jpg", "size": 84213, "jpeg": "<base64>"}
```

安全规则（硬性）：`name` 只允许**纯文件名**——拒绝空名、包含 `..`/`/`/`\` 的任何输入、
`os.path.basename` 变换后不一致的名字；只接受 `.jpg`/`.jpeg` 扩展名；解析后路径必须
仍位于 `rdkx5/snapshots/` 内。违规回 `success=false, message="invalid snapshot name"`；
文件不存在回 `success=false, message="snapshot not found: <name>"`。

### 3.2 `set_video`（新增，顶层 `{"type": "set_video", "params": {...}}`）

四个参数**全部热生效**（采集/推理/编码全链路；推理内部自带缩放，与分辨率无关），
缺省值 1280/720/15/78。校验范围（越界回失败 ack，**任何参数都不应用**）：

| 参数 | 范围 | 附加约束 |
| --- | --- | --- |
| `width` | 320–1920 | 必须为偶数 |
| `height` | 320–1920 | 必须为偶数 |
| `fps` | 1–30 | — |
| `jpeg_quality` | 30–95 | — |

```json
// 成功：回带应用后的真实参数
{"type": "ack", "command": "set_video", "success": true, "message": "ok",
 "width": 1280, "height": 720, "fps": 15, "jpeg_quality": 90}
// 失败：message 说明越界原因
{"type": "ack", "command": "set_video", "success": false,
 "message": "width out of range [320, 1920]: 5000"}
```

生效说明：`fps` 下一轮取帧循环即按新值计时；USB 摄像头同步写
`CAP_PROP_FRAME_WIDTH/HEIGHT/FPS`（驱动不支持时按最近可行值工作，`frame.width/height`
始终回报真实编码尺寸）；MIPI 摄像头按新参数重开；参数会被记忆，`set_camera` 切换后
依然生效。

## 4. 安全约定（PC 侧必须遵守）

1. `move` 必须带 `deadman_ms`（默认 1000ms），PC 每 100ms 重发当前期望值；
2. 网关连续 `deadman_ms` 未收到运动指令，自动输出中立值（看门狗）；
3. `emergency_stop` 优先级最高，立即回 ack；
4. 网关启动时 Pixhawk 默认未解锁（`pixhawk.auto_arm` 配置可改为链路建立后自动解锁）；
5. 控制日志：PC 端每次下发命令应记录 `ack` 结果用于审计。
