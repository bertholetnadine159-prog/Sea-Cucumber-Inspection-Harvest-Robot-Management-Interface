# SeaUI 商用化升级·接口契约 v1.0（冻结）

> 本文件是 Wave 1/2/3 所有并行智能体的唯一接口事实源。跨契约变更必须回到总控修改本文件后重发任务单。
> 铁律：**数据真实回传**——界面展示的每个数值必须溯源到真实硬件链路；禁止合成/兜底/残影数据。

## 1. 文件所有权矩阵（硬隔离，越权=返工）

| 所有者 | 独占路径 |
| --- | --- |
| A 后端 | `backend/**`（含 `backend/tests/**`） |
| B 网关 | `rdkx5/**`（含 tests、docs/UI_PROTOCOL.md、deploy/） |
| C Flutter基建 | `rov_flutter/lib/core/**`、`rov_flutter/lib/features/shared/**`、`rov_flutter/lib/main.dart`、`rov_flutter/windows/**`、`rov_flutter/android/app/src/main/AndroidManifest.xml`、`rov_flutter/pubspec.yaml`、`rov_flutter/assets/**`、`rov_flutter/tools/**` |
| D 控制页 | `rov_flutter/lib/features/auth/**`、`rov_flutter/lib/features/dashboard/desktop/{main_control_desktop,operate_desktop}.dart`、`rov_flutter/lib/features/dashboard/mobile/main_control_mobile.dart` |
| E 数据与设置 | `rov_flutter/lib/app.dart`、`rov_flutter/lib/features/dashboard/desktop/{admin_panel_desktop,data_analysis_desktop,settings_desktop}.dart`、`rov_flutter/lib/features/dashboard/mobile/{admin_panel_mobile,data_analysis_mobile,settings_mobile}.dart` |
| F 打包 | `installer/**`、`CHANGELOG.md`（新文件；backend 源码只读） |
| G 测试 | `rov_flutter/test/**`、各 tests 目录新增文件 |
| H 文档 | `README.md`、`docs/{ARCHITECTURE,VERIFICATION_STATUS}.md` |
| 总控 | `docs/UPGRADE_CONTRACTS.md`、集成与提交 |

## 2. 后端 REST API 契约（A 实现，E 消费）

### GET /api/stats（Bearer，admin 角色）
```json
{ "ok": true, "stats": {
  "users": 3, "sessions_active": 1,
  "control_logs_24h": 128, "sensor_readings_24h": 86400,
  "db_size_mb": 12.4, "uptime_s": 3600, "backend_mode": "rdk" }}
```
仅统计 `source='rdk'` 的传感器数据（真实回传），sim 不计入。

### GET /api/sensors（Bearer）
参数：`limit`（默认500，上限5000）、`from`/`to`（ISO8601 或 epoch 秒）、`bucket`（秒数，聚合窗口）、`names`（逗号分隔）、`source`（默认 `rdk`）。
返回：
```json
{ "ok": true, "source": "rdk", "series": [
  { "name": "ms5837_depth.depth_m", "unit": "m",
    "points": [{"ts": 1789123456.2, "value": 1.23}] },
  { "name": "ds18b20_water_1.temperature_c", "unit": "°C", "points": [...] }],
  "stats": { "ms5837_depth.depth_m": {"min": 1.0, "max": 2.3, "avg": 1.4} }}
```
`bucket` 存在时按窗口 AVG 聚合。`from>to` → 400。

## 3. WS 鉴权与角色规则（A 实现，D/E 遵守）
- `command`：无/无效 token → `{"type":"ack","command":...,"success":false,"message":"unauthorized"}`，**不执行**。
- `set_rdk_config`：同上，且需 admin 角色。
- 流式消息（frame/status/sensors）：连接后须先发有效 `auth` 才推送；未 auth 只回 `hello`。
- 危险命令白名单（仅 super_admin/admin）：`arm`、`disarm`、`esc_calibrate`、`calibrate_one_way`、`correct_param`、`motor_diagnostic`、`init_escs`。
- `/api/command` 同样走命令白名单 + 角色。
- CORS 收敛为 `http://127.0.0.1:*` 与 `http://localhost:*`。

