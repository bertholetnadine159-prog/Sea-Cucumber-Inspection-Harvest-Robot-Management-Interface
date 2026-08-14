# PC <-> RDK X5 通信协议

> 本目录所有代码运行在 **RDK X5（地瓜机器人 / D-Robotics Sunrise 5）** 上。
> PC 端软件通过网线直连 RDK X5，使用 WebSocket 同时承载视频、遥测和控制。

## 网络约定

| 端 | 地址 | 说明 |
| --- | --- | --- |
| RDK X5 网口 eth0 | `192.168.127.10/24`（镜像默认静态 IP） | 网关 `192.168.127.1` |
| PC 网口 | `192.168.127.100/24`（任意同网段即可） | 网关 `192.168.127.1` |
| RDK X5 服务端口 | TCP `8080` | WebSocket 服务 |

修改 RDK X5 侧端口/地址：编辑 `rdkx5/config.yaml` 的 `server` 段。
修改 PC 侧目标地址：设置环境变量 `ROV_RDK_HOST` / `ROV_RDK_PORT`。

## 协议选择理由

- 视频、遥测、控制都走**同一条 WebSocket**：NAT/防火墙最简单，只开一个端口，延迟低。
- 视频帧使用 **JPEG + base64 JSON**（与现有 SeaUI 前端兼容，零改造即可显示）。
- 上行控制使用 JSON 命令 + `deadman_ms` 看门狗，断链自动停车（水下安全要求）。
- 若 RDK 端硬件编码可用则用 `srcampy.Encoder`，否则回退 OpenCV JPEG。

## 消息总表（JSON 文本帧）

下行（RDK X5 -> PC）：

| type | 字段 | 频率 |
| --- | --- | --- |
| `hello` | `device`, `version`, `caps`, `cameras[]` | 连接后 1 次 |
| `frame` | `seq`, `ts`, `camera_id`, `width`, `height`, `jpeg`(base64), `detections[]`, `inference_ms`, `fps` | 按活动摄像头 `fps` |
| `telemetry` | `ts`, `sensors{}`, `pixhawk{connected,armed,mode,battery_v,...}`, `link{fps,rtt_ms}` | 按 `telemetry.hz` |
| `log` | `level`, `message` | 随时 |
| `ack` | `command`, `success`, `message` | 每条上行命令 1 次 |

上行（PC -> RDK X5）：

| type | command | params | 说明 |
| --- | --- | --- | --- |
| `command` | `move` | `axes{surge,sway,heave,roll,pitch,yaw}`, `deadman_ms` | 6 自由度速度，范围 [-1,1] |
| `command` | `stop` | - | 立即回中 |
| `command` | `arm` / `disarm` | `force` | 解锁/锁定 Pixhawk |
| `command` | `set_mode` | `mode` | 切换 Pixhawk 飞行模式 |
| `command` | `set_camera` | `camera_id`（`camera_1` 前视 / `camera_2` 吸口近距） | 切换活动摄像头 |
| `command` | `suction` | `power_percent` | 0-100，AUX1/AUX2 吸捕电机 |
| `command` | `servo` | `channel`, `pwm` | 直通 PWM（AUX3 舵机等） |
| `command` | `light_on` / `light_off` | - | 灯光输出 |
| `command` | `emergency_stop` | - | 立即回中 + 可选上锁 |
| `command` | `reset_position` | - | 坐标归零 |
| `set_video` | - | `width`, `height`, `fps`, `jpeg_quality` | 动态调整视频流 |
| `get_telemetry` | - | - | 请求一次遥测 |

## 遥测字段（下行 `telemetry.sensors`）

```json
{
  "veml7700_front_light": {"ok": true, "values": {"lux": 172.3, "als_raw": 2991, "white_raw": 2511}},
  "veml7700_down_light":  {"ok": true, "values": {"lux": 89.1,  "als_raw": 1547, "white_raw": 1300}},
  "ms5837_depth":         {"ok": true, "values": {"pressure_mbar": 1021.4, "temperature_c": 18.6, "depth_m": 0.42}},
  "ds18b20_water_1":     {"ok": true, "values": {"temperature_c": 18.8}},
  "ds18b20_water_2":     {"ok": true, "values": {"temperature_c": 19.1}},
  "ultrasonic_front":    {"ok": true, "values": {"distance_m": 0.055}},
  "ultrasonic_downward": {"ok": true, "values": {"distance_m": 0.70}}
}
```

`telemetry.pixhawk`：

```json
{
  "connected": true,
  "armed": false,
  "mode": "MANUAL",
  "battery_v": 12.3,
  "battery_remaining": 88,
  "attitude_deg": {"roll": -0.4, "pitch": 0.2, "yaw": 12.8},
  "depth_m": null
}
```

## 安全约定（PC 侧必须遵守）

1. `move` 必须带 `deadman_ms`（默认 1000ms）；PC 每 100ms 重发一次当前期望值。
2. RDK X5 连续 `deadman_ms` 未收到运动指令时，自动输出中位 PWM / MANUAL_CONTROL 0。
3. `emergency_stop` 的优先级高于任何其它命令，且立即回 ack。
4. RDK X5 启动时 Pixhawk 保持**未解锁**状态，只有收到 `arm` 才解锁。
