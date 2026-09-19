# SeaUI 海参检测及吸捕机器人控制系统

面向海参养殖与水下巡检场景的 ROV 管理与智能识别系统。

控制链：**SeaUI 桌面软件（PC）→ 网线 → 地瓜机器人 RDK X5 → MAVLink → Pixhawk 2.4.8**。

## 核心能力

- Flutter 跨平台控制端：登录、主控、控制操作、数据分析、管理员与设置页面
- RDK X5 边缘推理：MIPI/USB 摄像头 + BPU 上运行 YOLO11 海参分割模型
  （`rdkx5/YOLO11_LBL.bin`），标注后视频经 WebSocket 实时回传，**PC 不再跑 ONNX**
- RDK X5 控制服务：MAVLink 控制 Pixhawk 2.4.8 的 8 路推进器、吸捕电机与舵机
- 传感器回传：VEML7700 光照、MS5837 深度/压力、DS18B20 水温、LO81MTW 超声波
  （全部接在 RDK X5 上）
- SQLite 数据库：管理员账号、会话、传感器数据（按 `source` 标记数据来源）、控制日志、设置
- 登录拦截：用户名/密码缺失或错误一律阻止进入，不再放行访客

## v3.0.0 商用化要点

- **数据真实回传**：界面每个数值均溯源到真实硬件链路（RDK X5 → 后端 → 界面）。
  分辨率/帧率、链路时延（`frame.sent_ts` 端到端实测）、电池电压/余量、8 路电机
  PWM、深度/水温/光照/超声距离、BPU 真实推理检测框均来自真实数据源；无真实
  来源的坐标/GPS、信号强度、功率等假值已全部删除。
- **强鉴权**：WS 未带有效 token 不执行命令、`auth` 完成前不推送视频/遥测流；
  arm/disarm/esc_calibrate 等危险命令仅 super_admin/admin 可发；CORS 收敛为
  本机回环来源。
- **首登强制改密**：super_admin 仍使用初始口令登录时，后端返回
  `must_change_password`，客户端强制改密后方可进入主界面；普通用户可在设置页
  自助改密。
- **数据分析真实化**：KPI/曲线/统计摘要均来自 SQLite `source='rdk'` 的真实记录，
  支持时间范围、聚合窗口、多传感器筛选、CSV 导出与快照画廊；sim 模式全局
  显示"仿真数据"角标，不与真实数据混淆。
- **界面流畅化**：视频/遥测/连接三通道独立通知，消除每帧全页重建；数据断链
  超过 5 秒显示"⚠ 信号丢失"徽标并冻结最后真实值，恢复后自动消失。
- **打包交付**：PyInstaller onefile 后端 + Inno Setup 安装包，客户机器无需
  Python 环境，详见 [installer/README.md](installer/README.md)。

## 目录结构

```text
.
├── backend/                 # PC 端 Python 桥接服务 + SQLite + REST + 测试
├── rdkx5/                   # [RDK X5 side] 板卡网关（摄像头/YOLO/传感器/Pixhawk）
│   ├── docs/UI_PROTOCOL.md  # PC ↔ Flutter WS 全字段通信协议
│   └── deploy/              # systemd 单元与部署说明（seaui-gateway.service）
├── control/                 # [RDK X5 side] 机器人控制工程（配置/传感器/视觉对中/
│                            #   推进器混控/吸捕/任务状态机，实车自主流程入口）
├── rov_flutter/             # Flutter 桌面/移动端界面
├── installer/               # Windows 安装包打包工程（PyInstaller + Inno Setup）
├── docs/ARCHITECTURE.md     # 软件框架说明
├── docs/UPGRADE_CONTRACTS.md # v3.0.0 商用化升级接口契约（冻结事实源）
├── reference/               # 参考仓库克隆（研究用，不入库）
├── best.onnx                # 旧版 PC 本地推理模型（local 模式使用）
└── open_seaUI.bat           # Windows 一键启动脚本（开发者模式）
```

## 控制工程（control/）

`control/` 即原 Sunrise5 控制仓库的 `sea_cucumber_robot` 完整工程，现已并入本仓库，
与上位机系统组成"控制 + 系统"一体项目，控制侧修改直接在本仓库进行，不再单独推送：

