#!/usr/bin/env python3
"""
ROV后端服务示例
与Flutter前端通过WebSocket通信

功能：
1. 接收控制命令（前进/后退/上浮/下潜等）
2. 发送视频流（YOLO检测/分割并直接在画面上标注）
3. 两点距离估计

依赖安装：
pip install websockets opencv-python numpy ultralytics

使用方法：
# 默认使用 yolo11n-seg 分割模型（首次运行自动下载）
python rov_backend_server.py

# 使用自定义模型
python rov_backend_server.py --model path/to/custom.pt

# 使用视频文件
python rov_backend_server.py --video test.mp4

# 演示模式（无模型）
python rov_backend_server.py --no-model

支持的模型格式：
- .pt (PyTorch) - 推荐，首次加载自动下载
- .onnx (ONNX Runtime)

默认模型 yolo11n-seg.pt：
- YOLOv11 nano 分割模型
- 支持实例分割（检测框 + 分割掩码）
- 80个COCO类别
"""

import asyncio
import json
import base64
import time
import argparse
from pathlib import Path
from typing import Optional, Dict, Any, Set, List, Tuple
import cv2
import numpy as np

import sys

# WebSocket库
try:
    import websockets
except ImportError:
    print("Please install websockets: pip install websockets")
    exit(1)

# Ultralytics YOLO - supports custom builds with extra_modules
# We defer the actual import to load_model() so we can inject sys.path first
YOLO_AVAILABLE = False
YOLO = None

def _try_import_yolo(custom_pkg_dir: str = None):
    """Import YOLO, preferring custom ultralytics if path is provided."""
    global YOLO, YOLO_AVAILABLE
    if custom_pkg_dir and custom_pkg_dir not in sys.path:
        sys.path.insert(0, custom_pkg_dir)
    try:
        from ultralytics import YOLO as _YOLO
        YOLO = _YOLO
        YOLO_AVAILABLE = True
    except ImportError as e:
        YOLO_AVAILABLE = False
        print(f"WARNING: ultralytics not available: {e}")

# Try standard import on startup; custom path injected when model loads
_try_import_yolo()


