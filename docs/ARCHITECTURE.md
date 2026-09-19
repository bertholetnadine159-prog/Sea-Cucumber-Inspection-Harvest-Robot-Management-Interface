# SeaUI 软件框架说明

本文档说明当前软件（v3.0.0 商用化版本）的完整架构：SeaUI 桌面软件（PC）如何
通过网线与地瓜机器人 RDK X5 通信，RDK X5 如何控制 Pixhawk 2.4.8，以及视频、
AI 检测、传感器、数据库、登录鉴权与数据溯源的数据流。

> v3.0.0 商用化升级的接口契约见 [UPGRADE_CONTRACTS.md](UPGRADE_CONTRACTS.md)，
> 逐项验收状态见 [VERIFICATION_STATUS.md](VERIFICATION_STATUS.md)。

## 1. 总体架构

```text
┌─────────────────────────────────────────────────────────────┐
│ PC（Windows）                                                │
│                                                             │
│  ┌──────────────────┐   ws://127.0.0.1:8765   ┌───────────┐ │
│  │ Flutter 桌面界面  │ ──────────────────────▶ │ Python 后端│ │
│  │ 登录/主控/操作/    │ ◀────────────────────── │ (桥接服务) │ │
│  │ 数据/设置         │   视频帧 + 传感器 + 状态  │  WS 强鉴权 │ │
│  └──────────────────┘   （auth 后才推流）      │  + REST   │ │
│        http://127.0.0.1:5000 (REST 登录/管理)  │  SQLite   │ │
│                                               │ (source 标)│ │
│  安装版：SeaUI.exe + backend/SeaUIBackend.exe │           │ │
│  （PyInstaller onefile，免 Python 环境）       └─────┬─────┘ │
└─────────────────────────────────────────────────────┼───────┘
                                                      │ 网线直连
                                     ws://192.168.127.10:8080
                                                      │
┌─────────────────────────────────────────────────────▼───────┐
│ RDK X5（Sunrise 5，Ubuntu 22.04）                            │
│  rdkx5/gateway.py（可由 deploy/seaui-gateway.service 常驻）   │
│   ├─ 双摄像头(camera_1 前视 / camera_2 吸口) → BPU YOLO11     │
│   │   分割 → 标注 JPEG 视频流（可切换活动摄像头）               │
│   ├─ VEML7700 / MS5837 / DS18B20 / LO81MTW → 传感器遥测        │
│   └─ WebSocket 服务器（视频 + 遥测 + 命令 + 快照）              │
│                        │ MAVLink /dev/ttyACM0               │
└────────────────────────▼────────────────────────────────────┘
                   Pixhawk 2.4.8（ArduSub / PX4）
                   MAIN1-8 推进器 · AUX5-6 吸捕电机 · AUX4 舵机
```

## 2. PC 端（Flutter + Python 桥接）

| 组件 | 位置 | 职责 |
| --- | --- | --- |
| Flutter 桌面/移动界面 | `rov_flutter/` | 登录、主控、控制操作、数据分析、管理员、设置（移动端仅主控 + 设置） |
| 服务层 | `rov_flutter/lib/core/services/rov_backend_service.dart` | WS/REST 客户端；三通道 `ValueNotifier`（见 §3）；登录后 `attachAuth(token)` 注入令牌 |
| 共享组件 | `rov_flutter/lib/features/shared/` | TelemetryCard、StatusBadge、ControlPad、ConfirmDialog、StaleBadge、AppBackground |
| 本地后端 | `backend/app.py` | 桥接、WS 强鉴权、REST、命令转发与角色控制、死区看门狗 |
| RDK 客户端 | `backend/rdk_client.py` | 连 RDK X5 WebSocket，断线重连；`send_command_await` 按 ack 匹配并透传载荷 |
| 数据库 | `backend/database.py` | SQLite：用户、会话、传感器（带 `source` 标）、控制日志、设置 |
| REST API | `backend/app.py` | `http://127.0.0.1:5000`，CORS 仅放行 `http://127.0.0.1:*` 与 `http://localhost:*` |

后端三种模式（`ROV_BACKEND_MODE`）：

- `rdk`（默认）：视频与 AI 全部来自 RDK X5，PC 不跑 ONNX。
- `local`：旧版兼容，PC 摄像头 + `best.onnx`（开发调试）。
- `sim`：合成视频帧与遥测，无任何硬件也能联调界面。

落库按当前 `backend_mode` 为每条传感器记录打 `source` 标（rdk/local/sim），
`/api/stats` 与 `/api/sensors` 查询默认 `source='rdk'`，sim 数据不计入真实
统计；界面在 sim 模式下全局显示"仿真数据"角标。

