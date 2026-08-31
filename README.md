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
- SQLite 数据库：管理员账号、会话、传感器数据、控制日志、设置
- 登录拦截：用户名/密码缺失或错误一律阻止进入，不再放行访客

## 目录结构

```text
.
├── backend/                 # PC 端 Python 桥接服务 + SQLite + REST + 测试
├── rdkx5/                   # [RDK X5 side] 板卡网关（摄像头/YOLO/传感器/Pixhawk）
├── control/                 # [RDK X5 side] 机器人控制工程（配置/传感器/视觉对中/
│                            #   推进器混控/吸捕/任务状态机，实车自主流程入口）
├── rov_flutter/             # Flutter 桌面/移动端界面
├── docs/ARCHITECTURE.md     # 软件框架说明
├── reference/               # 参考仓库克隆（研究用，不入库）
├── best.onnx                # 旧版 PC 本地推理模型（local 模式使用）
└── open_seaUI.bat           # Windows 一键启动脚本
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

登录：超级管理员用户名 `zmm`，密码 `Zmm771023`（首次启动自动写入数据库）。

## RDK X5 部署

板卡网口默认静态 IP `192.168.127.10`，PC 网口配成同网段。部署与运行：

```bash
scp -r rdkx5 sunrise@192.168.127.10:/home/sunrise/seaUI_rdk
ssh sunrise@192.168.127.10
cd /home/sunrise/seaUI_rdk && ./run_robot.sh
```

详细接线、检查项、安全说明见 [rdkx5/README.md](rdkx5/README.md)，
通信协议见 [rdkx5/PROTOCOL.md](rdkx5/PROTOCOL.md)。

## 测试

```bash
cd backend
python -m unittest discover -s tests -v

cd ../rdkx5
python -m unittest discover -s tests -v
```

共 19 项测试覆盖：超级管理员初始化与鉴权拦截、会话、用户管理、
传感器/控制日志入库、REST 接口、UI WebSocket、假 RDK 网关回环、
**真实 rdkx5/gateway.py 仿真回环**（视频/遥测/命令），以及 RDK 端的
超声波协议解析、死区看门狗、传感器与视频仿真管线。

## 相关开源仓库

- [Model-weight-conversion](https://github.com/bertholetnadine159-prog/Model-weight-conversion)
- [Sunrise5-Based-Sea-Cucumber-Inspection-and-Suction-Harvest-Robot](https://github.com/bertholetnadine159-prog/Sunrise5-Based-Sea-Cucumber-Inspection-and-Suction-Harvest-Robot)
  （其 `sea_cucumber_robot` 控制工程已并入本仓库 `control/`，该仓库仅作留档，不再单独更新）
- [RDK X5 官方文档中心](https://developer.d-robotics.cc/rdk_doc_center/)
