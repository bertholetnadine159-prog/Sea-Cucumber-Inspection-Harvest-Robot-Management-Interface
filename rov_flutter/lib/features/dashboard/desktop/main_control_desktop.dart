import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/services/rov_backend_service.dart';
import '../../shared/widgets/motion_kit.dart';
import '../../shared/widgets/stale_badge.dart';
import '../../shared/widgets/status_badge.dart';

/// 桌面端主控界面（旧版 1cc31e5 视觉还原 + 真实数据绑定）
///
/// 视觉还原自旧版：标题栏状态芯片、视频区暗角/录制徽章/坐标卡/键帽提示、
/// 256×256 方向控制器与上浮/下潜侧钮、右栏状态卡/水温特色卡/快捷操作/日志面板。
///
/// Wave 2 真实化说明（契约§7 数据真实回传，样式照抄、数据接真）：
/// - 分辨率/帧率/≈链路时延：videoFrameNotifier 的真实帧字段，无源不显示；
/// - 标题栏芯片：旧版假"信号强度 -45dBm/能耗 120W"改为真实
///   电池电量（telemetry.pixhawk）与 RDK 链路状态芯片；
/// - 左下坐标卡：旧版假坐标"N 38°55'/E 121°38'"改为真实当前深度
///   （ms5837_depth），无源显示 --；
/// - 声呐/激光/自动巡航开关不复活（后端无实现，契约§7-③）；
/// - 灯光保留（真实 PWM 命令 setLight）；推进器动力为方向命令携带的
///   真实 speed 参数（可调滑块 + 同值进度条）；
/// - 检测日志为 videoFrameNotifier 每帧 detections[] 真实滚动；
/// - 时钟为本地真实时间，每秒动态刷新。
class MainControlDesktop extends StatefulWidget {
  const MainControlDesktop({super.key});

  @override
  State<MainControlDesktop> createState() => _MainControlDesktopState();
}

class _MainControlDesktopState extends State<MainControlDesktop> {
  // 灯光开关状态（真实 PWM 命令：setLight）
  bool _lightingOn = false;

  // 后端服务
  final _backendService = RovBackendService();

  // 测量模式（两点测距）
  bool _measureMode = false;

  // 推进器动力（发送方向命令时携带的真实 speed 参数，滑块可调）
  double _thrusterPower = 0.65;

  // 状态轮询定时器（后端持续推送之外的保底刷新）
  Timer? _statusTimer;

