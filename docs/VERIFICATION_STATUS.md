# 目标验收状态清单（需求 → 证据 → 状态）

> 更新：2026-09-19（文末新增 v3.0.0 商用化升级验证记录）。绿色 = 已离线验证；黄色 = 代码完成但需实机验证。

| # | 需求 | 证据 | 状态 |
| --- | --- | --- | --- |
| 1 | RDK X5 摄像头画面进主界面，UI 不再跑 ONNX | 双摄实机全部验证：camera_1→/dev/video0、camera_2→/dev/video2 均能打开出帧，`set_camera` 双向切换成功；真实 1280×720 帧经 backend 到达 UI WS | 绿色 |
| 2 | 优化 Pixhawk 控制仓库，链路为 软件→X5→Pixhawk | GitHub 已推送 `2349d1e`；`rdkx5/pixhawk_link.py`（by-id 解析 + 掉线自动重建连接 + force 魔数 21196 + ArduSub 遗留 Z 轴换算 + GCS 心跳）；实机 MAVLink 已通；arm/disarm 闭环通过；Pixhawk 输出级实测 arm 后 surge=+0.5 时 MAIN1/2=1400、MAIN3/4=1600、stop 回 1500；当前待定位 ESC“无信号”报警（疑似 Pixhawk→ESC 插排/共地/舵机排供电） | 黄色 |
| 3 | 网线两边通信，RDK 代码标注 | `rdkx5/*.py` 头部 `[RDK X5 side]`；`PROTOCOL.md`；`backend/rdk_client.py`；回环测试通过；实机网线联调已通过（ping/SSH/8080） | 绿色 |
| 4 | 网线传输 YOLO 部署后视频流 | WebSocket+JPEG；`test_rdk_gateway_loopback` 通过；实机 BPU 加载 + 逐帧推理已通过，JPEG 帧实时经网线到达 PC（帧内含 detections，当前场景无海参故为空） | 绿色 |
| 5 | RDK X5 上传感器全部回传 | `rdkx5/sensors.py`；遥测→SQLite→界面/分析页；sim 遥测落库实测通过；实机 I2C/串口读数待验证 | 黄色 |
| 6 | 调研官方/GitHub 方案并更新控制程序 | 官方 srcampy/hobot_dnn/web 显示示例、hobot_websocket、ArduSub MANUAL_CONTROL；已实现并推送 | 绿色 |
| 7 | 管理员与传感器数据入库，登录拦截，超管账号初始化 | `backend/database.py` + REST + Flutter 登录/管理员/日志接线；空/错密码 401 实测 | 绿色 |
| 8 | 说明软件框架 | `docs/ARCHITECTURE.md`、DOCX、PDF，已推送 | 绿色 |
| 9 | @documents @pdf | DOCX/PDF 已交付并通过内容/几何质检（DOCX 无 LibreOffice 渲染目检，已声明） | 绿色 |

## 实机验收步骤（恢复后执行）

1. 网线连接板卡并上电；`rdkx5/scripts/setup_pc_network.ps1 -Check` 应看到 Realtek 网卡 Up。
2. `-Apply` 配置 `192.168.127.100/24`；`ping 192.168.127.10` 通。
3. `python rdkx5/scripts/deploy_to_board.py --check`（一键上传 + 板卡自检）。
4. 板卡自检 8/10 PASS；剩余 2 个 FAIL 对应未接的超声波/传感器，属预期。
5. `deploy_to_board.py --check --start-gateway`（或板卡上 `./run_robot.sh`）启动网关；PC 双击 `open_seaUI.bat`。
6. `python backend/verify_live.py` 六项全 PASS；主界面确认：视频流、YOLO 标注、
   传感器数值、RDK X5 已连接；操作页发命令确认 Pixhawk 动作（电机接好前不 arm）。

> 2026-08-15 实测补充（第三轮，摄像头已接入）：接入 USB UVC `Camera8M` 后配置改为
> `cameras.camera_1/camera_2`（`device: auto` 自动探测采集节点），`camera_1` 自动解析到
> `/dev/video0`。`backend/verify_live.py` 六项全部 PASS（frame 约 51–58 KB JPEG 实时经
> backend 到达 UI WS），快照经像素统计确认是真实 1280×720 彩色画面。
> 双摄切换协议已实现：`hello.cameras`、`frame.camera_id`、上行 `set_camera`；
> `camera_2` 因第二只摄像头尚未插入，切换会正确返回失败并保持 `camera_1`。
> Pixhawk 掉电重插后改号到 `/dev/ttyACM1`，`pixhawk_link.py` 已加 by-id 自动解析
> （`/dev/serial/by-id/*Pixhawk*`）与启动期自动重连，心跳正常、未解锁、MANUAL。
> 板卡自检 8/10 PASS，仅剩 `ultrasonic_usb` 与 `sensors` 对应未接硬件。