class YOLODetector:
    """YOLO实例分割检测器 - 使用 best.pt + cv2 手动绘制mask"""

    # 每个实例的颜色池（BGR）
    INSTANCE_COLORS = [
        (0, 200, 255),   # 橙黄
        (0, 255, 128),   # 青绿
        (255, 80,  80),  # 蓝紫
        (80,  80, 255),  # 红
        (200, 0, 200),   # 品红
        (0, 220, 220),   # 黄
        (255, 200,  0),  # 天蓝
        (100, 255, 100), # 浅绿
    ]

    def __init__(self, model_path: Optional[str] = None, conf_threshold: float = 0.35):
        self.model = None
        self.model_path = model_path
        self.conf_threshold = conf_threshold
        self.classes: List[str] = []
        if model_path:
            self.load_model(model_path)
    
    def load_model(self, model_path: str, custom_pkg_dir: str = None) -> bool:
        """Load best.pt. Pass custom_pkg_dir for models that need extra_modules."""
        if custom_pkg_dir:
            _try_import_yolo(custom_pkg_dir)

        if not YOLO_AVAILABLE:
            print("[YOLO] ERROR: ultralytics not installed.")
            return False
        try:
            self.model = YOLO(model_path)
            self.model_path = model_path
            self.classes = list(self.model.names.values())
            print(f"[YOLO] Loaded: {model_path} | task={self.model.task} | classes={self.classes}")
            return True
        except Exception as e:
            print(f"[YOLO] Load failed: {e}")
            self.model = None
            return False

    def detect_and_annotate(self, frame: np.ndarray) -> Tuple[np.ndarray, List[Dict]]:
        """
        Run YOLO instance segmentation on a frame and draw results with cv2.
        Returns (annotated_frame, detections_list).
        """
        if self.model is None:
            return frame, []

        try:
            results = self.model(frame, conf=self.conf_threshold, verbose=False)
            result = results[0]

            annotated = frame.copy()
            detections: List[Dict] = []
            h, w = frame.shape[:2]

            boxes  = result.boxes   # Boxes object
            masks  = result.masks   # Masks object (None if no detections)

            for idx, box in enumerate(boxes):
                cls_id  = int(box.cls[0])
                conf    = float(box.conf[0])
                x1, y1, x2, y2 = [int(v) for v in box.xyxy[0].tolist()]
                color   = self.INSTANCE_COLORS[idx % len(self.INSTANCE_COLORS)]

                # ── 1. Draw semi-transparent segmentation mask ──────────────
                if masks is not None:
                    # masks.data: (N, H_mask, W_mask) float32 in [0,1]
                    mask_data = masks.data[idx].cpu().numpy()  # (Hm, Wm)
                    # Resize mask to original frame size
                    mask_resized = cv2.resize(
                        mask_data, (w, h), interpolation=cv2.INTER_NEAREST
                    )
                    binary_mask = (mask_resized > 0.5).astype(np.uint8)

                    # Overlay colored mask with alpha blending
                    color_layer = np.zeros_like(annotated, dtype=np.uint8)
                    color_layer[binary_mask == 1] = color
                    annotated = cv2.addWeighted(annotated, 1.0, color_layer, 0.45, 0)

                    # Draw mask contour
                    contours, _ = cv2.findContours(
                        binary_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
                    )
                    cv2.drawContours(annotated, contours, -1, color, 2)

                # ── 2. Draw bounding box ────────────────────────────────────
                cv2.rectangle(annotated, (x1, y1), (x2, y2), color, 2)

                # ── 3. Draw label background + text ────────────────────────
                label = f"{self.classes[cls_id]} {conf:.2f}"
                font       = cv2.FONT_HERSHEY_SIMPLEX
                font_scale = 0.6
                thickness  = 1
                (lw, lh), baseline = cv2.getTextSize(label, font, font_scale, thickness)
                # Background rectangle (slightly above bbox)
                top = max(y1 - lh - 8, 0)
                cv2.rectangle(annotated, (x1, top), (x1 + lw + 6, y1), color, -1)
                cv2.putText(
                    annotated, label,
                    (x1 + 3, y1 - 4),
                    font, font_scale, (0, 0, 0), thickness, cv2.LINE_AA
                )

                # ── 4. Collect detection info ───────────────────────────────
                cx_n = ((x1 + x2) / 2) / w
                cy_n = ((y1 + y2) / 2) / h
                detections.append({
                    'label':      self.classes[cls_id],
                    'confidence': conf,
                    'class_id':   cls_id,
                    'x': cx_n, 'y': cy_n,
                    'width':  (x2 - x1) / w,
                    'height': (y2 - y1) / h,
                    'bbox': {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2},
                })

            return annotated, detections

        except Exception as e:
            print(f"[YOLO] Inference error: {e}")
            return frame, []

    def detect(self, frame: np.ndarray) -> List[Dict]:
        """Convenience wrapper: run inference and return detection list only."""
        _, detections = self.detect_and_annotate(frame)
        return detections



