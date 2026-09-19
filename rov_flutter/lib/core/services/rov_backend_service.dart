/// ROV后端通信服务（Wave 1 重构版，契约见 docs/UPGRADE_CONTRACTS.md §6）
///
/// 与Python后端通过WebSocket通信，实现：
/// 1. 实时视频流接收（支持多种视频源）
/// 2. YOLO检测结果接收
/// 3. 控制命令发送（前进/后退/上浮/下潜等）
/// 4. 两点距离测量
///
/// ---
/// ## Wave 1 性能重构说明（务必阅读）
///
/// 旧版实现"每收到一帧视频就 notifyListeners()"，导致监听服务的整页
/// 以 15~30Hz 全量重建，是全应用最大的性能瓶颈。本轮重构后拆分出三条
/// **独立的高频数据通道**（ValueNotifier），高频数据不再经过
/// ChangeNotifier：
///
/// | 通道 | 类型 | 更新频率 | 用途 |
/// | --- | --- | --- | --- |
/// | `videoFrameNotifier` | `ValueNotifier<VideoFrame?>` | 每帧（15~30Hz） | 视频帧+内联检测框 |
/// | `telemetryNotifier` | `ValueNotifier<TelemetrySnapshot?>` | ≤5Hz 节流 | status+sensors 合并快照 |
/// | `connectionNotifier` | `ValueNotifier<RovConnectionState>` | 仅变化时 | 连接状态（connected/reconnecting/offline） |
///
/// 旧版 `notifyListeners()` 仅保留给低频状态（设置变更、测量点、检测框
/// 等），且统一经 2Hz 节流（用户主动操作仍即时通知）。
///
/// ## Wave 2 页面迁移指引
///
/// 1. **视频画面**：`ValueListenableBuilder` of `VideoFrame?`（
///      valueListenable: service.videoFrameNotifier, ...)` 渲染 JPEG；
///      分辨率/帧率/≈链路时延一律取自 `VideoFrame` 字段
///      （width/height/fps/`DateTime.now()`−sentTs），禁止假值（契约§7）。
/// 2. **遥测卡片**：`ValueListenableBuilder` of `TelemetrySnapshot?`（
///      valueListenable: service.telemetryNotifier, ...)`；
///      断链显示 `StaleBadge`（shared/widgets/stale_badge.dart），
///      冻结最后真实值，禁止合成数据。
/// 3. **连接指示**：`ValueListenableBuilder` of `RovConnectionState`（
///      valueListenable: service.connectionNotifier, ...)`。
/// 4. **登录接线**：登录成功后调用 `service.attachAuth(token)`
///      （token 即 REST /api/login 返回的 Bearer token）。未登录时后端
///      只回 hello、不推流——**这是预期行为**，勿当作故障。
/// 5. 旧字段（currentFrame/rovStatus/sensorData/...）暂时保留以兼容
///    未迁移页面，但它们**不再每帧通知**；迁移完成后由 Wave 2 移除对旧
///    字段的依赖，服务层再择机删除旧路径。
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

/// 视频帧数据（契约§6：帧数据专用通道，只经 [RovBackendService.videoFrameNotifier] 下发）
///
/// 全部字段来自后端真实推送；缺失时保持 null，禁止在上游合成假值。
class VideoFrame {
  /// JPEG 编码帧数据
  final Uint8List jpegBytes;

  /// 帧宽度（像素），后端未携带时为 null
  final int? width;

  /// 帧高度（像素），后端未携带时为 null
  final int? height;

  /// 帧率：优先后端上报的 fps，缺省回退本地实测帧率
  final double fps;

  /// 摄像头 ID（camera_1 前视 / camera_2 吸口近距）
  final String? cameraId;

  /// 网关发送时刻（epoch 秒，float，契约§5）。
  /// 端到端时延 ≈ 本地接收时刻 − sentTs。
  final double? sentTs;

  /// 本地接收时刻（用于链路时延计算与 Stale 判断）
  final DateTime receivedAt;

  /// 该帧内联的 BPU 检测框（frame.detections[]，可能为空）
  final List<DetectionResult> detections;

  const VideoFrame({
    required this.jpegBytes,
    this.width,
    this.height,
    required this.fps,
    this.cameraId,
    this.sentTs,
    required this.receivedAt,
    this.detections = const [],
  });

  /// 帧年龄（秒）：距本地接收时刻的流逝时间
  double get ageSeconds =>
      DateTime.now().difference(receivedAt).inMilliseconds / 1000.0;

