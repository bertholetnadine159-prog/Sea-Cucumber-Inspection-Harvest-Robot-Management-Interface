# 目标验收状态清单（需求 → 证据 → 状态）

> 更新：2026-08-15。绿色 = 已离线验证；黄色 = 代码完成但需实机验证。

| # | 需求 | 证据 | 状态 |
| --- | --- | --- | --- |
| 1 | RDK X5 摄像头画面进主界面，UI 不再跑 ONNX | `rdkx5/vision.py`（MIPI→BPU→JPEG→WS）；`backend/app.py` 默认 `rdk` 模式；真实网关仿真回环测试通过；实机 MIPI 待验证 | 黄色 |
| 2 | 优化 Pixhawk 控制仓库，链路为 软件→X5→Pixhawk | GitHub 已推送 `5bbd0db`；`rdkx5/pixhawk_link.py`；后端命令翻译 + 死区看门狗；实机 MAVLink 待验证 | 黄色 |
| 3 | 网线两边通信，RDK 代码标注 | `rdkx5/*.py` 头部 `[RDK X5 side]`；`PROTOCOL.md`；`backend/rdk_client.py`；回环测试通过；实机网线联调待验证 | 黄色 |
| 4 | 网线传输 YOLO 部署后视频流 | 协议选 WebSocket+JPEG（官方 web 显示示例同源）；`test_rdk_gateway_loopback` 通过；实机 BPU 帧待验证 | 黄色 |
| 5 | RDK X5 上传感器全部回传 | `rdkx5/sensors.py`；遥测→SQLite→界面/分析页；sim 遥测落库实测通过；实机 I2C/串口读数待验证 | 黄色 |
| 6 | 调研官方/GitHub 方案并更新控制程序 | 官方 srcampy/hobot_dnn/web 显示示例、hobot_websocket、ArduSub MANUAL_CONTROL；已实现并推送 | 绿色 |
| 7 | 管理员与传感器数据入库，登录拦截，超管 zmm/Zmm771023 | `backend/database.py` + REST + Flutter 登录/管理员/日志接线；19 项测试通过；空/错密码 401 实测 | 绿色 |
| 8 | 说明软件框架 | `docs/ARCHITECTURE.md`、DOCX、PDF，已推送 | 绿色 |
| 9 | @documents @pdf | DOCX/PDF 已交付并通过内容/几何质检（DOCX 无 LibreOffice 渲染目检，已声明） | 绿色 |

## 实机验收步骤（恢复后执行）

1. 网线连接板卡并上电；`rdkx5/scripts/setup_pc_network.ps1 -Check` 应看到 Realtek 网卡 Up。
2. `-Apply` 配置 `192.168.127.100/24`；`ping 192.168.127.10` 通。
3. `scp -r rdkx5 sunrise@192.168.127.10:/home/sunrise/seaUI_rdk`。
4. 板卡上 `python3 check_hardware.py --config config.yaml` 全 PASS。
5. `./run_robot.sh` 启动网关；PC 双击 `open_seaUI.bat`。
6. 主界面确认：视频流、YOLO 标注、传感器数值、RDK X5 已连接；操作页发命令确认 Pixhawk 动作。

> 2026-08-15 实测补充：板卡已上电并在线，网卡链路 Up(1Gbps)，mDNS 可解析
> `ubuntu.local -> 192.168.127.10`；但 PC 以太网网卡仍为 APIPA
> `169.254.107.34/16`，尚未配置 `192.168.127.100/24`，因此 IP 层不可达。
> 阻塞点仅剩：以管理员运行 `setup_pc_network.ps1 -Apply`。

## 测试总量

- 后端：12 项（数据库/鉴权/REST/UI WS/假网关回环/真网关仿真回环）。
- RDK X5 端：7 项（串口协议/死区看门狗/传感器/视频仿真）。
- 运行命令见 README.md。