class ROVController:
    """ROV控制器"""
    
    def __init__(self):
        self.current_speed = 0.0
        self.direction = 'stop'
        self.depth = 0.0
        self.position = {'x': 0.0, 'y': 0.0}
        self.light_on = False
        self.sonar_on = False
        self.laser_on = False
        self.auto_cruise = False
        self.thruster_power = 0.65
        self.arm_state = 'idle'
        self.command_history: List[Dict[str, Any]] = []
    
    def _record_hardware_signal(self, command: str, params: Dict[str, Any]):
        """
        记录硬件控制信号。
        实际接入硬件时，可在此处替换为串口/CAN/网络发送逻辑。
        """
        signal = {
            'timestamp': time.time(),
            'command': command,
            'params': params,
        }
        self.command_history.append(signal)
        # 仅保留最近100条，避免内存持续增长
        if len(self.command_history) > 100:
            self.command_history.pop(0)
        print(f"[HW] signal={signal}")
    
    def handle_command(self, command: str, params: Dict[str, Any] = None) -> Dict[str, Any]:
        """
        处理控制命令
        
        返回确认消息
        """
        params = params or {}
        speed = params.get('speed', 1.0)
        
        response = {
            'type': 'ack',
            'command': command,
            'success': True,
            'message': ''
        }
        
        if command == 'forward':
            self.direction = 'forward'
            self.current_speed = speed * self.thruster_power
            response['message'] = f'前进，速度: {self.current_speed:.2f}'
            self._record_hardware_signal(command, {'speed': self.current_speed})
            
        elif command == 'backward':
            self.direction = 'backward'
            self.current_speed = speed * self.thruster_power
            response['message'] = f'后退，速度: {self.current_speed:.2f}'
            self._record_hardware_signal(command, {'speed': self.current_speed})
            
        elif command == 'left':
            self.direction = 'left'
            self.current_speed = speed * self.thruster_power
            response['message'] = f'左转，速度: {self.current_speed:.2f}'
            self._record_hardware_signal(command, {'speed': self.current_speed})
            
        elif command == 'right':
            self.direction = 'right'
            self.current_speed = speed * self.thruster_power
            response['message'] = f'右转，速度: {self.current_speed:.2f}'
            self._record_hardware_signal(command, {'speed': self.current_speed})
            
        elif command == 'up':
            self.direction = 'up'
            self.current_speed = speed * self.thruster_power
            self.depth = max(0, self.depth - 0.5)
            response['message'] = f'上浮，当前深度: {self.depth:.1f}m'
            self._record_hardware_signal(command, {'speed': self.current_speed, 'depth': self.depth})
            
        elif command == 'down':
            self.direction = 'down'
            self.current_speed = speed * self.thruster_power
            self.depth += 0.5
            response['message'] = f'下潜，当前深度: {self.depth:.1f}m'
            self._record_hardware_signal(command, {'speed': self.current_speed, 'depth': self.depth})
            
        elif command == 'stop':
            self.direction = 'stop'
            self.current_speed = 0
            response['message'] = '停止'
            self._record_hardware_signal(command, {'speed': self.current_speed})
            
        elif command == 'emergencyStop':
            self.direction = 'stop'
            self.current_speed = 0
            self.auto_cruise = False
            response['message'] = '紧急停止！所有系统已停止'
            self._record_hardware_signal(command, {'speed': self.current_speed, 'auto_cruise': self.auto_cruise})
            
        elif command == 'grab':
            self.arm_state = 'grabbing'
            response['message'] = '执行抓取动作'
            self._record_hardware_signal(command, {'arm_state': self.arm_state})
            
        elif command == 'release':
            self.arm_state = 'released'
            response['message'] = '释放抓取'
            self._record_hardware_signal(command, {'arm_state': self.arm_state})
            
        elif command == 'lightOn':
            self.light_on = True
            response['message'] = '照明已开启'
            self._record_hardware_signal(command, {'light_on': self.light_on})
            
        elif command == 'lightOff':
            self.light_on = False
            response['message'] = '照明已关闭'
            self._record_hardware_signal(command, {'light_on': self.light_on})
            
        elif command == 'sonarOn':
            self.sonar_on = True
            response['message'] = '声呐已开启'
            self._record_hardware_signal(command, {'sonar_on': self.sonar_on})
            
        elif command == 'sonarOff':
            self.sonar_on = False
            response['message'] = '声呐已关闭'
            self._record_hardware_signal(command, {'sonar_on': self.sonar_on})
            
        elif command == 'laserOn':
            self.laser_on = True
            response['message'] = '激光测距已开启'
            self._record_hardware_signal(command, {'laser_on': self.laser_on})
            
        elif command == 'laserOff':
            self.laser_on = False
            response['message'] = '激光测距已关闭'
            self._record_hardware_signal(command, {'laser_on': self.laser_on})
            
        elif command == 'autoCruise':
            self.auto_cruise = params.get('enabled', False)
            response['message'] = f'自动巡航: {"开启" if self.auto_cruise else "关闭"}'
            self._record_hardware_signal(command, {'auto_cruise': self.auto_cruise})
            
        elif command == 'snapshot':
            response['message'] = '快照命令已接收'
            self._record_hardware_signal(command, {})
            
        elif command == 'resetPosition':
            self.position = {'x': 0.0, 'y': 0.0}
            response['message'] = '坐标已归零'
            self._record_hardware_signal(command, {'position': self.position})
            
        else:
            response['success'] = False
            response['message'] = f'未知命令: {command}'
        
        print(f"[ROV] {response['message']}")
        return response
    
    def get_status(self) -> Dict[str, Any]:
        """获取ROV状态"""
        return {
            'type': 'status',
            'data': {
                'direction': self.direction,
                'speed': self.current_speed,
                'depth': self.depth,
                'position': self.position,
                'light_on': self.light_on,
                'sonar_on': self.sonar_on,
                'laser_on': self.laser_on,
                'auto_cruise': self.auto_cruise,
                'arm_state': self.arm_state,
                'thruster_power': self.thruster_power,
                'battery': 85,  # 电池百分比
                'temperature': 22.5,  # 水温
            }
        }