界面基础：本地内置字体（Noto Sans SC / Inter，不依赖 google_fonts）、
本地登录背景与应用图标；桌面窗口经 window_manager 可调大小（最小 1024×640，
默认 1440×900，居中显示）。

## 3. 服务层三通道通知模型与断链感知

为消除"每帧视频触发全页重建"的卡顿，`RovBackendService` 将高频数据从全局
`notifyListeners` 中拆出，改为三条独立通道：

| 通道 | 类型 | 内容与上限 |
| --- | --- | --- |
| `videoFrameNotifier` | `ValueNotifier<VideoFrame?>` | 视频帧专用，仅画面组件监听，不触发全局重建；帧内含 `sent_ts`，可直接计算 ≈链路时延 |
| `telemetryNotifier` | `ValueNotifier<TelemetrySnapshot?>` | `status`/`sensors` 合并快照，5Hz 上限；每通道携带 `lastUpdated`（本地接收时刻） |
| `connectionNotifier` | `ValueNotifier<ConnectionState>` | connected / reconnecting / offline |

断链感知由共享组件 `StaleBadge` 实现：数据年龄（`now - lastUpdated`）超过
5 秒即显示"⚠ 信号丢失"徽标并冻结最后真实值，数据恢复后自动消失，不使用任何
兜底假值。登录成功后调用 `service.attachAuth(token)`，服务层在 WS 连接建立后
发送 `auth` 完成鉴权（未鉴权时后端不推流，属预期行为）。

## 4. RDK X5 端（`rdkx5/`，代码已逐文件标注 [RDK X5 side]）

| 文件 | 职责 |
| --- | --- |
| `gateway.py` | 主程序，装配所有组件 |
| `stream_server.py` | WebSocket 视频/遥测/命令通道；`set_video` 参数校验与 ack；快照命令 |
| `vision.py` | 双摄像头管理（UVC 自动探测/MIPI）、`hobot_dnn` BPU 分割、OpenCV 标注、JPEG；`set_video` 宽/高/fps/质量热更新真实生效 |
| `pixhawk_link.py` | MAVLink 控制 + 死区看门狗；遥测含 `motors_pwm/aux_pwm/vcc_v/vservo_v/sensors_health` |
| `sensors.py` | VEML7700 / MS5837 / DS18B20 / LO81MTW |
| `yolo11_seg_rdk.py` | 量化 BIN 模型推理（来自模型转换仓库） |
| `YOLO11_LBL.bin` | 海参 YOLO11 分割量化模型 |
| `config.yaml` | 网络、摄像头、模型、传感器、Pixhawk 接线 |
| `PROTOCOL.md` | PC ↔ RDK X5 消息协议（网关侧） |
| `docs/UI_PROTOCOL.md` | PC ↔ Flutter WS 全字段协议（v3.0.0 起为权威协议文档） |
| `deploy/seaui-gateway.service` | systemd 常驻单元（开机自启、断线 3s 自动重启） |
| `check_hardware.py` | 实机一键自检：网络/设备/依赖/传感器/Pixhawk/BPU/端口 |

## 5. 通信协议（一条 WebSocket，端口 8080）

全字段说明见 [rdkx5/docs/UI_PROTOCOL.md](../rdkx5/docs/UI_PROTOCOL.md)，此处仅列要点。

下行（RDK X5 → PC）：

- `hello`：设备信息与 `cameras[]`
- `frame`：`{seq, ts, camera_id, width, height, jpeg(base64), detections[], inference_ms, fps, sent_ts}`
  —— `ts` 为帧采集时刻，`sent_ts` 为网关发送时刻（epoch 秒，float）；
  **端到端时延 = 接收时刻 − `sent_ts`**，UI 标注"≈链路时延"，时钟倒挂或缺失时显示为空，不造数
- `telemetry`：`{sensors{...}, pixhawk{connected, armed, mode, battery_v, battery_remaining, motors_pwm, aux_pwm, vcc_v, vservo_v, sensors_health, attitude_deg}, link{fps}}`
- `ack`：命令应答；`list_snapshots`/`fetch_snapshot`/诊断类命令的结果经 ack 载荷完整透传回 UI
- `log`

上行（PC → RDK X5）：

- `move`：`{axes: {surge, sway, heave, roll, pitch, yaw}, deadman_ms}`
- `stop` / `arm` / `disarm` / `set_mode`
- `set_camera`：`{camera_id: camera_1 | camera_2}`，切换前视/吸口近距摄像头
- `set_video`：`{params: {width, height, fps, jpeg_quality}}`，真实热更新取帧链路，越界值回失败 ack
- `suction` / `servo` / `light_on` / `light_off` / `emergency_stop`
- `snapshot` / `list_snapshots` / `fetch_snapshot`：抓拍浏览与回传
  （`fetch_snapshot` 仅允许 `rdkx5/snapshots/` 目录内文件名，拒绝路径穿越）
