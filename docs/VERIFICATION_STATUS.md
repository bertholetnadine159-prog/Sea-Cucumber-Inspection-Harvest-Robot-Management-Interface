# 目标验收状态清单（需求 → 证据 → 状态）

> 更新：2026-08-15。绿色 = 已离线验证；黄色 = 代码完成但需实机验证。

| # | 需求 | 证据 | 状态 |
| --- | --- | --- | --- |
| 1 | RDK X5 摄像头画面进主界面，UI 不再跑 ONNX | 双摄实机全部验证：camera_1→/dev/video0、camera_2→/dev/video2 均能打开出帧，`set_camera` 双向切换成功；真实 1280×720 帧经 backend 到达 UI WS | 绿色 |
| 2 | 优化 Pixhawk 控制仓库，链路为 软件→X5→Pixhawk | GitHub 已推送 `d0cdc16`；`rdkx5/pixhawk_link.py`（by-id 解析 + 自动重连）；实机 MAVLink 已通（connected/MANUAL）；电机已接入，超管登录→后端→RDK→Pixhawk 的 stop/中性 PWM 命令链路 ok=True，带电旋转测试待用户确认桨叶拆除后执行 | 黄色 |
| 3 | 网线两边通信，RDK 代码标注 | `rdkx5/*.py` 头部 `[RDK X5 side]`；`PROTOCOL.md`；`backend/rdk_client.py`；回环测试通过；实机网线联调已通过（ping/SSH/8080） | 绿色 |
| 4 | 网线传输 YOLO 部署后视频流 | WebSocket+JPEG；`test_rdk_gateway_loopback` 通过；实机 BPU 加载 + 逐帧推理已通过，JPEG 帧实时经网线到达 PC（帧内含 detections，当前场景无海参故为空） | 绿色 |
| 5 | RDK X5 上传感器全部回传 | `rdkx5/sensors.py`；遥测→SQLite→界面/分析页；sim 遥测落库实测通过；实机 I2C/串口读数待验证 | 黄色 |
| 6 | 调研官方/GitHub 方案并更新控制程序 | 官方 srcampy/hobot_dnn/web 显示示例、hobot_websocket、ArduSub MANUAL_CONTROL；已实现并推送 | 绿色 |
| 7 | 管理员与传感器数据入库，登录拦截，超管 zmm/Zmm771023 | `backend/database.py` + REST + Flutter 登录/管理员/日志接线；19 项测试通过；空/错密码 401 实测 | 绿色 |
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

## 测试总量

- 后端：12 项（数据库/鉴权/REST/UI WS/假网关回环/真网关仿真回环）。
- RDK X5 端：9 项（串口协议/死区看门狗/传感器/视频仿真/网关韧性）。
- 运行命令见 README.md。
