/// ROV后端通信服务
/// 
/// 与Python后端通过WebSocket通信，实现：
/// 1. 实时视频流接收（支持多种视频源）
/// 2. YOLO检测结果接收
/// 3. 控制命令发送（前进/后退/上浮/下潜等）
/// 4. 两点距离测量
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'user_session.dart';

/// 视频源类型
enum VideoSourceType {
  websocket,    // WebSocket传输（Python后端）
  localFile,    // 本地视频文件
  rtsp,         // RTSP流
  httpStream,   // HTTP图片流
}

/// 视频源配置
class VideoSourceConfig {
  final VideoSourceType type;
  final String path;         // 路径/地址
  final int refreshRate;     // HTTP刷新率（毫秒）

  const VideoSourceConfig({
    required this.type,
    required this.path,
    this.refreshRate = 100,
  });

  /// WebSocket源
  factory VideoSourceConfig.websocket(String host, int port) {
    return VideoSourceConfig(
      type: VideoSourceType.websocket,
      path: 'ws://$host:$port',
    );
  }

  /// 本地文件源
  factory VideoSourceConfig.localFile(String filePath) {
    return VideoSourceConfig(
      type: VideoSourceType.localFile,
      path: filePath,
    );
  }

  /// RTSP流源
  factory VideoSourceConfig.rtsp(String url) {
    return VideoSourceConfig(
      type: VideoSourceType.rtsp,
      path: url,
    );
  }

  /// HTTP图片流源
  factory VideoSourceConfig.httpStream(String url, {int refreshRate = 100}) {
    return VideoSourceConfig(
      type: VideoSourceType.httpStream,
      path: url,
      refreshRate: refreshRate,
    );
  }
}

/// ROV控制命令类型
enum RovCommand {
  forward,      // 前进
  backward,     // 后退
  left,         // 左转
  right,        // 右转
  up,           // 上浮
  down,         // 下潜
  stop,         // 停止
  grab,         // 抓取
  release,      // 释放
  lightOn,      // 开灯
  lightOff,     // 关灯
  sonarOn,      // 声呐开
  sonarOff,     // 声呐关
  laserOn,      // 激光开
  laserOff,     // 激光关
  autoCruise,   // 自动巡航
  emergencyStop,// 紧急停止
  snapshot,     // 快照
  resetPosition,// 坐标归零
}

/// 检测结果 - YOLO检测到的对象
class DetectionResult {
  final String label;       // 标签（如"海参"）
  final double confidence;  // 置信度
  final Rect boundingBox;   // 边界框
  final int classId;        // 类别ID

  DetectionResult({
    required this.label,
    required this.confidence,
    required this.boundingBox,
    required this.classId,
  });

  factory DetectionResult.fromJson(Map<String, dynamic> json) {
    return DetectionResult(
      label: json['label'] ?? '',
      confidence: (json['confidence'] ?? 0).toDouble(),
      boundingBox: Rect.fromLTWH(
        (json['x'] ?? 0).toDouble(),
        (json['y'] ?? 0).toDouble(),
        (json['width'] ?? 0).toDouble(),
        (json['height'] ?? 0).toDouble(),
      ),
      classId: json['class_id'] ?? 0,
    );
  }
}

/// 测量点
class MeasurePoint {
  final double x;
  final double y;
  final String? label;

  MeasurePoint({required this.x, required this.y, this.label});

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'label': label};
}

/// ROV后端服务 - 单例模式
class RovBackendService extends ChangeNotifier {
  static final RovBackendService _instance = RovBackendService._internal();
  factory RovBackendService() => _instance;
  RovBackendService._internal();

  // WebSocket连接
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  // 连接状态
  bool _isConnected = false;
  String _connectionStatus = '未连接';

  // 服务器配置
  String _serverHost = 'localhost';
  int _serverPort = 8765;

  // === 视频源配置 ===
  VideoSourceType _videoSourceType = VideoSourceType.websocket;
  VideoSourceConfig? _videoSourceConfig;
  Timer? _httpStreamTimer;
  String _localVideoPath = '';      // 本地视频路径
  String _rtspUrl = '';             // RTSP流地址
  String _httpStreamUrl = '';       // HTTP图片流地址

  // 视频帧数据
  Uint8List? _currentFrame;
  int _frameRate = 0;
  DateTime? _lastFrameTime;
  int _frameCount = 0;

  // 检测结果
  List<DetectionResult> _detections = [];

  // 测量点（用于两点距离估计）
  MeasurePoint? _point1;
  MeasurePoint? _point2;
  double? _measuredDistance;