class VideoStreamer:
    """视频流处理器 - 支持多种视频源"""
    
    def __init__(self, camera_id: int = 0, model_path: Optional[str] = None,
                 custom_pkg_dir: Optional[str] = None):
        self.camera_id = camera_id
        self.model_path = model_path
        self.custom_pkg_dir = custom_pkg_dir
        self.cap = None
        self.detector = YOLODetector()  # created empty; loaded below
        self.frame_count = 0
        self.fps = 0
        self.last_fps_time = time.time()
        self.fps_frame_count = 0
        self.latest_frame: Optional[np.ndarray] = None
        self.snapshots_dir = Path(__file__).resolve().parent / 'snapshots'
        self.snapshots_dir.mkdir(parents=True, exist_ok=True)
        if model_path:
            self.detector.load_model(model_path, custom_pkg_dir=custom_pkg_dir)
    
    def load_model(self, model_path: str, custom_pkg_dir: str = None) -> bool:
        """Load or swap YOLO model."""
        self.model_path = model_path
        return self.detector.load_model(model_path, custom_pkg_dir=custom_pkg_dir or self.custom_pkg_dir)
    
    def set_source(self, source) -> bool:
        """
        设置视频源
        
        参数:
            source: 摄像头ID (int) 或 视频文件/RTSP流路径 (str)
        
        返回:
            是否设置成功
        """
        self.stop()
        self.camera_id = source
        return self.start()
    
    def start(self) -> bool:
        """启动视频捕获"""
        self.cap = cv2.VideoCapture(self.camera_id)
        if not self.cap.isOpened():
            print(f"[Video] 警告: 无法打开视频源 {self.camera_id}，使用测试图像")
            self.cap = None
            return False
        
        # 尝试设置分辨率
        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
        
        actual_width = self.cap.get(cv2.CAP_PROP_FRAME_WIDTH)
        actual_height = self.cap.get(cv2.CAP_PROP_FRAME_HEIGHT)
        print(f"[Video] 视频源已打开: {self.camera_id}, 分辨率: {int(actual_width)}x{int(actual_height)}")
        return True
    
    def stop(self):
        """停止视频捕获"""
        if self.cap:
            self.cap.release()
            self.cap = None
            print("[Video] 视频源已关闭")
    
    def get_frame(self) -> Tuple[str, List[Dict]]:
        """
        获取一帧视频（已标注YOLO检测结果）
        
        返回: (frame_base64, detections)
            - frame_base64: 已标注的画面（Base64编码的JPEG）
            - detections: 检测结果列表
        """
        # 获取原始帧
        if self.cap and self.cap.isOpened():
            ret, frame = self.cap.read()
            if not ret:
                # 视频文件播放完毕，重新开始
                self.cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                ret, frame = self.cap.read()
                if not ret:
                    frame = self._generate_test_frame()
        else:
            frame = self._generate_test_frame()
        
        # 执行YOLO检测并标注画面
        annotated_frame, detections = self.detector.detect_and_annotate(frame)
        self.latest_frame = annotated_frame.copy()
        
        # 添加FPS和检测统计信息到画面
        self._update_fps()
        self._draw_info_overlay(annotated_frame, detections)
        
        # 编码为JPEG
        _, buffer = cv2.imencode('.jpg', annotated_frame, [cv2.IMWRITE_JPEG_QUALITY, 85])
        frame_base64 = base64.b64encode(buffer).decode('utf-8')
        
        self.frame_count += 1
        return frame_base64, detections
    
    def save_snapshot(self) -> Optional[str]:
        """保存当前帧快照，返回保存路径。"""
        if self.latest_frame is None:
            return None
        timestamp = time.strftime('%Y%m%d_%H%M%S')
        file_path = self.snapshots_dir / f'snapshot_{timestamp}_{self.frame_count:06d}.jpg'
        success = cv2.imwrite(str(file_path), self.latest_frame)
        if not success:
            return None
        return str(file_path)
    
    def _update_fps(self):
        """更新FPS计算"""
        self.fps_frame_count += 1
        current_time = time.time()
        elapsed = current_time - self.last_fps_time
        if elapsed >= 1.0:
            self.fps = self.fps_frame_count / elapsed
            self.fps_frame_count = 0
            self.last_fps_time = current_time
    
    def _draw_info_overlay(self, frame: np.ndarray, detections: List[Dict]):
        """在画面上绘制信息叠加层"""
        h, w = frame.shape[:2]
        
        # 绘制半透明信息背景
        overlay = frame.copy()
        cv2.rectangle(overlay, (10, 10), (280, 100), (0, 0, 0), -1)
        cv2.addWeighted(overlay, 0.5, frame, 0.5, 0, frame)
        
        # 绘制时间戳
        timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
        cv2.putText(frame, timestamp, (20, 35), cv2.FONT_HERSHEY_SIMPLEX, 
                    0.6, (255, 255, 255), 1)
        
        # 绘制FPS
        cv2.putText(frame, f'FPS: {self.fps:.1f}', (20, 60), cv2.FONT_HERSHEY_SIMPLEX, 
                    0.6, (0, 255, 0), 1)
        
        # 绘制检测数量
        cv2.putText(frame, f'Detections: {len(detections)}', (20, 85), cv2.FONT_HERSHEY_SIMPLEX, 
                    0.6, (0, 255, 255), 1)
        
        # 模型状态指示
        model_status = "YOLO: ON" if self.detector.model else "YOLO: Demo"
        color = (0, 255, 0) if self.detector.model else (0, 165, 255)
        cv2.putText(frame, model_status, (150, 60), cv2.FONT_HERSHEY_SIMPLEX, 
                    0.5, color, 1)
    
    def _generate_test_frame(self) -> np.ndarray:
        """生成测试帧（当摄像头不可用时）"""
        # 创建深蓝色背景模拟水下画面
        frame = np.zeros((720, 1280, 3), dtype=np.uint8)
        frame[:] = (80, 50, 30)  # BGR - 深海蓝色
        
        # 添加一些随机噪点模拟水中颗粒
        noise = np.random.randint(0, 30, frame.shape, dtype=np.uint8)
        frame = cv2.add(frame, noise)
        
        # 添加水下光线效果
        center_x, center_y = 640, 200
        for radius in range(300, 50, -50):
            alpha = 0.02
            overlay = frame.copy()
            cv2.circle(overlay, (center_x, center_y), radius, (100, 80, 60), -1)
            cv2.addWeighted(overlay, alpha, frame, 1 - alpha, 0, frame)
        
        # 添加测试文字
        cv2.putText(frame, 'ROV Camera Feed - Test Mode', (20, 680), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, (200, 200, 200), 2)
        cv2.putText(frame, f'Frame: {self.frame_count}', (20, 710), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (150, 150, 150), 1)
        
        return frame


