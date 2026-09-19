# 更新日志（Changelog）

本文件记录 SeaUI 面向用户的显著变更。格式参考 Keep a Changelog，版本号语义化。

## [3.0.0] - 2026-09-19

商用化升级大版本：数据全部真实回传、全面强鉴权、交付形态升级为免 Python 环境的一键安装包。

### 新增
- **真实数据回传**：界面展示的每个数值均溯源到真实硬件链路（RDK X5 → 后端 → 界面）；
  分辨率/帧率、链路时延（`frame.sent_ts` 端到端实测）、电池电压/余量、8 路电机 PWM、
  深度/水温/水压、双路水温/光照/超声距离、BPU 真实推理检测框等全部来自真实数据源；
  无真实来源的坐标/GPS、信号强度、功率等假值一律删除。
- **强鉴权与角色控制**：WS `command`/`set_rdk_config` 未鉴权直接拒绝执行；流式消息
  （视频帧/遥测/状态）须先完成 `auth` 才推送；危险命令（arm/disarm/esc_calibrate/
  calibrate_one_way/correct_param/motor_diagnostic/init_escs）仅 super_admin/admin 可发；
  CORS 收敛为本机来源。
- **超管首登强制改密**：登录响应新增 `must_change_password`，super_admin 仍在使用初始
  口令时客户端强制改密，改密成功前不进入主界面（初始口令支持 `ROV_SUPER_ADMIN_PASSWORD`
  环境变量随机化，交付物不含明文口令）。
- **诊断中心**：8 路电机 PWM 实时诊断、ESC 校准流程、传感器健康度（sensors_health）等
  直连真实链路。
- **数据分析真实化**：KPI/曲线/日志全部来自 SQLite `source='rdk'` 的真实记录；
  `/api/sensors` 支持时间窗（from/to）、聚合（bucket）、按名筛选与 min/max/avg 统计；
  sim 模式数据带"仿真"角标，不与真实数据混淆。
- **快照能力**：新增 `list_snapshots`/`fetch_snapshot` 命令，可浏览/回传 RDK 抓拍
  （白名单目录校验，拒绝路径穿越）。
- **打包交付**（installer/）：
  - PyInstaller onefile 打包后端为 `SeaUIBackend.exe`（内置 best.onnx，含 CUDA 库裁剪与
    onefile 路径纠偏运行时钩子），客户机器**无需安装 Python**；
  - Inno Setup 6 安装脚本 `installer/seaui.iss`：中文安装界面、桌面快捷方式（默认勾选）、
    可选开机自启动（HKCU Run）、版本 3.0.0；
  - 客户须知 `installer/README.txt` 与打包指南 `installer/README.md`。

### 修复
- **`set_video` 不生效**：分辨率/帧率/JPEG 质量参数现在真实热更新到 RDK 网关取帧链路，
  越界值返回 400 语义 ack。
- 断链感知：传感器数据超过 5 秒未更新时界面显示"信号丢失"角标并冻结最后真实值，
  数据恢复自动消失；视频帧与遥测通道分离推送，互不阻塞。

### 变更
- 管理面板统计（`/api/stats`）仅统计 `source='rdk'` 的真实传感器数据，sim 不计入。
- Flutter 服务层重构：视频帧/遥测/连接状态分通道通知，遥测合并快照限频 5Hz。
- 后端打包为独立 exe 后，数据库默认落至 `%LOCALAPPDATA%\SeaUI\data\seaUI.db`
  （可用 `ROV_DB_PATH` 覆盖），升级/卸载不丢客户数据。