- 诊断类：`motor_diagnostic` / `esc_calibrate` / `calibrate_one_way` / `correct_param` / `init_escs`
- `sonar_on/off` / `laser_on/off` / `auto_cruise` / `reset_position`
  （协议保留；Flutter 界面已移除对应的空壳入口）

安全：`move` 带 `deadman_ms`；PC 每 100ms 重发；RDK 超时自动回中；
启动时 Pixhawk 保持未解锁，需显式 `arm`。

## 6. 后端 WS 鉴权与角色（PC 后端 ↔ Flutter）

UI WebSocket（`ws://127.0.0.1:8765`）的鉴权流程：

```text
连接建立 ──▶ 后端回 hello（此时不推任何流式数据）
        ──▶ 客户端发 {"type":"auth","token":...}（登录取得的 Bearer token）
        ──▶ 校验通过：auth_result，开始推送 frame/status/sensors
            校验失败：auth_result(success=false)，仍不推流
命令消息  ──▶ 无/无效 token：回 {"type":"ack","command":...,"success":false,
            "message":"unauthorized"}，不执行
```

- 危险命令白名单（仅 `super_admin`/`admin` 可发，WS 与 `POST /api/command`
  同规则）：`arm`、`disarm`、`esc_calibrate`、`calibrate_one_way`、
  `correct_param`、`motor_diagnostic`、`init_escs`。
- `set_rdk_config` 需有效 token 且 admin 角色。
- REST 与 WS 的 CORS 均收敛为本机回环来源。
- 命令执行结果与快照/诊断数据经 ack 载荷透传到界面（管理页链路诊断、
  数据分析页快照画廊即消费此通道）。

## 7. Pixhawk 控制（软件 → RDK X5 → Pixhawk 2.4.8）

`pixhawk_link.py` 支持两种方式（`config.yaml` 的 `pixhawk.control_mode`）：

- `manual_control`（推荐）：ArduSub `MANUAL_CONTROL`（x/y/z/r 虚拟摇杆，
  Z 轴为遗留范围 [0,1000]，500 为中性），保留飞控稳定回路与混控；
  吸捕/舵机仍用 `DO_SET_SERVO` 输出 AUX。
- `servo_pwm`：`MAV_CMD_DO_SET_SERVO` 直通 PWM，兼容任意固件。

串口按 `/dev/serial/by-id/*Pixhawk*` 自动解析并掉线自动重连；arm/disarm 使用
ArduPilot 魔数 21196；遥测额外上报 8 路 `motors_pwm`、`aux_pwm`、供电电压与
`sensors_health`，供管理页做链路诊断。电机/ESC 诊断（`motor_diagnostic`、
`esc_calibrate` 等）属于危险命令白名单，结果经 ack 载荷透传回诊断界面。

原有 GitHub 仓库
`Sunrise5-Based-Sea-Cucumber-Inspection-and-Suction-Harvest-Robot`
的 `pixhawk_mavlink.py` 已同步优化并推送到上游 `main`（commit `5bbd0db`）。

## 8. 传感器与数据分析（全部传感器在 RDK X5 上）

| 传感器 | 接口 | 输出 |
| --- | --- | --- |
| VEML7700 × 2 | I2C | `lux`, `als_raw`, `white_raw` |
| MS5837-30BA | I2C | `pressure_mbar`, `temperature_c`, `depth_m` |
| DS18B20 × 2 | 1-Wire sysfs | `temperature_c` |
| LO81MTW × 2 | USB 串口 | `distance_m` |

读数 → `telemetry.sensors` → PC 后端按 `backend_mode` 打 `source` 后入库
SQLite（`sensor_readings`）→ Flutter 主控/操作页经 `telemetryNotifier` 实时
显示（断链由 StaleBadge 标注）。

数据分析页全部消费真实库记录：`GET /api/sensors` 支持 `from`/`to` 时间窗、
`bucket` 聚合窗口（按窗口 AVG）、`names` 按名筛选与 `source` 来源过滤
（默认 `rdk`），并返回各序列 min/max/avg 统计摘要；界面支持多传感器聚合
曲线、CSV 导出与快照画廊（`list_snapshots`/`fetch_snapshot`）。sim 模式
下页面带全局"仿真数据"角标，数据仍走完整链路用于演示与联调。

## 9. 数据库、登录与数据溯源

SQLite 表：`users`、`sessions`、`sensor_readings`（含 `source` 列）、
`control_logs`、`settings`。