  // ROV状态
  Map<String, dynamic> _rovStatus = {};

  // RDK X5 遥测（由本地后端从 RDK X5 转发而来）
  Map<String, dynamic> _sensorData = {};
  Map<String, dynamic> _pixhawkStatus = {};
  Map<String, dynamic> _rdkStatus = {};
  String? _activeCameraId;
  DateTime? _lastSensorsTs;

  // Getters
  bool get isConnected => _isConnected;
  String get connectionStatus => _connectionStatus;
  Uint8List? get currentFrame => _currentFrame;
  int get frameRate => _frameRate;
  List<DetectionResult> get detections => _detections;
  MeasurePoint? get point1 => _point1;
  MeasurePoint? get point2 => _point2;
  double? get measuredDistance => _measuredDistance;
  Map<String, dynamic> get rovStatus => _rovStatus;
  Map<String, dynamic> get sensorData => _sensorData;
  Map<String, dynamic> get pixhawkStatus => _pixhawkStatus;
  Map<String, dynamic> get rdkStatus => _rdkStatus;
  String? get activeCameraId => _activeCameraId;
  DateTime? get lastSensorsTs => _lastSensorsTs;
  String get serverAddress => '$_serverHost:$_serverPort';
  VideoSourceType get videoSourceType => _videoSourceType;
  String get localVideoPath => _localVideoPath;
  String get rtspUrl => _rtspUrl;
  String get httpStreamUrl => _httpStreamUrl;

  /// 设置服务器地址
  void setServerAddress(String host, int port) {
    _serverHost = host;
    _serverPort = port;
  }

  /// 设置视频源类型
  void setVideoSourceType(VideoSourceType type) {
    if (_videoSourceType != type) {
      _videoSourceType = type;
      notifyListeners();
    }
  }

  /// 设置本地视频路径
  void setLocalVideoPath(String path) {
    _localVideoPath = path;
    notifyListeners();
  }

  /// 设置RTSP流地址
  void setRtspUrl(String url) {
    _rtspUrl = url;
    notifyListeners();
  }

  /// 设置HTTP图片流地址
  void setHttpStreamUrl(String url) {
    _httpStreamUrl = url;
    notifyListeners();
  }

  /// 根据当前视频源类型连接
  Future<bool> connectVideoSource() async {
    switch (_videoSourceType) {
      case VideoSourceType.websocket:
        return connect();
      case VideoSourceType.localFile:
        return _connectLocalFile();
      case VideoSourceType.rtsp:
        return _connectRtsp();
      case VideoSourceType.httpStream:
        return _connectHttpStream();
    }
  }

  /// 连接本地视频文件
  Future<bool> _connectLocalFile() async {
    if (_localVideoPath.isEmpty) {
      _connectionStatus = '未设置本地视频路径';
      notifyListeners();
      return false;
    }

    final file = File(_localVideoPath);
    if (!await file.exists()) {
      _connectionStatus = '视频文件不存在: $_localVideoPath';
      notifyListeners();
      return false;
    }

    _isConnected = true;
    _connectionStatus = '本地视频: $_localVideoPath';
    notifyListeners();
    return true;
  }

  /// 连接RTSP流
  Future<bool> _connectRtsp() async {
    if (_rtspUrl.isEmpty) {
      _connectionStatus = '未设置RTSP地址';
      notifyListeners();
      return false;
    }

    // RTSP流需要使用 media_kit 或 vlc_player 等库
    // 这里只设置状态，实际播放需要在UI层处理
    _isConnected = true;
    _connectionStatus = 'RTSP流: $_rtspUrl';
    notifyListeners();
    return true;
  }

  /// 连接HTTP图片流
  Future<bool> _connectHttpStream() async {
    if (_httpStreamUrl.isEmpty) {
      _connectionStatus = '未设置HTTP流地址';
      notifyListeners();
      return false;
    }

    _stopHttpStreamTimer();
    
    try {
      // 测试连接
      final response = await http.get(Uri.parse(_httpStreamUrl)).timeout(
        const Duration(seconds: 5),
      );
      
      if (response.statusCode == 200) {
        _isConnected = true;
        _connectionStatus = 'HTTP流已连接';
        _startHttpStreamTimer();
        notifyListeners();
        return true;
      } else {
        _connectionStatus = 'HTTP流连接失败: ${response.statusCode}';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _connectionStatus = 'HTTP流连接错误: $e';
      notifyListeners();
      return false;
    }
  }

  /// 启动HTTP图片流定时器
  void _startHttpStreamTimer() {
    _httpStreamTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _fetchHttpFrame(),
    );
  }