def calculate_distance(point1: Dict, point2: Dict, depth: float = 5.0) -> float:
    """
    估计两点之间的距离
    
    基于像素坐标和预估深度计算实际距离
    这是一个简化的计算，实际应用需要相机标定
    
    参数:
        point1: {'x': 0.1, 'y': 0.2} - 相对坐标
        point2: {'x': 0.5, 'y': 0.6} - 相对坐标
        depth: 当前深度（米）
    
    返回:
        估计距离（厘米）
    """
    # 假设视野角度和画面尺寸
    fov_horizontal = 90  # 度
    frame_width_at_depth = 2 * depth * np.tan(np.radians(fov_horizontal / 2))  # 米
    
    # 计算像素距离
    dx = (point2['x'] - point1['x']) * frame_width_at_depth
    dy = (point2['y'] - point1['y']) * frame_width_at_depth * 0.5625  # 16:9比例
    
    distance_m = np.sqrt(dx**2 + dy**2)
    distance_cm = distance_m * 100
    
    return round(distance_cm, 2)


class ROVServer:
    """ROV WebSocket服务器"""
    
    def __init__(self, host: str = 'localhost', port: int = 8765,
                 model_path: Optional[str] = None, camera_id: int = 0,
                 custom_pkg_dir: Optional[str] = None):
        self.host = host
        self.port = port
        self.clients: Set = set()
        self.controller = ROVController()
        self.streamer = VideoStreamer(camera_id, model_path, custom_pkg_dir=custom_pkg_dir)
        self.running = False
    
    async def register(self, websocket):
        """注册新客户端"""
        self.clients.add(websocket)
        print(f"[Server] 客户端连接: {websocket.remote_address}")
    
    async def unregister(self, websocket):
        """注销客户端"""
        self.clients.discard(websocket)
        print(f"[Server] 客户端断开: {websocket.remote_address}")
    
    async def handle_message(self, websocket, message: str):
        """处理接收到的消息"""
        try:
            data = json.loads(message)
            msg_type = data.get('type')
            
            if msg_type == 'init':
                print(f"[Server] 客户端初始化: {data.get('client')}")
                # 发送初始状态
                await websocket.send(json.dumps(self.controller.get_status()))
                
            elif msg_type == 'command':
                command = data.get('command')
                params = {k: v for k, v in data.items() if k not in ['type', 'command', 'timestamp']}
                response = self.controller.handle_command(command, params)
                if command == 'snapshot':
                    snapshot_path = self.streamer.save_snapshot()
                    response['snapshotPath'] = snapshot_path
                    if snapshot_path:
                        response['message'] = f'快照已保存: {snapshot_path}'
                    else:
                        response['success'] = False
                        response['message'] = '快照保存失败：当前没有可用帧'
                await websocket.send(json.dumps(response))
                
            elif msg_type == 'measure_distance':
                point1 = data.get('point1')
                point2 = data.get('point2')
                if point1 and point2:
                    distance = calculate_distance(point1, point2, self.controller.depth or 5.0)
                    response = {
                        'type': 'distance',
                        'distance': distance,
                        'point1': point1,
                        'point2': point2
                    }
                    await websocket.send(json.dumps(response))
                    print(f"[Server] 距离测量: {distance} cm")
                    
            elif msg_type == 'set_power':
                power = data.get('power', 0.65)
                self.controller.thruster_power = max(0, min(1, power))
                print(f"[Server] 推进器动力设置为: {self.controller.thruster_power}")
                
            elif msg_type == 'get_status':
                await websocket.send(json.dumps(self.controller.get_status()))
                
        except json.JSONDecodeError:
            print(f"[Server] 无效的JSON消息: {message}")
        except Exception as e:
            print(f"[Server] 消息处理错误: {e}")
    
    async def stream_video(self, websocket):
        """向客户端流式传输视频"""
        try:
            while self.running and websocket in self.clients:
                frame_base64, detections = self.streamer.get_frame()
                
                # 发送视频帧
                frame_msg = {
                    'type': 'frame',
                    'data': frame_base64
                }
                await websocket.send(json.dumps(frame_msg))
                
                # 发送检测结果
                if detections:
                    detection_msg = {
                        'type': 'detections',
                        'results': detections
                    }
                    await websocket.send(json.dumps(detection_msg))
                
                # 控制帧率（约30fps）
                await asyncio.sleep(1/30)
                
        except websockets.exceptions.ConnectionClosed:
            pass
        except Exception as e:
            print(f"[Server] 视频流错误: {e}")
    
    async def handler(self, websocket, path=None):
        """WebSocket连接处理器"""
        await self.register(websocket)
        
        # 启动视频流任务
        video_task = asyncio.create_task(self.stream_video(websocket))
        
        try:
            async for message in websocket:
                await self.handle_message(websocket, message)
        finally:
            video_task.cancel()
            await self.unregister(websocket)
    
    async def start(self):
        """启动服务器"""
        self.running = True
        self.streamer.start()
        
        print(f"[Server] ROV后端服务启动于 ws://{self.host}:{self.port}")
        print("[Server] 等待Flutter客户端连接...")
        print("[Server] 按 Ctrl+C 停止服务器")
        
        async with websockets.serve(self.handler, self.host, self.port):
            await asyncio.Future()  # 永久运行
    
    def stop(self):
        """停止服务器"""
        self.running = False
        self.streamer.stop()


