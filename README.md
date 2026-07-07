# SeaUI 海参检测及吸捕机器人控制系统

SeaUI 是面向海参养殖与水下巡检场景的 ROV 管理与智能识别系统。项目围绕“端侧 AI 检测、无损吸捕、多传感器协同、远程控制”构建，配合海参吸捕机器人实现水下视频回传、目标识别、设备控制、环境数据分析和操作日志管理。

本项目介绍整理自《中国国际大学生创新大赛项目计划书0606(2).docx》。计划书中的核心目标是研发一款面向海参养殖场景的端侧 AI 海参智能检测与无损吸捕机器人，通过轻量化实例分割模型、八推进器全向矢量推进结构、负压吸捕装置和地面控制软件，降低人工潜水采捕的风险与成本，并为养殖户提供“捕捞 + 检测 + 环境档案”的一体化服务。

## 核心能力

- Flutter 跨平台控制端：支持 Windows 桌面端和移动端布局，包含登录、主控、控制操作、数据分析、管理员与设置页面。
- Python 推理后端：基于 Ultralytics YOLO 加载 `best.onnx`，对本地视频或摄像头画面进行实例分割推理，并通过 WebSocket 推送标注帧。
- ROV 控制服务：封装前进、后退、左右转、上浮、下潜、抓取、释放、照明、声呐、激光测距、自动巡航和紧急停止等控制命令。
- 数据看板：读取环境数据、系统日志和用户角色样例数据，展示水温、盐度、PH、气压、报警和巡检记录。
- 开源友好配置：后端模型、视频源、WebSocket 地址和推理阈值均可通过环境变量覆盖。

## 项目结构

```text
.
├── backend/                 # Python YOLO/WebSocket 推理后端
├── rov_flutter/             # Flutter ROV 控制端
├── 1.app/                   # 移动端页面设计导出
├── 1.win/                   # 桌面端页面设计导出
├── best.onnx                # 海参检测模型示例权重
├── start_rover.bat          # Windows 一键启动脚本
├── LICENSE
└── README.md
```

## 快速开始

### 1. 安装 Python 依赖

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

### 2. 准备视频源

后端默认读取本机摄像头 `0`。也可以用环境变量指定待检测视频、RTSP/HTTP 流或其他摄像头索引：

```bash
set ROV_VIDEO_SOURCE=D:\path\to\underwater-input.mp4
set ROV_MODEL_PATH=D:\path\to\best.onnx
```

`output.MP4` 是分割检测验证结果视频，不作为默认待检测输入源，也不会默认发布到仓库。

### 3. 启动后端

```bash
cd backend
python app.py
```

默认 WebSocket 地址为：

```text
ws://localhost:8765
```

可选配置：

```bash
set ROV_WS_HOST=localhost
set ROV_WS_PORT=8765
set ROV_VIDEO_SOURCE=0
set ROV_CONF_THRESH=0.25
set ROV_JPEG_QUAL=80
```

### 4. 启动 Flutter 客户端

```bash
cd rov_flutter
flutter pub get
flutter run -d windows
```

Windows 用户也可以在仓库根目录运行：

```bash
start_rover.bat
```

## 技术栈

- Flutter / Dart
- Python 3
- OpenCV
- Ultralytics YOLO
- ONNX Runtime
- WebSocket

## 开源协议

本项目使用 MIT License 开源，详见 [LICENSE](LICENSE)。