  /// ≈链路时延（秒）＝本地接收时刻 − 网关 sent_ts（契约§5）。
  /// 后端未携带 sent_ts 时返回 null（不猜）。
  double? get linkLatencySeconds {
    if (sentTs == null) return null;
    final receivedEpoch = receivedAt.millisecondsSinceEpoch / 1000.0;
    final v = receivedEpoch - sentTs!;
    return v >= 0 ? v : null; // 时钟倒挂时返回 null，避免负值误导
  }
}

/// 遥测合并快照（status+sensors，≤5Hz 节流下发）
class TelemetrySnapshot {
  /// ROV 状态（原 status 消息 data，含 rdk/pixhawk 子树）
  final Map<String, dynamic> status;

  /// RDK X5 传感器遥测（原 sensors 消息 data）
  final Map<String, dynamic> sensors;

  /// Pixhawk 飞控状态（status.pixhawk 或 sensors.pixhawk，取较新者）
  final Map<String, dynamic> pixhawk;

  /// RDK 网关状态子树（status.rdk）
  final Map<String, dynamic> rdk;

  /// 本地接收时刻（StaleBadge 判据）
  final DateTime lastUpdated;

  const TelemetrySnapshot({
    required this.status,
    required this.sensors,
    required this.pixhawk,
    required this.rdk,
    required this.lastUpdated,
  });

  /// 数据年龄（秒）
  double get ageSeconds =>
      DateTime.now().difference(lastUpdated).inMilliseconds / 1000.0;
}

/// 连接阶段（契约§6）
enum RovConnectionPhase {
  /// 已连接（TCP/WS 建立；未 auth 时后端不推流属正常）
  connected,

  /// 连接断开，自动重连中
  reconnecting,

  /// 离线（初始态 / 手动断开 / 连接失败等待重试）
  offline,
}

/// 连接状态快照（connectionNotifier 携带）
class RovConnectionState {
  final RovConnectionPhase phase;

  /// 人类可读状态描述（直接可用于 UI）
  final String message;

  /// 状态变化时刻
  final DateTime lastUpdated;

  const RovConnectionState({
    required this.phase,
    required this.message,
    required this.lastUpdated,
  });
}

/// ROV后端服务 - 单例模式（ChangeNotifier 仅承载低频状态）
class RovBackendService extends ChangeNotifier {
  static final RovBackendService _instance = RovBackendService._internal();
  factory RovBackendService() => _instance;
  RovBackendService._internal();

  // ============ Wave 1 新增：三条高频数据通道（契约§6） ============

  /// 视频帧专用通道：每帧更新，视频组件只监听它
  final ValueNotifier<VideoFrame?> videoFrameNotifier =
      ValueNotifier<VideoFrame?>(null);

  /// 遥测合并快照通道（status+sensors，≤5Hz 节流）
  final ValueNotifier<TelemetrySnapshot?> telemetryNotifier =
      ValueNotifier<TelemetrySnapshot?>(null);

  /// 连接状态通道（connected/reconnecting/offline，仅变化时更新）
  final ValueNotifier<RovConnectionState> connectionNotifier =
      ValueNotifier<RovConnectionState>(
    RovConnectionState(
      phase: RovConnectionPhase.offline,
      message: '未连接',
      lastUpdated: DateTime.now(),
    ),
  );

  /// 遥测通知节流周期（5Hz = 200ms）
  static const Duration _telemetryInterval = Duration(milliseconds: 200);

  /// 旧 ChangeNotifier 通知节流周期（2Hz = 500ms）
  static const Duration _legacyNotifyInterval = Duration(milliseconds: 500);

  TelemetrySnapshot? _telemetryLatest;
  bool _telemetryPushPending = false;
  DateTime _lastTelemetryPush = DateTime.fromMillisecondsSinceEpoch(0);

  bool _legacyNotifyPending = false;
  DateTime _lastLegacyNotify = DateTime.fromMillisecondsSinceEpoch(0);

  // ============ 连接与鉴权 ============

  // WebSocket连接
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  // 连接状态
  bool _isConnected = false;
  String _connectionStatus = '未连接';

  /// 是否手动断开（手动断开后不自动重连）
  bool _manualDisconnect = false;

  /// 自动重连定时器与已尝试次数
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectDelaySeconds = 10;

  /// 登录令牌（attachAuth 注入；未登录时后端不推流是预期行为）
  String? _authToken;