async def main():
    """主函数"""
    parser = argparse.ArgumentParser(description='ROV后端服务器')
    parser.add_argument('--host', type=str, default='localhost', help='Listen host (default: localhost)')
    parser.add_argument('--port', type=int, default=8765, help='Listen port (default: 8765)')
    parser.add_argument('--model', type=str, default=None,
                        help='YOLO model path (.pt or .onnx). Omit or use --no-model for demo mode.')
    parser.add_argument('--camera', type=int, default=0, help='Camera ID (default: 0)')
    parser.add_argument('--video', type=str, default=None, help='Video file path (overrides --camera)')
    parser.add_argument('--no-model', action='store_true', help='Demo mode, no YOLO model')
    parser.add_argument('--custom-pkg', type=str, default=None,
                        help='Path to custom ultralytics source root (needed for models with extra_modules)')
    
    args = parser.parse_args()
    
    video_source = args.video if args.video else args.camera
    model_path = None if args.no_model else args.model
    custom_pkg_dir = args.custom_pkg
    
    print("=" * 55)
    print("  ROV Backend Server")
    print("=" * 55)
    print(f"  WS address : ws://{args.host}:{args.port}")
    print(f"  Video src  : {video_source}")
    print(f"  YOLO model : {model_path if model_path else 'Demo mode (no model)'}")
    print(f"  Custom pkg : {custom_pkg_dir if custom_pkg_dir else 'standard ultralytics'}")
    print("=" * 55)
    
    server = ROVServer(
        host=args.host,
        port=args.port,
        model_path=model_path,
        camera_id=video_source,
        custom_pkg_dir=custom_pkg_dir,
    )
    
    try:
        await server.start()
    except KeyboardInterrupt:
        print("\n[Server] 正在关闭服务器...")
        server.stop()


if __name__ == '__main__':
    asyncio.run(main())