  /// 停止HTTP图片流定时器
  void _stopHttpStreamTimer() {
    _httpStreamTimer?.cancel();
    _httpStreamTimer = null;
  }

  /// 获取HTTP图片帧
  Future<void> _fetchHttpFrame() async {
    if (!_isConnected || _httpStreamUrl.isEmpty) return;

    try {
      final response = await http.get(Uri.parse(_httpStreamUrl));
      if (response.statusCode == 200) {
        _handleFrameData(response.bodyBytes);
      }
    } catch (e) {
      debugPrint('获取HTTP帧失败: $e');
    }
  }

  /// 连接到Python后端
  Future<bool> connect({String? host, int? port}) async {
    if (_isConnected) {
      await disconnect();
    }

    final targetHost = host ?? _serverHost;
    final targetPort = port ?? _serverPort;

    try {
      _connectionStatus = '正在连接...';
      notifyListeners();

      final uri = Uri.parse('ws://$targetHost:$targetPort');
      _channel = WebSocketChannel.connect(uri);

      // 等待连接建立
      await _channel!.ready;

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _isConnected = true;
      _connectionStatus = '已连接';
      _serverHost = targetHost;
      _serverPort = targetPort;
      notifyListeners();

      // 发送初始化消息
      _send({'type': 'init', 'client': 'flutter_rov'});

      return true;
    } catch (e) {
      _connectionStatus = '连接失败: $e';
      _isConnected = false;
      notifyListeners();
      return false;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    _stopHttpStreamTimer();
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _subscription = null;
    _isConnected = false;
    _connectionStatus = '已断开';
    _currentFrame = null;
    _detections = [];
    notifyListeners();
  }

  /// 发送消息
  void _send(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(json.encode(message));
    }
  }

  /// 处理接收到的消息
  void _onMessage(dynamic message) {
    try {
      if (message is String) {
        final data = json.decode(message) as Map<String, dynamic>;
        _handleJsonMessage(data);
      } else if (message is Uint8List) {
        // 二进制数据 - 视频帧
        _handleFrameData(message);
      }
    } catch (e) {
      debugPrint('消息处理错误: $e');
    }
  }

  /// 处理JSON消息
  void _handleJsonMessage(Map<String, dynamic> data) {
    final type = data['type'] as String?;

    switch (type) {
      case 'frame':
        // Base64编码的视频帧
        if (data['camera_id'] != null) {
          _activeCameraId = data['camera_id'] as String;
        }
        if (data['data'] != null) {
          final frameData = base64Decode(data['data'] as String);
          _handleFrameData(frameData);
        }
        break;

      case 'detections':
        // YOLO检测结果
        final results = (data['results'] as List?)?.map((e) {
          return DetectionResult.fromJson(e as Map<String, dynamic>);
        }).toList() ?? [];
        _detections = results;
        notifyListeners();
        break;

      case 'distance':
        // 两点距离测量结果
        _measuredDistance = (data['distance'] as num?)?.toDouble();
        notifyListeners();
        break;

      case 'status':
        // ROV状态更新
        final status = data['data'] as Map<String, dynamic>? ?? {};
        _rovStatus = status;
        _rdkStatus = status['rdk'] as Map<String, dynamic>? ?? {};
        _pixhawkStatus = status['pixhawk'] as Map<String, dynamic>? ?? {};
        if (_rdkStatus['active_camera'] != null) {
          _activeCameraId = _rdkStatus['active_camera'] as String;
        }
        notifyListeners();
        break;

      case 'sensors':
        // RDK X5 传感器遥测
        _sensorData = data['data'] as Map<String, dynamic>? ?? {};
        _pixhawkStatus = data['pixhawk'] as Map<String, dynamic>? ?? {};
        _lastSensorsTs = DateTime.now();
        notifyListeners();
        break;

      case 'ack':
        // 命令确认
        debugPrint('命令确认: ${data['command']}');
        break;

      case 'error':
        // 错误消息
        debugPrint('后端错误: ${data['message']}');
        break;
    }
  }

  /// 处理视频帧数据
  void _handleFrameData(Uint8List frameData) {
    _currentFrame = frameData;

    // 计算帧率
    final now = DateTime.now();
    _frameCount++;
    if (_lastFrameTime != null) {
      final diff = now.difference(_lastFrameTime!).inMilliseconds;
      if (diff >= 1000) {
        _frameRate = (_frameCount * 1000 / diff).round();
        _frameCount = 0;
        _lastFrameTime = now;
      }
    } else {
      _lastFrameTime = now;
    }

    notifyListeners();
  }