  // 服务器配置
  String _serverHost = 'localhost';
  int _serverPort = 8765;

  // === 视频源配置 ===
  VideoSourceType _videoSourceType = VideoSourceType.websocket;
  Timer? _httpStreamTimer;
  String _localVideoPath = '';      // 本地视频路径
  String _rtspUrl = '';             // RTSP流地址
  String _httpStreamUrl = '';       // HTTP图片流地址

  // 视频帧数据（旧字段，保留兼容未迁移页面；不再每帧 notifyListeners）
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

  // Getters（旧接口，保留兼容）
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

  /// 当前鉴权令牌（attachAuth 注入，供诊断/展示）
  String? get authToken => _authToken;

  /// 是否已通过 attachAuth 完成鉴权（连接后未 auth 不推流是预期行为）
  bool get isAuthAttached => _authToken != null && _authToken!.isNotEmpty;

  // ============ Wave 1 新增：鉴权接线 ============

  /// 登录成功后注入 Bearer token，并立即向已连接的后端发送 auth 消息。
  ///
  /// 后端协议（Wave 1 已改造）：连接后仅回 hello；收到
  /// `{"type":"auth","action":"login","token":...}` 且校验通过后才开始
  /// 推送 frame/status/sensors。因此"未登录不推流"是预期行为。
  ///
  /// 若当前未连接，token 会被缓存，重连成功后自动补发。
  void attachAuth(String token) {
    _authToken = token;
    debugPrint('attachAuth: 已注入登录令牌');
    if (_isConnected) {
      _sendAuthMessage();
      // 鉴权完成即请求一次状态，加快首屏遥测呈现
      _send({'type': 'get_status', 'token': token});
    }
  }

  /// 登出时清除令牌；后端将停止推流（下次登录重新 attachAuth）
  void detachAuth() {
    _authToken = null;
    debugPrint('detachAuth: 已清除登录令牌');
  }

  /// 发送 auth 鉴权消息（协议见 attachAuth 注释）
  void _sendAuthMessage() {
    final token = _authToken;
    if (token == null || token.isEmpty) return;
    _send({'type': 'auth', 'action': 'login', 'token': token});
  }

  // ============ Wave 1 新增：节流通知 ============

  /// 遥测通道推送（≤5Hz 节流；数据始终先落到 _telemetryLatest 保证最新）
  void _pushTelemetry() {
    final snap = TelemetrySnapshot(
      status: _rovStatus,
      sensors: _sensorData,
      pixhawk: _pixhawkStatus,
      rdk: _rdkStatus,
      lastUpdated: DateTime.now(),
    );
    _telemetryLatest = snap;

    final now = DateTime.now();
    final elapsed = now.difference(_lastTelemetryPush);
    if (elapsed >= _telemetryInterval) {
      _lastTelemetryPush = now;
      telemetryNotifier.value = snap;
    } else if (!_telemetryPushPending) {
      _telemetryPushPending = true;
      Timer(_telemetryInterval - elapsed, () {
        _telemetryPushPending = false;
        _lastTelemetryPush = DateTime.now();
        if (_telemetryLatest != null) {
          telemetryNotifier.value = _telemetryLatest;
        }
      });
    }
  }

