# SeaUI 软件框架说明

本文档说明当前软件的完整架构：SeaUI 桌面软件（PC）如何通过网线与
地瓜机器人 RDK X5 通信，RDK X5 如何控制 Pixhawk 2.4.8，以及
视频、AI 检测、传感器、数据库与登录鉴权的数据流。

## 1. 总体架构

```text
┌─────────────────────────────────────────────────────────────┐
│ PC（Windows）                                                │
│                                                             │
│  ┌──────────────────┐   ws://127.0.0.1:8765   ┌───────────┐ │
│  │ Flutter 桌面界面  │ ──────────────────────▶ │ Python 后端│ │
│  │ 登录/主控/操作/    │ ◀────────────────────── │ (桥接服务) │ │
│  │ 数据/设置         │   视频帧 + 传感器 + 状态  │           │ │
│  └──────────────────┘                         │  SQLite   │ │
│        http://127.0.0.1:5000 (REST 登录/管理)  │  数据库   │ │
│                                               └─────┬─────┘ │
└─────────────────────────────────────────────────────┼───────┘
                                                      │ 网线直连
                                     ws://192.168.127.10:8080
                                                      │
┌─────────────────────────────────────────────────────▼───────┐
│ RDK X5（Sunrise 5，Ubuntu 22.04）                            │
│  rdkx5/gateway.py                                            │
│   ├─ 双摄像头(camera_1 前视 / camera_2 吸口) → BPU YOLO11     │
│   │   分割 → 标注 JPEG 视频流（可切换活动摄像头）               │
│   ├─ VEML7700 / MS5837 / DS18B20 / LO81MTW → 传感器遥测        │
│   └─ WebSocket 服务器（视频 + 遥测 + 命令）                    │
│                        │ MAVLink /dev/ttyACM0               │
└────────────────────────▼────────────────────────────────────┘
                   Pixhawk 2.4.8（ArduSub / PX4）
                   MAIN1-8 推进器 · AUX1-2 吸捕电机 · AUX3 舵机
```

## 2. PC 端（Flutter + Python 桥接）

| 组件 | 位置 | 职责 |
| --- | --- | --- |
| Flutter 桌面界面 | `rov_flutter/` | 登录、主控、控制操作、数据分析、设置 |
| 本地后端 | `backend/app.py` | 桥接、鉴权、REST、命令转发、死区看门狗 |
| RDK 客户端 | `backend/rdk_client.py` | 连 RDK X5 WebSocket，断线重连 |
| 数据库 | `backend/database.py` | SQLite：用户、会话、传感器、控制日志、设置 |
| REST API | `backend/app.py` | `http://127.0.0.1:5000` |

后端三种模式（`ROV_BACKEND_MODE`）：

- `rdk`（默认）：视频与 AI 全部来自 RDK X5，PC 不跑 ONNX。
- `local`：旧版兼容，PC 摄像头 + `best.onnx`（开发调试）。
- `sim`：合成视频帧与遥测，无任何硬件也能联调界面。

## 3. RDK X5 端（`rdkx5/`，代码已逐文件标注 [RDK X5 side]）

| 文件 | 职责 |
| --- | --- |
| `gateway.py` | 主程序，装配所有组件 |
| `stream_server.py` | WebSocket 视频/遥测/命令通道 |
| `vision.py` | 双摄像头管理（UVC 自动探测/MIPI）、`hobot_dnn` BPU 分割、OpenCV 标注、JPEG |
| `pixhawk_link.py` | MAVLink 控制 + 死区看门狗 |
| `sensors.py` | VEML7700 / MS5837 / DS18B20 / LO81MTW |
| `yolo11_seg_rdk.py` | 量化 BIN 模型推理（来自模型转换仓库） |
| `YOLO11_LBL.bin` | 海参 YOLO11 分割量化模型 |
| `config.yaml` | 网络、摄像头、模型、传感器、Pixhawk 接线 |
| `PROTOCOL.md` | PC ↔ RDK X5 消息协议 |
| `check_hardware.py` | 实机一键自检：网络/设备/依赖/传感器/Pixhawk/BPU/端口 |

## 4. 通信协议（一条 WebSocket，端口 8080）

下行（RDK X5 → PC）：

- `hello`：设备信息与 `cameras[]`
- `frame`：`{seq, ts, camera_id, width, height, jpeg(base64), detections[], inference_ms, fps}`
- `telemetry`：`{sensors{...}, pixhawk{connected, armed, mode, battery_v, attitude_deg}, link{fps}}`
- `log` / `ack`

上行（PC → RDK X5）：

