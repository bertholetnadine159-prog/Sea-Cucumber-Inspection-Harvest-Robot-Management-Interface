# RDK X5 网关（SeaUI <-> RDK X5 <-> Pixhawk）

> **本目录全部代码运行在地瓜机器人 RDK X5（Sunrise 5）上。**
> 运行前请确认板卡系统镜像为 Ubuntu 22.04 + RDK OS，且已包含
> `hobot_dnn`（BPU 推理）。摄像头支持 USB UVC（推荐）与 MIPI
> （`srcampy` / `hobot_vio`，可选）。

## 控制链

```text
SeaUI 桌面软件 (PC)
    |
    | 网线直连 192.168.127.10:8080 (WebSocket)
    v
RDK X5 网关 (rdkx5/)
    |-- 双摄像头(camera_1 前视 / camera_2 吸口近距) -> BPU YOLO11 分割
    |        -> 标注 JPEG 视频流（set_camera 切换）
    |-- I2C/串口传感器 -> 遥测 JSON
    |-- MAVLink（by-id 自动解析 Pixhawk 串口，掉电重插不改号）
    v
Pixhawk 2.4.8 (ArduSub / PX4) -> 8 路推进器 + 吸捕电机 + 舵机
```

## 部署到 RDK X5

```bash
# 1) 通过 SSH 进入板卡（默认 sunrise / sunrise，IP 192.168.127.10）
ssh sunrise@192.168.127.10

# 2) 上传本目录 + 自检 + 启动网关（推荐在 PC 上一键执行）
python rdkx5/scripts/deploy_to_board.py --check --start-gateway

# 3) 板卡上运行
cd /home/sunrise/seaUI_rdk
sudo usermod -aG dialout,video,i2c $USER   # 之后重新登录
./run_robot.sh
```

## 检查项

```bash
# 网络：PC 端应能 ping 通 192.168.127.10
ping 192.168.127.10

# Pixhawk 串口（掉电重插可能改号为 /dev/ttyACM1，网关会按 by-id 自动找到）
ls -l /dev/ttyACM*

# 摄像头 / 传感器
ls /dev/video* /dev/i2c-* /dev/ttyUSB* 2>/dev/null
sudo i2cdetect -y 0
sudo i2cdetect -y 1
sudo i2cdetect -y 5
```

## 双摄像头

配置见 `config.yaml` 的 `cameras`：`camera_1`（前视，默认打开）与
`camera_2`（吸口近距，靠近后切换）。`device: auto` 会自动探测 UVC
采集节点并跳过 metadata 节点；两只摄像头按系统枚举顺序对应
camera_1 / camera_2。若前后位置与枚举顺序不一致，把 `device` 改为
固定的 `/dev/videoN`：

```yaml
cameras:
  camera_1: {device: /dev/video0, ...}   # 前视
  camera_2: {device: /dev/video2, ...}   # 吸口近距（UVC 摄像头间隔 2 个节点）
```

PC/界面切换：发 `set_camera {camera_id: camera_2}`，桌面/手机主界面
均有“前视相机 / 吸口相机”按钮。第二只摄像头未插入时切换会返回失败并
自动保持当前摄像头。

## 传感器接线前准备

`config.yaml` 的 `sensors` 已给出默认地址：VEML7700 两路 `0x10`
（bus 5 / bus 0）、MS5837 `0x76`（bus 1）、DS18B20 两路、LO81MTW
超声波两路（`/dev/ttyUSB0`、`/dev/ttyUSB1`）。接线后先确认：

- I2C：`sudo i2cdetect -y 0/1/5` 应扫到对应地址；
- DS18B20：需在板卡设备树启用 w1-gpio 并重启，`/sys/bus/w1/devices`
  下出现 `28-xxx`；若有两个探头，在 config 里填 `device_id` 区分；
- 超声波：插入 USB 转 RS485 后应出现 `/dev/ttyUSB0` / `/dev/ttyUSB1`。

## 关键文件

| 文件 | 说明 |
| --- | --- |
| `gateway.py` | 主程序 |
| `stream_server.py` | WebSocket 视频/遥测/命令通道 |
| `vision.py` | 双摄像头管理（UVC 自动探测 + set_camera 切换）、BPU 分割推理、JPEG 编码 |
| `pixhawk_link.py` | MAVLink 控制（MANUAL_CONTROL / DO_SET_SERVO）+ 死区看门狗 + 掉线自动重连 |
| `sensors.py` | VEML7700 / MS5837 / DS18B20 / LO81MTW |
| `yolo11_seg_rdk.py` | 从 Model-weight-conversion 仓库来的 BPU 推理脚本 |
| `YOLO11_LBL.bin` | 已量化的海参 YOLO11 分割模型 |
| `config.yaml` | 全部硬件接线与运行参数 |
| `PROTOCOL.md` | PC <-> RDK X5 通信协议 |
| `check_hardware.py` | 实机一键自检（网络/设备/依赖/传感器/Pixhawk/BPU/端口） |
| `tools/pixhawk_arm_probe.py` | arm 诊断（默认只读；读 PreArm/STATUSTEXT/COMMAND_ACK，可无桨闭环测试 arm→disarm） |

## 安全说明

- Pixhawk 启动时保持未解锁，PC 需显式发送 `arm`。
- `move` 带 `deadman_ms`，断链超时自动回中。
- `pixhawk_link.py` 在 USB 掉线/心跳超时后自动 close 并按 by-id 重连；
  ArduPilot force arm/disarm 使用魔数 `21196`。
- 无桨 arm 测试用 `python3 tools/pixhawk_arm_probe.py --arm --i-confirm-propellers-removed`，
  成功后脚本立即 disarm；只读诊断时不要加 `--arm`。
- 下水前务必在 `config.yaml` 校准推进器通道与方向，先做水池空载测试。

## 实机自检

拿到板卡并接好硬件后，先跑一遍自检再启动网关：

```bash
cd /home/sunrise/seaUI_rdk
python3 check_hardware.py --config config.yaml
```

全部 PASS 后再执行 `./run_robot.sh`。逐项排查时也可用 `--simulate` 验证脚本本身。