  /// 旧 ChangeNotifier 低频通知（≤2Hz 节流；高频数据不得走此路径）
  void _notifyThrottled() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastLegacyNotify);
    if (elapsed >= _legacyNotifyInterval) {
      _lastLegacyNotify = now;
      notifyListeners();
    } else if (!_legacyNotifyPending) {
      _legacyNotifyPending = true;
      Timer(_legacyNotifyInterval - elapsed, () {
        _legacyNotifyPending = false;
        _lastLegacyNotify = DateTime.now();
        notifyListeners();
      });
    }
  }

  /// 更新连接状态通道（仅状态真正变化时通知）
  void _updateConnection(RovConnectionPhase phase, String message) {
    final old = connectionNotifier.value;
    _connectionStatus = message;
    if (old.phase != phase || old.message != message) {
      connectionNotifier.value = RovConnectionState(
        phase: phase,
        message: message,
        lastUpdated: DateTime.now(),
      );
    }
  }

  /// 调度自动重连（指数退避：2s → 4s → 8s → 封顶 10s）
  void _scheduleReconnect() {
    if (_manualDisconnect || _reconnectTimer != null) return;
    int delaySeconds = 2;
    if (_reconnectAttempts > 0) {
      final exp = (_reconnectAttempts - 1).clamp(0, 4).toInt();
      delaySeconds = (2 << exp).clamp(2, _maxReconnectDelaySeconds).toInt();
    }
    _reconnectAttempts++;
    debugPrint(
        '将在 $delaySeconds 秒后重连 $_serverHost:$_serverPort（第 $_reconnectAttempts 次）');
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _reconnectTimer = null;
      if (_manualDisconnect) return;
      _reconnectNow();
    });
  }

  /// 执行一次重连（不递归阻塞，失败后由 connect 内部再调度）
  Future<void> _reconnectNow() async {
    _updateConnection(RovConnectionPhase.reconnecting, '正在重连...');
    await connect(host: _serverHost, port: _serverPort, isReconnect: true);
  }

  // ============ 视频源设置（旧接口，保留） ============

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
  ///
  /// [isReconnect] 为 true 时表示自动重连路径（失败继续退避重试，
  /// 不覆盖 reconnecting 状态语义）。
  Future<bool> connect({String? host, int? port, bool isReconnect = false}) async {
    if (_isConnected) {
      await disconnect(manual: false);
    }
    _manualDisconnect = false;

    final targetHost = host ?? _serverHost;
    final targetPort = port ?? _serverPort;

    try {
      if (!isReconnect) {
        _updateConnection(RovConnectionPhase.offline, '正在连接...');
        notifyListeners();
      }

      final uri = Uri.parse('ws://$targetHost:$targetPort');
      _channel = WebSocketChannel.connect(uri);

      // 等待连接建立
      await _channel!.ready.timeout(const Duration(seconds: 5));

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _isConnected = true;
      _serverHost = targetHost;
      _serverPort = targetPort;
      _reconnectAttempts = 0;
      _updateConnection(RovConnectionPhase.connected, '已连接');
      notifyListeners();

      // 连接建立后立即鉴权（后端约定：未 auth 只回 hello，不推流）
      _sendAuthMessage();

      return true;
    } catch (e) {
      _isConnected = false;
      if (isReconnect) {
        _updateConnection(
            RovConnectionPhase.reconnecting, '重连失败，稍后自动重试');
      } else {
        _updateConnection(RovConnectionPhase.offline, '连接失败: $e');
        notifyListeners();
      }
      // 自动重连（手动断开时除外）
      _scheduleReconnect();
      return false;
    }
  }

  /// 断开连接
  ///
  /// [manual] 为 true（用户主动断开）时取消自动重连。
  Future<void> disconnect({bool manual = true}) async {
    _manualDisconnect = manual;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHttpStreamTimer();
    await _subscription?.cancel();
    // 自动重连失败后残留的未建立通道，其 sink.close() 可能永不完成；
    // 加超时兜底，避免 disconnect() 调用方（登出/手动断开）被挂死。
    if (_channel != null) {
      try {
        await _channel!.sink.close().timeout(const Duration(seconds: 2));
      } catch (_) {
        // 关闭失败/超时不阻断本地状态清理
      }
    }
    _channel = null;
    _subscription = null;
    _isConnected = false;
    _currentFrame = null;
    _detections = [];
    videoFrameNotifier.value = null;
    if (manual) {
      _updateConnection(RovConnectionPhase.offline, '已断开');
      notifyListeners();
    }
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
        // Base64编码的视频帧（契约§5：含 sent_ts/width/height/fps/camera_id）
        if (data['camera_id'] != null) {
          _activeCameraId = data['camera_id'] as String;
        }
        if (data['data'] != null) {
          final frameData = base64Decode(data['data'] as String);
          _handleFrameData(frameData, meta: data);
        }
        break;

      case 'detections':
        // YOLO检测结果（独立消息形态）
        final results = (data['results'] as List?)?.map((e) {
          return DetectionResult.fromJson(e as Map<String, dynamic>);
        }).toList() ?? [];
        _detections = results;
        _notifyThrottled();
        break;

      case 'distance':
        // 两点距离测量结果
        _measuredDistance = (data['distance'] as num?)?.toDouble();
        notifyListeners();
        break;

      case 'status':
        // ROV状态更新（遥测通道 ≤5Hz 下发；旧通知 ≤2Hz）
        final status = data['data'] as Map<String, dynamic>? ?? {};
        _rovStatus = status;
        _rdkStatus = status['rdk'] as Map<String, dynamic>? ?? {};
        _pixhawkStatus = status['pixhawk'] as Map<String, dynamic>? ?? {};
        if (_rdkStatus['active_camera'] != null) {
          _activeCameraId = _rdkStatus['active_camera'] as String;
        }
        _pushTelemetry();
        _notifyThrottled();
        break;

      case 'sensors':
        // RDK X5 传感器遥测
        _sensorData = data['data'] as Map<String, dynamic>? ?? {};
        _pixhawkStatus = data['pixhawk'] as Map<String, dynamic>? ?? {};
        _lastSensorsTs = DateTime.now();
        _pushTelemetry();
        _notifyThrottled();
        break;

      case 'hello':
        // 后端连接问候（Wave 1 协议：auth 前只回 hello），无需处理
        debugPrint('后端 hello: ${data['message'] ?? data['proto'] ?? ''}');
        break;

      case 'auth':
        // 鉴权结果反馈（成功/失败均记录，便于排查"无流"问题）
        debugPrint(
            '后端鉴权结果: ok=${data['ok'] ?? data['success']} msg=${data['message'] ?? ''}');
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
  ///
  /// [meta] 为 frame 消息原始 JSON（含 width/height/fps/sent_ts/camera_id/
  /// detections 等）；HTTP 图片流等来源无 meta，字段留空。
  /// 注意：本方法**只更新 videoFrameNotifier**，不再触发全局
  /// notifyListeners（Wave 1 性能重构核心点）。
  void _handleFrameData(Uint8List frameData, {Map<String, dynamic>? meta}) {
    _currentFrame = frameData;

    // 计算实测帧率（1秒窗口）
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

    // 解析帧内联检测框（契约§7：检测框来自 frame.detections[] 真实推理）
    List<DetectionResult> inlineDetections = const [];
    final rawDet = meta?['detections'];
    if (rawDet is List) {
      inlineDetections = rawDet
          .whereType<Map<String, dynamic>>()
          .map(DetectionResult.fromJson)
          .toList();
      _detections = inlineDetections;
    }

    // 只更新帧通道（视频组件按帧重建，其余页面不受影响）
    videoFrameNotifier.value = VideoFrame(
      jpegBytes: frameData,
      width: (meta?['width'] as num?)?.toInt(),
      height: (meta?['height'] as num?)?.toInt(),
      fps: (meta?['fps'] as num?)?.toDouble() ?? _frameRate.toDouble(),
      cameraId: meta?['camera_id'] as String? ?? _activeCameraId,
      sentTs: (meta?['sent_ts'] as num?)?.toDouble(),
      receivedAt: now,
      detections: inlineDetections,
    );
  }

  /// 连接错误处理
  void _onError(dynamic error) {
    _isConnected = false;
    _updateConnection(RovConnectionPhase.reconnecting, '连接错误: $error');
    notifyListeners();
    _scheduleReconnect();
  }

  /// 连接关闭处理
  void _onDone() {
    _isConnected = false;
    if (!_manualDisconnect) {
      _updateConnection(RovConnectionPhase.reconnecting, '连接已断开，正在重连...');
      notifyListeners();
      _scheduleReconnect();
    }
  }

  // === 控制命令 ===

  /// 发送ROV控制命令
  void sendCommand(RovCommand command, {Map<String, dynamic>? params}) {
    final message = {
      'type': 'command',
      'command': command.name,
      'token': _authToken ?? UserSession().authToken ?? '',
      'timestamp': DateTime.now().toIso8601String(),
      ...?params,
    };
    _send(message);
    debugPrint('发送命令: ${command.name}');
  }

  /// 修改 RDK X5 连接地址（网线直连配置）
  void sendRdkConfig(String host, int port) {
    _send({
      'type': 'set_rdk_config',
      'host': host,
      'port': port,
      'token': _authToken ?? UserSession().authToken ?? '',
    });
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

  /// 切换 RDK X5 摄像头（camera_1 前视 / camera_2 吸口近距）
  void switchCamera(String cameraId) {
    _send({
      'type': 'command',
      'command': 'set_camera',
      'params': {'camera_id': cameraId},
      'token': _authToken ?? UserSession().authToken ?? '',
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
    _send({'type': 'get_status', 'token': _authToken ?? UserSession().authToken ?? ''});
  }

  @override
  void dispose() {
    disconnect();
    _reconnectTimer?.cancel();
    videoFrameNotifier.dispose();
    telemetryNotifier.dispose();
    connectionNotifier.dispose();
    super.dispose();
  }
}
