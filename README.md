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
├── rov_flutter/             # Flutter 桌面/移动端界面
├── docs/ARCHITECTURE.md     # 软件框架说明
├── reference/               # 参考开源仓库克隆（研究用，不入库）
├── best.onnx                # 旧版 PC 本地推理模型（local 模式使用）
└── open_seaUI.bat           # Windows 一键启动脚本
```

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
```

11 项测试覆盖：超级管理员初始化与鉴权拦截、会话、用户管理、
传感器/控制日志入库、REST 接口、UI WebSocket、假 RDK 网关回环联调。

## 相关开源仓库

- [Sunrise5-Based-Sea-Cucumber-Inspection-and-Suction-Harvest-Robot](https://github.com/bertholetnadine159-prog/Sunrise5-Based-Sea-Cucumber-Inspection-and-Suction-Harvest-Robot)
- [Model-weight-conversion](https://github.com/bertholetnadine159-prog/Model-weight-conversion)
- [RDK X5 官方文档中心](https://developer.d-robotics.cc/rdk_doc_center/)
