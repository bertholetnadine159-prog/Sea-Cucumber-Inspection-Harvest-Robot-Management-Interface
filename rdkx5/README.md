# RDK X5 网关（SeaUI <-> RDK X5 <-> Pixhawk）

> **本目录全部代码运行在地瓜机器人 RDK X5（Sunrise 5）上。**
> 运行前请确认板卡系统镜像为 Ubuntu 22.04 + RDK OS，且已包含
> `hobot_dnn`（BPU 推理）与 `srcampy`（MIPI 摄像头，可选）。

## 控制链

```text
SeaUI 桌面软件 (PC)
    |
    | 网线直连 192.168.127.10:8080 (WebSocket)
    v
RDK X5 网关 (rdkx5/)
    |-- MIPI/USB 摄像头 -> BPU YOLO11 分割 -> 标注 JPEG 视频流
    |-- I2C/串口传感器 -> 遥测 JSON
    |-- MAVLink /dev/ttyACM0
    v
Pixhawk 2.4.8 (ArduSub / PX4) -> 8 路推进器 + 吸捕电机 + 舵机
```

## 部署到 RDK X5

```bash
# 1) 通过 SSH 进入板卡（默认 sunrise / sunrise，IP 192.168.127.10）
ssh sunrise@192.168.127.10

# 2) 上传本目录（用 scp / U盘 / git 均可）
#    PC 上执行：
scp -r rdkx5 sunrise@192.168.127.10:/home/sunrise/seaUI_rdk

# 3) 板卡上运行
cd /home/sunrise/seaUI_rdk
sudo usermod -aG dialout,video,i2c $USER   # 之后重新登录
./run_robot.sh
```

## 检查项

```bash
# 网络：PC 端应能 ping 通 192.168.127.10
ping 192.168.127.10

# Pixhawk 串口（插入后应出现 /dev/ttyACM0）
ls -l /dev/ttyACM*

# 摄像头 / 传感器
ls /dev/video* /dev/i2c-* /dev/ttyUSB* 2>/dev/null
sudo i2cdetect -y 0
sudo i2cdetect -y 5
```

## 关键文件

| 文件 | 说明 |
| --- | --- |
| `gateway.py` | 主程序 |
| `stream_server.py` | WebSocket 视频/遥测/命令通道 |
| `vision.py` | 摄像头采集、BPU 分割推理、JPEG 编码 |
| `pixhawk_link.py` | MAVLink 控制（MANUAL_CONTROL / DO_SET_SERVO）+ 死区看门狗 |
| `sensors.py` | VEML7700 / MS5837 / DS18B20 / LO81MTW |
| `yolo11_seg_rdk.py` | 从 Model-weight-conversion 仓库来的 BPU 推理脚本 |
| `YOLO11_LBL.bin` | 已量化的海参 YOLO11 分割模型 |
| `config.yaml` | 全部硬件接线与运行参数 |
| `PROTOCOL.md` | PC <-> RDK X5 通信协议 |
| `check_hardware.py` | 实机一键自检（网络/设备/依赖/传感器/Pixhawk/BPU/端口） |

## 安全说明

- Pixhawk 启动时保持未解锁，PC 需显式发送 `arm`。
- `move` 带 `deadman_ms`，断链超时自动回中。
- 下水前务必在 `config.yaml` 校准推进器通道与方向，先做水池空载测试。

## 实机自检

拿到板卡并接好硬件后，先跑一遍自检再启动网关：

```bash
cd /home/sunrise/seaUI_rdk
python3 check_hardware.py --config config.yaml
```

全部 PASS 后再执行 `./run_robot.sh`。逐项排查时也可用 `--simulate` 验证脚本本身。