  /// 连接错误处理
  void _onError(dynamic error) {
    _connectionStatus = '连接错误: $error';
    _isConnected = false;
    notifyListeners();
  }

  /// 连接关闭处理
  void _onDone() {
    _connectionStatus = '连接已关闭';
    _isConnected = false;
    notifyListeners();
  }

  // === 控制命令 ===

  /// 发送ROV控制命令
  void sendCommand(RovCommand command, {Map<String, dynamic>? params}) {
    final message = {
      'type': 'command',
      'command': command.name,
      'token': UserSession().authToken ?? '',
      'timestamp': DateTime.now().toIso8601String(),
      ...?params,
    };
    _send(message);
    debugPrint('发送命令: ${command.name}');
  }

  /// 修改 RDK X5 连接地址（网线直连配置）
  void sendRdkConfig(String host, int port) {
    _send({'type': 'set_rdk_config', 'host': host, 'port': port});
  }

  /// 前进
  void forward({double speed = 1.0}) {
    sendCommand(RovCommand.forward, params: {'speed': speed});
  }

  /// 后退
  void backward({double speed = 1.0}) {
    sendCommand(RovCommand.backward, params: {'speed': speed});
  }

  /// 左转
  void turnLeft({double speed = 1.0}) {
    sendCommand(RovCommand.left, params: {'speed': speed});
  }

  /// 右转
  void turnRight({double speed = 1.0}) {
    sendCommand(RovCommand.right, params: {'speed': speed});
  }

  /// 上浮
  void ascend({double speed = 1.0}) {
    sendCommand(RovCommand.up, params: {'speed': speed});
  }

  /// 下潜
  void descend({double speed = 1.0}) {
    sendCommand(RovCommand.down, params: {'speed': speed});
  }

  /// 停止
  void stop() {
    sendCommand(RovCommand.stop);
  }

  /// 紧急停止
  void emergencyStop() {
    sendCommand(RovCommand.emergencyStop);
  }

  /// 抓取
  void grab() {
    sendCommand(RovCommand.grab);
  }

  /// 释放
  void release() {
    sendCommand(RovCommand.release);
  }

  /// 开灯/关灯
  void setLight(bool on) {
    sendCommand(on ? RovCommand.lightOn : RovCommand.lightOff);
  }

  /// 声呐开关
  void setSonar(bool on) {
    sendCommand(on ? RovCommand.sonarOn : RovCommand.sonarOff);
  }

  /// 激光开关
  void setLaser(bool on) {
    sendCommand(on ? RovCommand.laserOn : RovCommand.laserOff);
  }

  /// 自动巡航
  void setAutoCruise(bool on) {
    sendCommand(RovCommand.autoCruise, params: {'enabled': on});
  }

  /// 切换 RDK X5 摄像头（camera_1 前视 / camera_2 吸口近距）
  void switchCamera(String cameraId) {
    _send({
      'type': 'command',
      'command': 'set_camera',
      'params': {'camera_id': cameraId},
      'token': UserSession().authToken ?? '',
    });
    debugPrint('切换摄像头: $cameraId');
  }

  /// 快照
  void takeSnapshot() {
    sendCommand(RovCommand.snapshot);
  }

  /// 坐标归零
  void resetPosition() {
    sendCommand(RovCommand.resetPosition);
  }

  // === 两点测量 ===

  /// 设置测量点1
  void setMeasurePoint1(double x, double y) {
    _point1 = MeasurePoint(x: x, y: y, label: '点1');
    _measuredDistance = null;
    notifyListeners();

    if (_point2 != null) {
      _requestDistanceMeasurement();
    }
  }

  /// 设置测量点2
  void setMeasurePoint2(double x, double y) {
    _point2 = MeasurePoint(x: x, y: y, label: '点2');
    _measuredDistance = null;
    notifyListeners();

    if (_point1 != null) {
      _requestDistanceMeasurement();
    }
  }

  /// 清除测量点
  void clearMeasurePoints() {
    _point1 = null;
    _point2 = null;
    _measuredDistance = null;
    notifyListeners();
  }

  /// 请求距离测量
  void _requestDistanceMeasurement() {
    if (_point1 == null || _point2 == null) return;

    _send({
      'type': 'measure_distance',
      'point1': _point1!.toJson(),
      'point2': _point2!.toJson(),
    });
  }

  /// 设置推进器动力
  void setThrusterPower(double power) {
    _send({
      'type': 'set_power',
      'power': power.clamp(0.0, 1.0),
    });
  }

  /// 请求状态更新
  void requestStatus() {
    _send({'type': 'get_status'});
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