> 2026-08-15 实测补充（第四轮，第二只摄像头 + 电机已接入）：板卡重启后网关需重新部署，
> `deploy_to_board.py --start-gateway` 一键恢复。双摄全部实机验证：camera_1→`/dev/video0`、
> camera_2→`/dev/video2`，`set_camera` 双向切换成功且各自出帧，`verify_live.py` 六项全 PASS。
> Pixhawk 重启后回到 `/dev/ttyACM0`，by-id 解析自动匹配，心跳正常、未解锁、MANUAL。
> 电机链路安全验证（未解锁）：超管 `zmm` 登录 → `/api/command` 下发 `stop` 与
> AUX1/AUX3 中性 1500 PWM，PC 后端→RDK→Pixhawk 全部 `ok=True`，Pixhawk 保持 `armed=false`。
> 剩余待办：传感器接线（当前 ttyUSB/w1/I2C 均无设备）；电机带电旋转测试前必须确认
> 桨叶已拆除并在陆地干式环境执行，收到确认后才发送 `arm`。

> 2026-08-15 实测补充（第五轮，arm 根因定位 + 无桨 arm 闭环）：板卡日志与 `dmesg` 显示
> Pixhawk USB（`1209:5741`）反复掉线重枚举，最后一次在启动后 702s 断开且长期未回归，
> 这是此前 `arm` 已传输但 Pixhawk 仍 `armed=false` 的直接原因（命令常落在断线窗口）。
> 修复 `rdkx5/pixhawk_link.py`：串口 drain 异常/心跳超时后立即 `close()` 并清空 master，
> 由 run loop 按 by-id 每 3s 自动重连，实测掉线恢复后无需人工重启即重新连上；同时把
> ArduPilot force arm/disarm 参数改为魔数 `21196`（原 0/1 无效）。新增只读优先的诊断工具
> `rdkx5/tools/pixhawk_arm_probe.py`（默认不 arm；`--arm` 必须同带
> `--i-confirm-propellers-removed`，成功后立即 disarm，异常走 finally 兜底）。
> 实机诊断：`ARMING_CHECK=448`（RC+板电压+电池检查）、`BATT_MONITOR=0`、RC 参数已校准；
> 正常 `MAV_CMD_COMPONENT_ARM_DISARM`（force=0）返回 `MAV_RESULT_ACCEPTED`，心跳确认
> `armed=true`；随后 normal disarm 返回 ACCEPTED，`armed=false`，闭环通过。
> 为消除 ESC“无信号”报警（桨已拆）：恢复网关后经 `/api/command` 下发 `arm`，Pixhawk
> `armed=true` 持续稳定，网关以 25Hz 持续发送中性 MANUAL_CONTROL，MAIN1–8 输出 1500
> PWM（`motors.yaml` 约定双向推进器 1500=停转）。低油门旋转实测仍需用户听音/观察确认后执行。
> 同日续测：新增 `backend/verify_motor_pulse.py`（必须显式
> `--i-confirm-propellers-removed`；异常 finally 先 stop；默认结束保持 armed）。
> 经该脚本下发 surge=+0.080、1.0s 脉冲再 stop，PC 后端→RDK→Pixhawk 全部 `ok=True`，
> Pixhawk 保持 armed=true/MANUAL；推进器是否实际旋转由用户现场目视确认。

> 2026-08-15 实测补充（第六轮，watchdog 定位 + ArduSub 遗留协议修正 + ESC 无信号定位）：
> 网关日志新增 STATUSTEXT/COMMAND_ACK 记录后，捕获到 Pixhawk 每 10s 一次
> `WDG: T-3 ...` watchdog 卡顿与 `IE47105 IEC118` 内部错误，dmesg 还出现“固件→
> bootloader→固件”的 USB 循环。隔离测试证明在无任何外部 MAVLink 流量时依然出现，
> 属固件/板卡坏状态；RDK X5 与 Pixhawk 全部断电重启后该循环消失（60s 内 0 条 WDG）。
> 同时发现并修正：ArduSub MANUAL_CONTROL 的 Z 轴是遗留范围 [0,1000]，500 才是中性，
> 原按 [-1000,1000] 发 0 会让垂直推进器输出 1700；现已按 500+heave*500 换算。
> 吸捕电机最终确认为 AUX5/AUX6、抓取舵机 AUX4，`config.yaml` 已改
> `suction_channels:[13,14]`、`servo_channel:12`。
> 为避免再次诱发 watchdog，已移除对旧固件的周期数据流请求，并给 Pixhawk 增加 1Hz GCS
> 心跳；遥测新增 `motors_pwm/aux_pwm/vcc_v/vservo_v/sensors_health`。
> 固件参数：`FRAME_CONFIG=2`、`BRD_SAFETYENABLE=0`、SERVO1–8=Motor1–8、SERVO9–11=0、
> `RC3_TRIM=1100`（异常值待处理）；Vservo≈4.48V、电机输出健康位已置位，但 8 个推进器
> 电调仍报“无信号”（约 2s 一声），当前用 AUX4 舵机做 1500→1800→1200 扫描定位是
> 输出排电气问题还是 ESC 接线/共地问题，待用户观察反馈。