- 密码 PBKDF2-HMAC-SHA256 加盐哈希，不存明文；文档与交付物均不含明文口令。
- 超级管理员首次启动自动创建；初始口令可通过环境变量
  `ROV_SUPER_ADMIN_PASSWORD` 预置（正式部署必须覆盖默认值）。
- 登录走 `POST /api/login`：用户名或密码缺失/错误返回 401，Flutter 登录页
  直接拦截，无"访客放行"路径；响应携带 `must_change_password`——super_admin
  仍在使用初始口令时为 true，客户端弹出强制改密对话框，改密成功前不进入
  主界面。
- 普通用户可经 `PUT /api/users/{id}/password` 自助改密（仅限本人；管理员
  可改他人）。
- 管理接口（用户增删改）需要 Bearer token 且角色为 `super_admin/admin`；
  危险命令角色白名单同 §6。
- 所有控制命令写入 `control_logs`，所有传感器读数写入 `sensor_readings`
  并按来源打标；`/api/stats` 管理页 KPI 与 `/api/sensors` 曲线只统计
  `source='rdk'` 的真实记录，sim/演示数据不混入。

## 10. 部署与运行

PC（安装版，客户交付）：

```text
SeaUI-Setup-3.0.0.exe（Inno Setup 向导，默认装至 C:\Program Files\SeaUI）
├── SeaUI.exe                    # Flutter release 客户端（自动拉起后端）
└── backend/SeaUIBackend.exe     # PyInstaller onefile 后端（内置 best.onnx）
```

客户机器无需 Python 环境；数据库持久化在 `%LOCALAPPDATA%\SeaUI\data\`。
打包步骤与产物清单见 [installer/README.md](../installer/README.md)，
`SeaUIBackend.exe` 冒烟验证（health / 未授权请求拦截）已通过。

PC（开发者模式）：

```text
双击 open_seaUI.bat（/rebuild 重新构建）
无硬件联调：set ROV_BACKEND_MODE=sim && python backend\app.py
```

PC 网口一键配置（管理员 PowerShell，`-Check` 只检查不改动）：

```text
powershell -NoProfile -ExecutionPolicy Bypass -File rdkx5\scripts\setup_pc_network.ps1 -Check
powershell -NoProfile -ExecutionPolicy Bypass -File rdkx5\scripts\setup_pc_network.ps1 -Apply
```

RDK X5（SSH `sunrise@192.168.127.10`）：

```bash
scp -r rdkx5 sunrise@192.168.127.10:/home/sunrise/seaUI_rdk
ssh sunrise@192.168.127.10
cd /home/sunrise/seaUI_rdk && ./run_robot.sh
```

长期部署建议用 systemd 常驻（`rdkx5/deploy/seaui-gateway.service`：
以 `sunrise` 用户运行 `gateway.py`，开机自启、异常退出 3 秒后自动重启），
安装步骤见 [rdkx5/deploy/README.md](../rdkx5/deploy/README.md)。

## 11. 验证情况

- `backend/tests/`：27 项测试全部通过。覆盖数据库鉴权/拦截、REST、UI
  WebSocket、假 RDK 网关回环、真实 `rdkx5/gateway.py` 仿真回环，以及本轮
  升级项：stats/sensors 时间窗与 bucket 聚合、source 过滤与落库打标、
  WS 强鉴权与危险命令角色白名单、CORS 收敛、`must_change_password`、
  ack 载荷透传（`send_command_await`）与自助改密。
- `rdkx5/tests/`：34 项测试全部通过。覆盖超声波 FF 协议解析、死区看门狗、
  传感器与视频仿真管线，以及本轮升级项：`set_video` 参数校验与热生效、
  `frame.sent_ts` 单调性、快照命令与路径穿越防护、推送循环端到端。
- `rov_flutter/test/`：24 项测试全部通过。覆盖登录流、服务层三通道
  （时延计算、数据年龄、连接状态机回环）、命令下发、StaleBadge 断链徽标
  与组件冒烟；`flutter analyze` 0 error。
- RDK X5 端代码已通过 `py_compile` 语法检查；
  摄像头/BPU/传感器/Pixhawk 需在实机板卡上按 `rdkx5/README.md` 验证。
- 模型文件 SHA256 与上游仓库记录一致（BC66F9E8…D995）。
- sim 模式闭环已实测：合成传感器遥测按 `source='sim'` 落库并经
  `GET /api/sensors` 返回，数据分析页正常消费且带"仿真数据"角标。
- 真机逐字段回传验收（UI vs MAVLink vs SQLite 三方比对、拔线断链徽标、
  双摄切换复测）尚未执行，待验清单见
  [VERIFICATION_STATUS.md](VERIFICATION_STATUS.md)。