  // 键盘焦点
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // 低频状态（测量点/测距结果）仍走旧通知通道，仅触发本页 setState
    _backendService.addListener(_onBackendUpdate);
    // 保底状态轮询：遥测主通道为后端主动推送
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_backendService.isConnected) {
        _backendService.requestStatus();
      }
    });
  }

  @override
  void dispose() {
    _backendService.removeListener(_onBackendUpdate);
    _statusTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _onBackendUpdate() {
    if (mounted) setState(() {});
  }

  /// 处理键盘事件（WASD 推进、空格抓取；松开即停）
  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyW:
          _backendService.forward(speed: _thrusterPower);
          break;
        case LogicalKeyboardKey.keyS:
          _backendService.backward(speed: _thrusterPower);
          break;
        case LogicalKeyboardKey.keyA:
          _backendService.turnLeft(speed: _thrusterPower);
          break;
        case LogicalKeyboardKey.keyD:
          _backendService.turnRight(speed: _thrusterPower);
          break;
        case LogicalKeyboardKey.space:
          _backendService.grab();
          break;
        default:
          break;
      }
    } else if (event is KeyUpEvent) {
      // 松开按键时停止
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyW:
        case LogicalKeyboardKey.keyS:
        case LogicalKeyboardKey.keyA:
        case LogicalKeyboardKey.keyD:
          _backendService.stop();
          break;
        default:
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _buildContent(isDark),
        ),
      ),
    );
  }

  /// 构建主体内容（旧版布局：左 flex7 视频/控制条/方向盘，右 flex3 信息栏）
  Widget _buildContent(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        _buildTitleBar(isDark),
        const SizedBox(height: 24),
        // 主体布局 - 移除最大宽度限制，使用flex比例填充
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧主内容区
            Expanded(
              flex: 7,
              child: Column(
                children: [
                  // 视频监控区
                  _buildVideoSection(),
                  const SizedBox(height: 24),
                  // 设备控制条
                  _buildControlBar(),
                  const SizedBox(height: 24),
                  // 方向控制面板
                  _buildDirectionPanel(),
                ],
              ),
            ),
            const SizedBox(width: 24),
            // 右侧信息区 - 使用Expanded自适应
            Expanded(
              flex: 3,
              child: _buildRightPanel(),
            ),
          ],
        ),
      ],
    );
  }

  /// 构建标题栏（旧版样式；副行与右侧芯片全部接真实数据）
  Widget _buildTitleBar(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('实时监控中心', style: AppTextStyles.h2.copyWith(
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            )),
            const SizedBox(height: 4),
            // 真实连接状态（connectionNotifier）+ 真实后端地址
            ValueListenableBuilder<RovConnectionState>(
              valueListenable: _backendService.connectionNotifier,
              builder: (context, conn, _) {
                final level = switch (conn.phase) {
                  RovConnectionPhase.connected => AppStatusLevel.success,
                  RovConnectionPhase.reconnecting => AppStatusLevel.warning,
                  RovConnectionPhase.offline => AppStatusLevel.danger,
                };
                return Row(
                  children: [
                    StatusBadge(text: conn.message, level: level),
                    const SizedBox(width: 8),
                    Text(
                      '后端 ${_backendService.serverAddress}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        // 旧版右侧状态芯片（样式还原；数据接真：电池电量 + RDK 链路）
        ValueListenableBuilder<TelemetrySnapshot?>(
          valueListenable: _backendService.telemetryNotifier,
          builder: (context, telemetry, _) {
            final px = telemetry?.pixhawk ?? const <String, dynamic>{};
            final batteryRemaining = (px['battery_remaining'] as num?)?.toDouble();
            final batteryV = (px['battery_v'] as num?)?.toDouble();
            final batteryText = batteryRemaining != null
                ? '电池: ${batteryRemaining.toStringAsFixed(0)}%'
                : (batteryV != null ? '电池: ${batteryV.toStringAsFixed(2)}V' : '电池: --');
            final rdkConnected = telemetry?.rdk['connected'] == true;
            return Row(
              children: [
                _buildStatusChip(
                  Icons.battery_charging_full,
                  batteryText,
                  batteryRemaining != null || batteryV != null
                      ? AppColors.success
                      : AppColors.textHint,
                  isDark,
                ),
                const SizedBox(width: 12),
                _buildStatusChip(
                  Icons.signal_cellular_alt,
                  rdkConnected ? 'RDK 链路正常' : 'RDK 未接入',
                  rdkConnected ? AppColors.success : AppColors.warning,
                  isDark,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// 构建状态芯片（旧版胶囊样式：h16 v8 / 圆角 20 / 白底描边）
  Widget _buildStatusChip(IconData icon, String text, Color iconColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Text(text, style: AppTextStyles.caption.copyWith(
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
          )),
        ],
      ),
    );
  }

  /// 构建视频监控区（旧版：16:9 黑底圆角 16 + 大投影 + 暗角渐变叠层）
  Widget _buildVideoSection() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          // 视频画面/叠加层按帧通道（videoFrameNotifier）重建
          child: ValueListenableBuilder<VideoFrame?>(
            valueListenable: _backendService.videoFrameNotifier,
            builder: (context, frame, _) {
              return Stack(
                children: [
                  // 视频画面 - 从Python后端接收的真实帧
                  Positioned.fill(
                    child: GestureDetector(
                      onTapDown: _measureMode ? _onVideoTap : null,
                      child: _buildVideoFrame(frame),
                    ),
                  ),
                  // YOLO检测结果叠加（来自 frame.detections 真实推理）
                  if (frame != null && frame.detections.isNotEmpty)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: DetectionOverlayPainter(
                          detections: frame.detections,
                        ),
                      ),
                    ),
                  // 测量点叠加
                  if (_backendService.point1 != null || _backendService.point2 != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: MeasurePointPainter(
                          point1: _backendService.point1,
                          point2: _backendService.point2,
                          distance: _backendService.measuredDistance,
                        ),
                      ),
                    ),
                  // 渐变遮罩（旧版暗角：stops [0,0.2,0.8,1]）
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.4),
                              Colors.transparent,
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.6),
                            ],
                            stops: const [0, 0.2, 0.8, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 左上角实时画面标识（摄像头来自真实 camera_id）
                  Positioned(
                    top: 16,
                    left: 16,
                    child: _buildLiveBadge(frame),
                  ),
                  // 右上角分辨率/帧率/≈链路时延（真实帧字段，无源不显示）
                  Positioned(
                    top: 16,
                    right: 16,
                    child: _buildVideoInfo(frame),
                  ),
                  // 视频源/摄像头切换/连接状态工具条（top16 居中，旧版三胶囊）
                  Positioned(
                    top: 16,
                    left: 220,
                    right: 220,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _buildVideoToolbar(frame),
                      ),
                    ),
                  ),
                  // 测量模式指示
                  if (_measureMode)
                    Positioned(
                      top: 16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            '测量模式：点击画面标记两点',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  // 距离显示
                  if (_backendService.measuredDistance != null)
                    Positioned(
                      top: 60,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '估计距离: ${_backendService.measuredDistance!.toStringAsFixed(2)} cm',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                  // 左下角深度卡（旧版坐标卡样式；数据接真：ms5837 深度）
                  Positioned(
                    bottom: 64,
                    left: 24,
                    child: _buildDepthCard(),
                  ),
                  // 右下角时间（本地真实时钟，每秒刷新）
                  const Positioned(
                    bottom: 64,
                    right: 24,
                    child: _LiveClock(),
                  ),
                  // 底部控制提示
                  Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: _buildControlHints(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 构建视频帧显示
  Widget _buildVideoFrame(VideoFrame? frame) {
    if (frame != null) {
      return Image.memory(
        frame.jpegBytes,
        fit: BoxFit.cover,
        gaplessPlayback: true, // 防止闪烁
      );
    }
    // 无视频时显示占位信息（连接状态来自 connectionNotifier 真实状态）
    return ValueListenableBuilder<RovConnectionState>(
      valueListenable: _backendService.connectionNotifier,
      builder: (context, conn, _) {
        final connected = conn.phase == RovConnectionPhase.connected;
        final rdkConnected =
            _backendService.telemetryNotifier.value?.rdk['connected'] == true;
        return Container(
          color: Colors.black87,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  connected ? Icons.videocam_off : Icons.link_off,
                  size: 64,
                  color: Colors.white30,
                ),
                const SizedBox(height: 16),
                Text(
                  connected ? '等待视频流...' : conn.message,
                  style: const TextStyle(color: Colors.white54, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  '服务器: ${_backendService.serverAddress}',
                  style: const TextStyle(color: Colors.white30, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  rdkConnected
                      ? 'RDK X5: ${_backendService.telemetryNotifier.value?.rdk['host'] ?? ''} 已连接'
                      : 'RDK X5: 未连接（等待后端桥接）',
                  style: TextStyle(
                    color: rdkConnected ? AppColors.success : Colors.white30,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                if (!connected)
                  ElevatedButton.icon(
                    onPressed: () => _backendService.connect(),
                    icon: const Icon(Icons.link),
                    label: const Text('连接'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 构建视频区工具条（视频源配置 / 摄像头切换 / 连接状态，旧版三胶囊样式）
  Widget _buildVideoToolbar(VideoFrame? frame) {
    final cameraId = frame?.cameraId ?? _backendService.activeCameraId;
    return ValueListenableBuilder<RovConnectionState>(
      valueListenable: _backendService.connectionNotifier,
      builder: (context, conn, _) {
        final isConnected = conn.phase == RovConnectionPhase.connected;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 视频源配置（仅 RDK WebSocket 流，假选项已删除）
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _showVideoSourceDialog,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.settings_input_antenna, size: 14, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        'RDK 视频源',
                        style: AppTextStyles.caption.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // RDK X5 双摄像头切换（前视 / 吸口近距），真实 set_camera 命令
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _backendService.switchCamera(
                  cameraId == 'camera_2' ? 'camera_1' : 'camera_2',
                ),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam, size: 14, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        cameraId == 'camera_2' ? '吸口相机' : '前视相机',
                        style: AppTextStyles.caption.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 连接状态（connectionNotifier 真实状态）
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isConnected ? AppColors.success : AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    conn.message,
                    style: AppTextStyles.caption.copyWith(color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  // 连接/断开按钮
                  InkWell(
                    onTap: () async {
                      if (isConnected) {
                        await _backendService.disconnect();
                      } else {
                        await _backendService.connect();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isConnected ? AppColors.error : AppColors.success,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isConnected ? '断开' : '连接',
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// 显示视频源配置对话框
  void _showVideoSourceDialog() {
    showDialog(
      context: context,
      builder: (context) => _VideoSourceConfigDialog(
        backendService: _backendService,
      ),
    );
  }

  /// 处理视频点击（测量模式）
  void _onVideoTap(TapDownDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    // 计算相对坐标（0-1范围）
    final localPos = details.localPosition;
    final size = box.size;
    final relX = localPos.dx / size.width;
    final relY = localPos.dy / size.height;

    // 设置测量点
    if (_backendService.point1 == null) {
      _backendService.setMeasurePoint1(relX, relY);
    } else if (_backendService.point2 == null) {
      _backendService.setMeasurePoint2(relX, relY);
    } else {
      // 重新开始测量
      _backendService.clearMeasurePoints();
      _backendService.setMeasurePoint1(relX, relY);
    }
  }

  /// 构建实时画面标识（旧版录制徽章样式：black50% 底 + 白20%描边 + 红点；
  /// 摄像头编号来自真实 frame.camera_id）
  Widget _buildLiveBadge(VideoFrame? frame) {
    final cameraId = frame?.cameraId;
    final hasFrame = frame != null;
    final label = cameraId == 'camera_2'
        ? '实时画面 - 02号摄像头'
        : cameraId == 'camera_1'
            ? '实时画面 - 01号摄像头'
            : '实时画面 - 等待视频流';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              // 旧版录制红点：有真实帧时纯红点亮
              color: hasFrame ? Colors.red : Colors.white24,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }

  /// 构建视频信息（真实帧率/分辨率 + ≈链路时延，均来自 VideoFrame；无源不显示）
  Widget _buildVideoInfo(VideoFrame? frame) {
    final width = frame?.width;
    final height = frame?.height;
    final resolution =
        (width != null && height != null) ? '$width×$height' : null;
    final latency = frame?.linkLatencySeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${frame != null ? frame.fps.toStringAsFixed(0) : '--'} fps'
          '${resolution != null ? ' | $resolution' : ''}',
          style: AppTextStyles.timestamp.copyWith(color: Colors.white),
        ),
        // ≈链路时延（契约§5）：sent_ts 缺失或时钟倒挂时为 null，不显示
        if (latency != null) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt, size: 12, color: AppColors.warning),
              const SizedBox(width: 4),
              Text(
                '≈链路时延 ${(latency * 1000).toStringAsFixed(0)}ms',
                style: AppTextStyles.caption.copyWith(color: AppColors.warning),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 构建左下深度卡（旧版坐标卡样式：black40% 底圆角12 + 白10%描边；
  /// 数据接真：ms5837_depth 深度，无源显示 --）
  Widget _buildDepthCard() {
    final telemetry = _backendService.telemetryNotifier.value;
    final depth = _sensorValueFrom(telemetry, 'ms5837_depth', 'depth_m');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前深度',
            style: AppTextStyles.caption.copyWith(color: AppColors.textTertiaryLight),
          ),
          const SizedBox(height: 4),
          // 动效工具箱：数值滚动插值（真实 ms5837 深度；无源 '--'，不合成兜底值）
          AnimatedTelemetryValue(
            value: depth ?? double.nan,
            invalidText: '-- m',
            formatter: (v) => '${v.toStringAsFixed(2)} m',
            style: AppTextStyles.coordinate.copyWith(
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建控制提示（旧版键帽：白40%描边 + 白10%底圆角4）
  Widget _buildControlHints() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildKeyHint('W'),
        _buildKeyHint('A'),
        _buildKeyHint('S'),
        _buildKeyHint('D'),
        const SizedBox(width: 8),
        Text(
          '推进器控制',
          style: AppTextStyles.caption.copyWith(color: Colors.white.withValues(alpha: 0.8)),
        ),
        const SizedBox(width: 24),
        Container(width: 1, height: 24, color: Colors.white.withValues(alpha: 0.2)),
        const SizedBox(width: 24),
        _buildKeyHint('空格', isWide: true),
        const SizedBox(width: 8),
        Text(
          '抓取采集',
          style: AppTextStyles.caption.copyWith(color: Colors.white.withValues(alpha: 0.8)),
        ),
      ],
    );
  }

  Widget _buildKeyHint(String key, {bool isWide = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: EdgeInsets.symmetric(horizontal: isWide ? 16 : 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(4),
        color: Colors.white.withValues(alpha: 0.1),
      ),
      child: Text(
        key,
        style: AppTextStyles.caption.copyWith(color: Colors.white.withValues(alpha: 0.8)),
      ),
    );
  }

  /// 构建设备控制条（旧版白卡开关条；仅保留真实生效的灯光 PWM 控制）
  ///
  /// 旧版"声呐雷达/激光测距/自动巡航"开关为无后端实现的空壳入口，
  /// 按契约§7-③不得复活，此处不还原。
  Widget _buildControlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildSwitchItem('照明系统', _lightingOn, (v) {
            setState(() => _lightingOn = v);
            _backendService.setLight(v);
          }),
          Text(
            '声呐/激光/自动巡航后端无实现，不提供假开关',
            style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchItem(String label, bool value, Function(bool) onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryLight)),
        const SizedBox(width: 12),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.primary,
        ),
      ],
    );
  }

  /// 构建方向控制面板（旧版布局：上浮/下潜侧钮 + 256×256 圆形控制器，
  /// 全部走真实方向命令：按住推进、松开即停）
  Widget _buildDirectionPanel() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 上浮按钮
          _buildVerticalButton(Icons.expand_less, '上浮', () => _backendService.ascend(speed: _thrusterPower)),
          const SizedBox(width: 48),
          // 中央方向控制
          _buildDirectionController(),
          const SizedBox(width: 48),
          // 下潜按钮
          _buildVerticalButton(Icons.expand_more, '下潜', () => _backendService.descend(speed: _thrusterPower)),
        ],
      ),
    );
  }

  Widget _buildVerticalButton(IconData icon, String label, VoidCallback onPressed) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTapDown: (_) => onPressed(),
          onTapUp: (_) => _backendService.stop(),
          onTapCancel: () => _backendService.stop(),
          child: Material(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Icon(icon, color: AppColors.primary),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }

  Widget _buildDirectionController() {
    return SizedBox(
      width: 256,
      height: 256,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 圆形背景（旧版：borderLight 2px 描边 + primary 5% 填充）
          Container(
            width: 256,
            height: 256,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.borderLight, width: 2, style: BorderStyle.solid),
              color: AppColors.primary.withValues(alpha: 0.05),
            ),
          ),
          // 上
          Positioned(top: 0, child: _buildDirectionButton(Icons.keyboard_arrow_up, '前进', () => _backendService.forward(speed: _thrusterPower))),
          // 下
          Positioned(bottom: 0, child: _buildDirectionButton(Icons.keyboard_arrow_down, '后退', () => _backendService.backward(speed: _thrusterPower))),
          // 左
          Positioned(left: 0, child: _buildDirectionButton(Icons.keyboard_arrow_left, '左转', () => _backendService.turnLeft(speed: _thrusterPower), isHorizontal: true)),
          // 右
          Positioned(right: 0, child: _buildDirectionButton(Icons.keyboard_arrow_right, '右转', () => _backendService.turnRight(speed: _thrusterPower), isHorizontal: true)),
          // 中心按钮 - 停止（primary 30% blur16 spread2 光晕）
          GestureDetector(
            onTap: () => _backendService.stop(),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.videogame_asset, color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionButton(IconData icon, String label, VoidCallback onPressed, {bool isHorizontal = false}) {
    final width = isHorizontal ? 64.0 : 48.0;
    final height = isHorizontal ? 48.0 : 64.0;

    return GestureDetector(
      onTapDown: (_) => onPressed(),
      onTapUp: (_) => _backendService.stop(),
      onTapCancel: () => _backendService.stop(),
      child: Material(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.primary),
              Text(label, style: AppTextStyles.caption.copyWith(fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建右侧面板（旧版顺序：报警提醒 → 运行状态 → 飞控 → 水温 → 快捷 → 日志；
  /// 全部接 telemetryNotifier 真实数据，断链 StaleBadge）
  Widget _buildRightPanel() {
    return ValueListenableBuilder<TelemetrySnapshot?>(
      valueListenable: _backendService.telemetryNotifier,
      builder: (context, telemetry, _) {
        // 动效工具箱：右栏卡片错峰入场（仅首次挂载播放，数据刷新不重放）
        return Column(
          children: [
            // 报警提醒（真实链路状态推导，非旧版固定文案）
            StaggerIn(index: 0, child: _buildAlarmCard(telemetry)),
            const SizedBox(height: 16),
            // 运行状态卡片（RDK/Pixhawk/后端链路真实状态）
            StaggerIn(index: 1, child: _buildRunStatusCard(telemetry)),
            const SizedBox(height: 16),
            // 飞控状态（解锁/模式/电池电压/剩余电量，真实 pixhawk 字段）
            StaggerIn(index: 2, child: _buildPixhawkCard(telemetry)),
            const SizedBox(height: 16),
            // 环境水温卡
            StaggerIn(index: 3, child: _buildWaterCard(telemetry)),
            const SizedBox(height: 16),
            // 快捷操作
            StaggerIn(index: 4, child: _buildQuickActions()),
            const SizedBox(height: 16),
            // 实时检测日志（真实数据源：每帧 detections[]）
            const StaggerIn(index: 5, child: _DetectionLogPanel()),
          ],
        );
      },
    );
  }

  /// 报警提醒卡（旧版样式；内容由真实链路状态推导）
  (String, Color) _alarmState(TelemetrySnapshot? telemetry) {
    if (!_backendService.isConnected) {
      return ('后端链路未连接', AppColors.error);
    }
    if (telemetry == null) {
      return ('等待遥测数据', AppColors.warning);
    }
    if (telemetry.rdk['connected'] != true) {
      return ('RDK X5 未接入', AppColors.warning);
    }
    if (telemetry.ageSeconds > 5) {
      return ('遥测数据超时', AppColors.warning);
    }
    return ('无异常', AppColors.success);
  }

  Widget _buildAlarmCard(TelemetrySnapshot? telemetry) {
    final (text, color) = _alarmState(telemetry);
    return _buildStatusCard(
      Icons.error_outline,
      '报警提醒',
      text,
      color,
      trailing: StaleBadge(lastUpdated: telemetry?.lastUpdated),
    );
  }

  /// 运行状态卡片（RDK/Pixhawk/后端链路真实状态）
  Widget _buildRunStatusCard(TelemetrySnapshot? telemetry) {
    String statusText;
    Color iconColor;
    if (telemetry != null && telemetry.rdk['connected'] == true) {
      statusText = 'RDK X5 已连接';
      iconColor = AppColors.success;
    } else if (telemetry != null && telemetry.pixhawk['connected'] == true) {
      statusText = 'Pixhawk 已连接';
      iconColor = AppColors.success;
    } else if (_backendService.isConnected) {
      statusText = '后端已连接';
      iconColor = AppColors.warning;
    } else {
      statusText = '未连接';
      iconColor = AppColors.error;
    }
    return _buildStatusCard(
      Icons.check_circle_outline,
      '运行状态',
      statusText,
      iconColor,
      trailing: StaleBadge(lastUpdated: telemetry?.lastUpdated),
    );
  }

  /// 旧版状态卡样式：48 圆形图标 tile（图标色 10% 底）+ caption/h3
  Widget _buildStatusCard(
    IconData icon,
    String label,
    String value,
    Color iconColor, {
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(label, style: AppTextStyles.caption),
                    const Spacer(),
                    ?trailing,
                  ],
                ),
                Text(value, style: AppTextStyles.h3),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 飞控（Pixhawk）状态卡片：解锁/模式/电池均来自 telemetry.pixhawk 真实字段
  Widget _buildPixhawkCard(TelemetrySnapshot? telemetry) {
    final px = telemetry?.pixhawk ?? const <String, dynamic>{};
    final lastUpdated = telemetry?.lastUpdated;
    final armed = _asBool(px['armed']);
    final mode = px['mode']?.toString();
    final batteryV = (px['battery_v'] as num?)?.toDouble();
    final batteryRemaining = (px['battery_remaining'] as num?)?.toDouble();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flight_takeoff, color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text('飞控状态', style: AppTextStyles.subtitle)),
              StaleBadge(lastUpdated: lastUpdated),
            ],
          ),
          const SizedBox(height: 12),
          _kvRow('解锁状态', px.isEmpty ? null : (armed ? '已解锁' : '已锁定')),
          _kvRow('飞行模式', mode),
          _kvRow('电池电压', batteryV != null ? '${batteryV.toStringAsFixed(2)} V' : null),
          _kvRow(
              '剩余电量', batteryRemaining != null ? '${batteryRemaining.toStringAsFixed(0)} %' : null),
        ],
      ),
    );
  }

  /// 键值行（值为 null 时显示 "--"，不合成假值）
  Widget _kvRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.caption),
          Text(
            value ?? '--',
            style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// 环境水温卡片（真实传感器：ds18b20_water_1 / ms5837_depth）
  Widget _buildWaterCard(TelemetrySnapshot? telemetry) {
    final lastUpdated = telemetry?.lastUpdated;
    final waterTemp = _sensorValueFrom(telemetry, 'ds18b20_water_1', 'temperature_c') ??
        _sensorValueFrom(telemetry, 'ms5837_depth', 'temperature_c');
    final depth = _sensorValueFrom(telemetry, 'ms5837_depth', 'depth_m');
    final frontDistance =
        _sensorValueFrom(telemetry, 'ultrasonic_front_suction_mouth', 'distance_m');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: AppColors.surfaceLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.thermostat, color: AppColors.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('环境水温',
                        style: AppTextStyles.caption.copyWith(color: AppColors.primary)),
                    const Spacer(),
                    StaleBadge(lastUpdated: lastUpdated),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // 动效工具箱：数值滚动插值（真实遥测驱动；无源 '--'，不合成兜底值）
                    if (waterTemp != null)
                      AnimatedTelemetryValue(
                        value: waterTemp,
                        decimals: 1,
                        style: AppTextStyles.dataMedium
                            .copyWith(color: AppColors.primary),
                      )
                    else
                      Text(
                        '--',
                        style: AppTextStyles.dataMedium
                            .copyWith(color: AppColors.primary),
                      ),
                    const SizedBox(width: 4),
                    Text('°C', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '深度 ${depth?.toStringAsFixed(2) ?? '--'} m · 前方 ${frontDistance?.toStringAsFixed(2) ?? '--'} m',
                  style: AppTextStyles.caption.copyWith(color: AppColors.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 从遥测快照读取某个传感器的标量值（无源返回 null）
  double? _sensorValueFrom(TelemetrySnapshot? telemetry, String sensor, String key) {
    final data = telemetry?.sensors[sensor];
    if (data is Map && data['ok'] == true && data['values'] is Map) {
      final value = data['values'][key];
      if (value is num) return value.toDouble();
    }
    return null;
  }

  /// bool 兼容解析（后端可能下发布尔或 0/1）
  bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v?.toString().toLowerCase();
    return s == 'true' || s == '1';
  }

  /// 快捷操作（旧版样式：straighten/flash_on 图标头 + 2列网格 + 红色急停
  /// + 推进器动力行；动力为真实 speed 参数：滑块可调 + 同值进度条）
  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('快捷操作', style: AppTextStyles.subtitle),
              Row(
                children: [
                  // 测量模式切换（真实两点测距）
                  IconButton(
                    icon: Icon(
                      Icons.straighten,
                      color: _measureMode ? AppColors.warning : AppColors.textSecondaryLight,
                      size: 16,
                    ),
                    onPressed: () {
                      setState(() {
                        _measureMode = !_measureMode;
                        if (!_measureMode) {
                          _backendService.clearMeasurePoints();
                        }
                      });
                    },
                    tooltip: _measureMode ? '退出测量' : '两点测量',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.flash_on, color: AppColors.primary, size: 16),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildActionButtonWithCallback(Icons.vertical_align_top, '一键上浮', AppColors.warning,
                  () => _backendService.ascend(speed: 1.0)),
              _buildActionButtonWithCallback(Icons.refresh, '坐标归零', AppColors.primary,
                  () => _backendService.resetPosition()),
              _buildActionButtonWithCallback(Icons.wb_incandescent, _lightingOn ? '关闭补光' : '开启补光',
                  AppColors.warning, () {
                setState(() => _lightingOn = !_lightingOn);
                _backendService.setLight(_lightingOn);
              }),
              _buildActionButtonWithCallback(Icons.photo_camera, '快照捕获', AppColors.success,
                  () => _backendService.takeSnapshot()),
            ],
          ),
          const SizedBox(height: 16),
          // 紧急停止（真实命令）
          SizedBox(
            width: double.infinity,
            // 动效工具箱：按压缩放反馈（急停命令仍由 ElevatedButton 直发）
            child: PressableScale(
              child: ElevatedButton(
                onPressed: () => _backendService.emergencyStop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.stop_circle, color: Colors.white),
                    const SizedBox(width: 8),
                    Column(
                      children: [
                        Text('紧急停止',
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                        Text('STOP',
                            style: AppTextStyles.caption
                                .copyWith(color: Colors.white.withValues(alpha: 0.8))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 推进器动力（真实参数：方向命令携带的 speed 值；旧版进度条样式 + 可调滑块）
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('推进器动力', style: AppTextStyles.caption),
                  Text('${(_thrusterPower * 100).round()}%',
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _thrusterPower,
                backgroundColor: AppColors.borderLight,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                borderRadius: BorderRadius.circular(4),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: AppColors.borderLight,
                  thumbColor: AppColors.primary,
                  overlayColor: AppColors.primary.withValues(alpha: 0.1),
                ),
                child: Slider(
                  value: _thrusterPower,
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  label: '${(_thrusterPower * 100).round()}%',
                  onChanged: (v) => setState(() => _thrusterPower = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtonWithCallback(IconData icon, String label, Color color, VoidCallback onTap) {
    // 动效工具箱：按压缩放反馈（点击仍由内部 InkWell 处理）
    return PressableScale(
      child: Material(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 4),
                Text(label, style: AppTextStyles.caption, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 本地真实时钟（每秒刷新，替代原假时钟 16:36:20 / 2026/02/14）
class _LiveClock extends StatefulWidget {
  const _LiveClock();

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${_two(_now.hour)}:${_two(_now.minute)}:${_two(_now.second)}',
          style: AppTextStyles.dataLarge.copyWith(
            color: Colors.white,
            fontSize: 32,
          ),
        ),
        Text(
          '${_now.year}/${_two(_now.month)}/${_two(_now.day)}',
          style: AppTextStyles.timestamp.copyWith(
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

/// 实时检测日志面板（旧版样式：400 高白卡 + show_chart 头 + 条目时间戳/标签chip/
/// 标题/副文；数据源为 videoFrameNotifier 每帧内联的 detections[] 真实滚动，
/// 保留最近 50 条。旧版假日志与"查看完整历史记录"空按钮不复活）
class _DetectionLogPanel extends StatefulWidget {
  const _DetectionLogPanel();

  @override
  State<_DetectionLogPanel> createState() => _DetectionLogPanelState();
}

class _DetectionLogPanelState extends State<_DetectionLogPanel> {
  static const int _maxEntries = 50;

  final RovBackendService _service = RovBackendService();
  final List<_DetectionLogEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _service.videoFrameNotifier.addListener(_onFrame);
  }

  @override
  void dispose() {
    _service.videoFrameNotifier.removeListener(_onFrame);
    super.dispose();
  }

  /// 每帧检测框追加进滚动列表（时间戳 + 标签 + 置信度）
  void _onFrame() {
    final frame = _service.videoFrameNotifier.value;
    if (frame == null || frame.detections.isEmpty) return;
    final now = DateTime.now();
    setState(() {
      for (final d in frame.detections) {
        _entries.insert(
          0,
          _DetectionLogEntry(time: now, label: d.label, confidence: d.confidence),
        );
      }
      if (_entries.length > _maxEntries) {
        _entries.removeRange(_maxEntries, _entries.length);
      }
    });
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  String _fmt(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          // 标题（旧版：show_chart + subtitle + 右侧"实时流"caption）
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderLight)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.show_chart, color: AppColors.primary, size: 16),
                    const SizedBox(width: 8),
                    Text('实时检测日志', style: AppTextStyles.subtitle),
                  ],
                ),
                Text('实时流', style: AppTextStyles.caption),
              ],
            ),
          ),
          // 日志列表（最新在上）
          Expanded(
            child: _entries.isEmpty
                ? Center(
                    child: Text(
                      '暂无检测结果（BPU 未输出检测框）',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textSecondaryLight),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _entries.length,
                    itemBuilder: (context, index) {
                      final e = _entries[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildLogItem(
                          _fmt(e.time),
                          'AI识别',
                          '${e.label} · 置信度 ${(e.confidence * 100).toStringAsFixed(1)}%',
                          '检测框来自 BPU 实时推理',
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 旧版日志条目样式：时间戳 + 标签 chip（primary10%底圆角4）+ 标题 bold + 副文
  Widget _buildLogItem(String time, String tag, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(time, style: AppTextStyles.timestamp),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                tag,
                style: AppTextStyles.caption.copyWith(color: AppColors.primary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(title, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.bold)),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(subtitle, style: AppTextStyles.caption),
        ],
      ],
    );
  }
}

/// 检测日志条目
class _DetectionLogEntry {
  final DateTime time;
  final String label;
  final double confidence;

  const _DetectionLogEntry({
    required this.time,
    required this.label,
    required this.confidence,
  });
}

/// YOLO检测结果叠加绘制器
class DetectionOverlayPainter extends CustomPainter {
  final List<DetectionResult> detections;

  DetectionOverlayPainter({required this.detections});

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()
      ..color = AppColors.success
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final fillPaint = Paint()
      ..color = AppColors.success.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.bold,
      backgroundColor: AppColors.success.withValues(alpha: 0.8),
    );

    for (final detection in detections) {
      // 将相对坐标转换为实际像素坐标
      final rect = Rect.fromLTWH(
        detection.boundingBox.left * size.width,
        detection.boundingBox.top * size.height,
        detection.boundingBox.width * size.width,
        detection.boundingBox.height * size.height,
      );

      // 绘制边界框
      canvas.drawRect(rect, boxPaint);
      canvas.drawRect(rect, fillPaint);

      // 绘制标签
      final textSpan = TextSpan(
        text: ' ${detection.label} ${(detection.confidence * 100).toStringAsFixed(1)}% ',
        style: textStyle,
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // 标签位置在边界框上方
      final labelOffset = Offset(
        rect.left,
        rect.top - textPainter.height - 4,
      );

      // 确保标签不超出画布
      final clampedOffset = Offset(
        labelOffset.dx.clamp(0, size.width - textPainter.width),
        labelOffset.dy.clamp(0, size.height - textPainter.height),
      );

      textPainter.paint(canvas, clampedOffset);
    }
  }

  @override
  bool shouldRepaint(DetectionOverlayPainter oldDelegate) {
    return detections != oldDelegate.detections;
  }
}

/// 测量点绘制器
class MeasurePointPainter extends CustomPainter {
  final MeasurePoint? point1;
  final MeasurePoint? point2;
  final double? distance;

  MeasurePointPainter({this.point1, this.point2, this.distance});

  @override
  void paint(Canvas canvas, Size size) {
    final pointPaint = Paint()
      ..color = AppColors.warning
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = AppColors.warning
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final ringPaint = Paint()
      ..color = AppColors.warning
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // 绘制第一个点
    if (point1 != null) {
      final p1 = Offset(point1!.x * size.width, point1!.y * size.height);
      canvas.drawCircle(p1, 8, pointPaint);
      canvas.drawCircle(p1, 16, ringPaint);

      // 绘制标签
      _drawPointLabel(canvas, p1, '点1', size);
    }

    // 绘制第二个点
    if (point2 != null) {
      final p2 = Offset(point2!.x * size.width, point2!.y * size.height);
      canvas.drawCircle(p2, 8, pointPaint);
      canvas.drawCircle(p2, 16, ringPaint);

      // 绘制标签
      _drawPointLabel(canvas, p2, '点2', size);
    }

    // 绘制连线
    if (point1 != null && point2 != null) {
      final p1 = Offset(point1!.x * size.width, point1!.y * size.height);
      final p2 = Offset(point2!.x * size.width, point2!.y * size.height);
      canvas.drawLine(p1, p2, linePaint);
    }
  }

  void _drawPointLabel(Canvas canvas, Offset position, String label, Size size) {
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.bold,
      backgroundColor: AppColors.warning.withValues(alpha: 0.8),
    );

    final textSpan = TextSpan(text: ' $label ', style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final labelOffset = Offset(
      position.dx + 20,
      position.dy - textPainter.height / 2,
    );

    // 确保标签不超出画布
    final clampedOffset = Offset(
      labelOffset.dx.clamp(0, size.width - textPainter.width),
      labelOffset.dy.clamp(0, size.height - textPainter.height),
    );

    textPainter.paint(canvas, clampedOffset);
  }

  @override
  bool shouldRepaint(MeasurePointPainter oldDelegate) {
    return point1 != oldDelegate.point1 ||
        point2 != oldDelegate.point2 ||
        distance != oldDelegate.distance;
  }
}

/// 视频源配置对话框
///
/// 契约§7：仅保留真实生效的 RDK WebSocket 流；RTSP/本地文件/HTTP 图片流
/// 为无真实链路的假选项（服务层假实现仅剩引用残留），全部删除。
class _VideoSourceConfigDialog extends StatefulWidget {
  final RovBackendService backendService;

  const _VideoSourceConfigDialog({required this.backendService});

  @override
  State<_VideoSourceConfigDialog> createState() => _VideoSourceConfigDialogState();
}

class _VideoSourceConfigDialogState extends State<_VideoSourceConfigDialog> {
  final _wsHostController = TextEditingController();
  final _wsPortController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final parts = widget.backendService.serverAddress.split(':');
    _wsHostController.text = parts.isNotEmpty ? parts.first : 'localhost';
    _wsPortController.text = parts.length > 1 ? parts[1] : '8765';
  }

  @override
  void dispose() {
    _wsHostController.dispose();
    _wsPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('视频源配置（RDK 流）'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('RDK X5 视频流经本地后端 WebSocket 转发，仅支持该真实链路。'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _wsHostController,
                    decoration: const InputDecoration(
                      labelText: '后端主机地址',
                      hintText: 'localhost 或 IP',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _wsPortController,
                    decoration: const InputDecoration(
                      labelText: '端口',
                      hintText: '8765',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _saveAndClose,
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _saveAndClose() {
    final host = _wsHostController.text.trim();
    final port = int.tryParse(_wsPortController.text) ?? 8765;
    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('主机地址不能为空'), backgroundColor: AppColors.error),
      );
      return;
    }
    widget.backendService.setServerAddress(host, port);
    Navigator.of(context).pop();
  }
}