- `config/`：硬件、电机输出（MAIN1-8 / AUX）、视觉、PID 控制、任务参数
- `src/sea_cucumber_robot/`：传感器读取、海参分割、mask 对中 PID、推进器混控、
  Pixhawk MAVLink 输出、吸捕控制、`INIT→搜索→对中→接近5.5cm→切换吸口
  摄像头→吸捕→完成` 任务状态机
- `scripts/`、`tests/`：实机检查脚本与核心逻辑单元测试

运行方式见 [control/README.md](control/README.md)。

## 快速开始（PC）

### 安装版（客户交付）

运行安装包 `SeaUI-Setup-3.0.0.exe`（由 [installer/](installer/README.md) 工程产出），
按向导安装后双击 `SeaUI.exe` 即可：客户端自动拉起内置后端，客户机器**无需
Python 环境**。运行模式、端口、数据位置与常见问题见随包 `README.txt`。

### 开发者模式

依赖：Python 3.10+（`opencv-python onnxruntime numpy ultralytics websockets`），
双击 [open_seaUI.bat](open_seaUI.bat) 直接打开已编译的 Release 桌面程序。
需要重新构建时使用 `open_seaUI.bat /rebuild`。

后端默认 `ROV_BACKEND_MODE=rdk`，会连接 RDK X5 的
`ws://192.168.127.10:8080`；在设置页可修改 IP/端口。

无硬件联调：

```bash
set ROV_BACKEND_MODE=sim
python backend\app.py
```

登录：首次启动自动创建超级管理员，请通过环境变量
`ROV_SUPER_ADMIN_PASSWORD` 预置初始口令（正式部署必须设置，勿沿用默认值）；
super_admin 首登将强制修改口令，普通用户可在设置页自助改密。

## RDK X5 部署

板卡网口默认静态 IP `192.168.127.10`，PC 网口配成同网段。部署与运行：

```bash
scp -r rdkx5 sunrise@192.168.127.10:/home/sunrise/seaUI_rdk
ssh sunrise@192.168.127.10
cd /home/sunrise/seaUI_rdk && ./run_robot.sh
```

详细接线、检查项、安全说明见 [rdkx5/README.md](rdkx5/README.md)，
通信协议见 [rdkx5/PROTOCOL.md](rdkx5/PROTOCOL.md) 与
[rdkx5/docs/UI_PROTOCOL.md](rdkx5/docs/UI_PROTOCOL.md)。
长期部署可用 systemd 常驻（开机自启、断线自动重启），见
[rdkx5/deploy/README.md](rdkx5/deploy/README.md)。

## 测试

```bash
cd backend
python -m unittest discover -s tests -v

cd ../rdkx5
python -m unittest discover -s tests -v

cd ../rov_flutter
flutter test
```

共 85 项测试全绿：后端 27 项（数据库鉴权/拦截、会话、用户管理、REST、
UI WebSocket、假 RDK 网关回环、真实 rdkx5/gateway.py 仿真回环，以及本轮
stats/sensors 聚合与 source 过滤、WS 强鉴权与角色白名单、
must_change_password、ack 载荷透传与自助改密等升级用例）、
RDK X5 端 34 项（超声波协议解析、死区看门狗、传感器与视频仿真管线，
以及 set_video 参数热生效、frame.sent_ts、快照命令与路径穿越防护等
升级用例）、Flutter 24 项（登录流、服务层三通道与时延计算、命令下发、
StaleBadge 断链徽标与组件冒烟）。另 `flutter analyze` 0 error。

## 相关开源仓库

- [Model-weight-conversion](https://github.com/bertholetnadine159-prog/Model-weight-conversion)
- [Sunrise5-Based-Sea-Cucumber-Inspection-and-Suction-Harvest-Robot](https://github.com/bertholetnadine159-prog/Sunrise5-Based-Sea-Cucumber-Inspection-and-Suction-Harvest-Robot)
  （其 `sea_cucumber_robot` 控制工程已并入本仓库 `control/`，该仓库仅作留档，不再单独更新）
- [RDK X5 官方文档中心](https://developer.d-robotics.cc/rdk_doc_center/)