## 测试总量

- 后端：27 项（数据库/鉴权/REST/UI WS/假网关回环/真网关仿真回环 + v3.0.0 升级项）。
- RDK X5 端：34 项（串口协议/死区看门狗/SERVO_OUTPUT_RAW 解析/传感器/视频仿真/网关韧性 + v3.0.0 升级项）。
- Flutter：24 项（登录流/服务层三通道/命令下发/组件）。
- 运行命令见 README.md；逐项说明见下文 v3.0.0 验证记录。

## v3.0.0 商用化升级验证记录（2026-09-19）

本轮为 v3.0.0 商用化升级（接口契约见 [UPGRADE_CONTRACTS.md](UPGRADE_CONTRACTS.md)）。
如实分层记录：自动化验证全绿、sim 模式闭环已验；**真机逐字段回传验收本轮未执行**，
待验清单见第三节，不得视为已验证。

### 一、自动化验证（全绿）

| 套件 | 数量 | 运行方式 | 覆盖要点 |
| --- | --- | --- | --- |
| backend/tests | 27 | `cd backend && python -m unittest discover -s tests -v` | 数据库鉴权/拦截、会话、用户管理、REST、UI WebSocket、假 RDK 网关回环、真实 rdkx5/gateway.py 仿真回环；本轮升级项：/api/stats 与 /api/sensors 时间范围+bucket 聚合+source 过滤（默认 rdk）、落库按 backend_mode 打 source 标、WS 强鉴权（无 token 不执行命令、auth 前不推流）、危险命令角色白名单（arm/disarm/esc_calibrate/calibrate_one_way/correct_param/motor_diagnostic/init_escs 仅 admin+）、CORS 收敛 localhost、登录返回 must_change_password、ack 载荷透传（send_command_await）、普通用户自助改密 |
| rdkx5/tests | 34 | `cd rdkx5 && python -m unittest discover -s tests -v` | 超声波 FF 协议解析、死区看门狗、SERVO_OUTPUT_RAW 解析、传感器与视频仿真管线、网关韧性；本轮升级项：set_video 宽/高/fps/质量参数校验与热生效、frame 消息 sent_ts（存在/float/≥采集时刻/随 seq 单调）、list_snapshots/fetch_snapshot（base64 回传、路径穿越拒绝）、推送循环端到端 |
| rov_flutter/test | 24 | `cd rov_flutter && flutter test` | 登录流（含首登强制改密分支）、服务层三通道（VideoFrame.linkLatencySeconds 时延计算、TelemetrySnapshot 数据年龄、连接状态机回环）、命令下发、StaleBadge 断链徽标（超时出现/恢复消失）、组件冒烟 |

静态检查：`flutter analyze` 共 66 条提示、0 error；Python 侧 `py_compile` 通过。
修复产品缺陷均由测试捕获并回归：rdk 命令 ack 丢 reply 的 NameError（回环测试捕获）、
set_video 参数被忽略、websockets>=14 优雅退出异常、disconnect() 未建立通道挂死。

### 二、sim 模式闭环（已验）

- `ROV_BACKEND_MODE=sim` 下 PC 后端 + Flutter 全链路可走通：登录 → 主控 →
  数据分析 → 设置改密；合成视频帧与遥测正常推流，传感器数据按
  `source='sim'` 落库并可经 `GET /api/sensors` 查询，`source='rdk'` 默认过滤
  生效；界面全局显示"仿真数据"角标。

### 三、真机逐字段回传验收（本轮未执行——待验清单）

以下验收**本轮未执行**，上线前须在实车环境逐项核对（步骤参照上文
"实机验收步骤"），全部通过后方可宣布"数据真实回传"验收完成：

1. **UI vs MAVLink vs SQLite 三方比对**：解锁/armed、模式、电池电压/余量、
   8 路电机 PWM、深度/水温/水压、双路水温、双路光照、双路超声距离——
   界面显示值、MAVLink 报文值、SQLite 落库值逐字段一致。
2. **≈链路时延**：UI 显示值 = 接收时刻 − `frame.sent_ts`，抽样核对为真实计算。
3. **分辨率/帧率**：`set_video` 修改后 `frame` 实际宽/高/fps/质量同步变化，
   UI 显示与帧内容一致。
4. **拔线断链徽标**：运行中拔网线，画面冻结 + "⚠ 信号丢失"徽标出现并冻结
   最后真实值；恢复网线后数据自动恢复、徽标消失。
5. **双摄切换**：camera_1/camera_2 双向切换、各自出帧、UI 显示的 camera_id
   与实际画面一致。
6. **快照链路**：实机抓拍 → `list_snapshots`/`fetch_snapshot` → 数据分析页
   快照画廊展示（含路径穿越拒绝实测）。
7. **危险命令角色拦截（真机复测）**：普通用户经 WS 与 `/api/command` 下发
   `arm` 应被拒（自动化已测，实机复测确认端到端行为）。
8. **BPU 检测框**：真实场景下 `frame.detections[]` 上屏与置信度显示。