- `move`：`{axes: {surge, sway, heave, roll, pitch, yaw}, deadman_ms}`
- `stop` / `arm` / `disarm` / `set_mode`
- `set_camera`：`{camera_id: camera_1 | camera_2}`，切换前视/吸口近距摄像头
- `suction` / `servo` / `light_on` / `light_off` / `emergency_stop`
- `sonar_on/off` / `laser_on/off` / `auto_cruise` / `snapshot` / `reset_position`

安全：`move` 带 `deadman_ms`；PC 每 100ms 重发；RDK 超时自动回中；
启动时 Pixhawk 保持未解锁，需显式 `arm`。

## 5. Pixhawk 控制（软件 → RDK X5 → Pixhawk 2.4.8）

`pixhawk_link.py` 支持两种方式（`config.yaml` 的 `pixhawk.control_mode`）：

- `manual_control`（推荐）：ArduSub `MANUAL_CONTROL`（x/y/z/r 虚拟摇杆），
  保留飞控稳定回路与混控；吸捕/舵机仍用 `DO_SET_SERVO` 输出 AUX。
- `servo_pwm`：`MAV_CMD_DO_SET_SERVO` 直通 PWM，兼容任意固件。

原有 GitHub 仓库
`Sunrise5-Based-Sea-Cucumber-Inspection-and-Suction-Harvest-Robot`
的 `pixhawk_mavlink.py` 已同步优化并推送到上游 `main`（commit `5bbd0db`）：
新增 `arm / set_mode / manual_control / drain_messages / telemetry_snapshot`。

## 6. 传感器（全部在 RDK X5 上）

| 传感器 | 接口 | 输出 |
| --- | --- | --- |
| VEML7700 × 2 | I2C | `lux`, `als_raw`, `white_raw` |
| MS5837-30BA | I2C | `pressure_mbar`, `temperature_c`, `depth_m` |
| DS18B20 × 2 | 1-Wire sysfs | `temperature_c` |
| LO81MTW × 2 | USB 串口 | `distance_m` |

读数 → `telemetry.sensors` → PC 后端入库 SQLite（`sensor_readings`）→
Flutter 主控/操作页实时显示；数据分析页从 `GET /api/sensors` 读取历史，
按分钟聚合后绘制深度、水温、光照、压强曲线（无板卡时 sim 模式也会生成
合成遥测用于演示完整链路）。

## 7. 数据库与登录拦截

SQLite 表：`users`、`sessions`、`sensor_readings`、`control_logs`、`settings`。

- 密码 PBKDF2-HMAC-SHA256 加盐哈希，不存明文。
- 超级管理员首次启动自动创建：用户名 `zmm`，密码 `Zmm771023`。
- 登录走 `POST /api/login`；用户名或密码缺失/错误返回 401，
  Flutter 登录页直接拦截，不再出现“访客放行”路径。
- 管理接口（用户增删改）需要 Bearer token 且角色为 `super_admin/admin`。
- 所有控制命令写入 `control_logs`，所有传感器读数写入 `sensor_readings`。
- Flutter 管理员面板的用户列表/增删、操作日志均以数据库为权威来源。

## 8. 部署与运行

PC：

```text
双击 open_seaUI.bat
```

PC 网口一键配置（管理员 PowerShell，`-Check` 只检查不改动）：

```text
powershell -NoProfile -ExecutionPolicy Bypass -File rdkx5\scripts\setup_pc_network.ps1 -Check
powershell -NoProfile -ExecutionPolicy Bypass -File rdkx5\scripts\setup_pc_network.ps1 -Apply
```

RDK X5（SSH `sunrise@192.168.127.10`，默认密码 `sunrise`）：

```bash
scp -r rdkx5 sunrise@192.168.127.10:/home/sunrise/seaUI_rdk
ssh sunrise@192.168.127.10
cd /home/sunrise/seaUI_rdk && ./run_robot.sh
```

无硬件联调（PC 单机）：

```text
set ROV_BACKEND_MODE=sim
python backend\app.py
```

## 9. 验证情况

- `backend/tests/`：12 项测试全部通过，覆盖数据库鉴权/拦截、REST、
  UI WebSocket、假 RDK 网关回环（视频 + 遥测转发），以及**真实
  `rdkx5/gateway.py` 仿真回环**（视频/遥测/命令全链路）。
- `rdkx5/tests/`：7 项测试全部通过，覆盖超声波 FF 协议解析、死区看门狗、
  传感器与视频仿真管线。
- RDK X5 端代码已通过 `py_compile` 语法检查；
  摄像头/BPU/传感器/Pixhawk 需在实机板卡上按 `rdkx5/README.md` 验证。
- 模型文件 SHA256 与上游仓库记录一致（BC66F9E8…D995）。
- sim 模式实测：合成传感器遥测落库并经 `GET /api/sensors` 返回，供数据分析页消费。