## 4. 登录契约（A 实现，D 消费）
`POST /api/login` 响应新增：`"must_change_password": true|false`。
规则：当登录用户为 super_admin 且其口令等于默认初始口令（与 `ROV_SUPER_ADMIN_PASSWORD` 环境变量比较）时为 true。UI 收到 true → 强制改密对话框（调既有 `PUT /api/users/{id}/password`），改密成功前不进主界面。

## 5. RDK 网关契约（B 实现）
- `set_video`：`width/height/fps/jpeg_quality` 全部真实生效（vision.py 热更新取帧尺寸/帧率/质量），越界值回 400 语义 ack。
- `frame` 消息新增 `"sent_ts"`（网关发送时刻 epoch 秒，float）；既有 `ts` 语义=帧采集时刻。端到端时延 = 后端转发时刻/前端接收时刻 − `sent_ts`（UI 标注"≈链路时延"）。
- 新命令 `list_snapshots` → `{"ok":true,"snapshots":[{"name":"rdk_....jpg","size":12345,"ts":...}]}`；`fetch_snapshot {"name":...}` → `{"ok":true,"name":...,"jpeg":"<base64>"}`（仅允许 `rdkx5/snapshots/` 目录内文件名，拒绝路径穿越）。
- `docs/UI_PROTOCOL.md`：补全 PC↔Flutter WS 全部消息与字段（含 pixhawk 的 motors_pwm/aux_pwm/vcc_v/vservo_v/sensors_health）。

## 6. Flutter 服务层契约（C 实现，D/E 消费）
- `RovBackendService` 重构：
  - `ValueNotifier<VideoFrame?> videoFrameNotifier` —— 帧数据专用，页面只监听它，**不再触发全局 notifyListeners**；
  - `ValueNotifier<TelemetrySnapshot?> telemetryNotifier` —— status/sensors 合并快照，5Hz 上限；
  - 每个通道携带 `lastUpdated`（本地接收时刻）。
- `StaleBadge`（C 提供的共享组件）：`age > 5s` → 显示"⚠ 信号丢失"，冻结最后真实值；数据恢复自动消失。
- 连接状态：`connectionNotifier`（connected/reconnecting/offline）。
- `strings.dart`：新增 `lib/core/l10n/strings.dart` 常量类，页面文案逐步集中（本轮不强制全量）。

## 7. 数据溯源矩阵（终验逐条核对）

| UI 展示 | 上游真实来源 | 无源处置 |
| --- | --- | --- |
| 分辨率/帧率 | `frame.width/height/fps` | 删除假值 |
| ≈链路时延 | `now - frame.sent_ts` | 真实计算 |
| 解锁/模式 | `telemetry.pixhawk.armed/mode` | — |
| 电池电压/余量 | `pixhawk.battery_v/battery_remaining` | 删除假值 |
| 8路电机PWM | `pixhawk.motors_pwm` | — |
| 深度/水温水压 | `sensors.ms5837_depth.*` | 断链→StaleBadge |
| 双路水温 | `sensors.ds18b20_*.temperature_c` | 同上 |
| 双路光照 | `sensors.veml7700_*.lux` | 同上 |
| 双路超声距离 | `sensors.ultrasonic_*.distance_m` | 同上 |
| 检测框/置信度 | `frame.detections[]`（BPU 真实推理） | — |
| KPI/曲线/日志 | SQLite `source='rdk'` 记录 | sim 标注"仿真"角标 |
| ~~坐标/GPS~~、~~信号强度~~、~~功率~~ | 无真实来源 | **删除** |

## 8. sim/rdk 隔离
- 落库：backend 按 `ROV_BACKEND_MODE` 打 `source`（rdk/local/sim）。
- 查询：`/api/sensors`、`/api/stats` 默认 `source='rdk'`。
- UI：backend_mode == 'sim' 时全页角标"仿真数据"（黄色），rdk 模式无角标。

## 9. 质量门槛（所有智能体）
- Python：遵循仓库既有安全模式（URL 白名单+解析 IP 校验+禁重定向，参照 backend/verify_live.py）；`python -m py_compile` 通过；新增逻辑带单测。
- Dart：`flutter analyze` 不新增 error/warning；不引入新重度依赖（window_manager 例外，C 专属）。
- 安全钩子（Mimosa）可能拦截写入：若被拦，按其建议改成安全写法后重试，不得绕过。
- 中文注释/文案；提交粒度小步；不动所有权外文件。
