/// 主控界面 - 移动端
///
/// 功能：视频监控、设备控制、方向控制、状态显示、快捷操作、实时日志
/// 设计稿对应：app/main_control/screen.png
///
/// Wave 2 真实化说明（契约§7 数据真实回传，与桌面版同等清算）：
/// - 分辨率/帧率/≈链路时延：videoFrameNotifier 真实帧字段，无源不显示；
/// - 假坐标"N 38°55'/E 121°38'"、假深度 42.5m、假信号强度"-45dBm"、
///   假功率"120W"、假设备名"ROV-01/全海区/CAM-01"、假日志均已删除；
/// - 深度显示改为真实 ms5837_depth.depth_m（断链 StaleBadge 冻结）；
/// - 时钟为本地真实时间（每秒刷新）；
/// - 解锁/模式/电池来自 telemetryNotifier.pixhawk；
/// - 声呐开关删除（后端仅 ack 空壳），灯光保留（真实 PWM 命令）；
/// - 左倾/右倾空按钮不复活；方向键盘还原旧版布局并接真实命令。
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/rov_backend_service.dart';
import '../../shared/widgets/motion_kit.dart';
import '../../shared/widgets/stale_badge.dart';
import '../../shared/widgets/status_badge.dart';

/// 移动端主控界面
class MainControlMobile extends StatefulWidget {
  const MainControlMobile({super.key});

  @override
  State<MainControlMobile> createState() => _MainControlMobileState();
}

class _MainControlMobileState extends State<MainControlMobile> {
  // 灯光开关状态（真实 PWM 命令：setLight）
  bool _lightingOn = false;

  // 后端服务
  final _backendService = RovBackendService();

  // 测量模式
  bool _measureMode = false;

  // 推进器动力（方向命令携带的真实 speed 参数，滑块可调）
  double _thrusterPower = 0.65;

  // 状态定时器（保底轮询；遥测主通道为后端主动推送）
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    // 低频状态（测量点/测距结果）仍走旧通知通道
    _backendService.addListener(_onBackendUpdate);
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
    super.dispose();
  }

  void _onBackendUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : null,
      body: CustomScrollView(
        slivers: [
          // 渐变头部
          _buildAppBar(context),
          // 内容区域
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 视频监控区域
                  _buildVideoSection(),
                  const SizedBox(height: 16),

                  // 设备控制开关
                  _buildDeviceControls(),
                  const SizedBox(height: 16),

                  // 方向控制面板
                  _buildDirectionControl(),
                  const SizedBox(height: 16),

                  // 状态卡片组
                  _buildStatusCards(),
                  const SizedBox(height: 16),

                  // 快捷操作
                  _buildQuickActions(),
                  const SizedBox(height: 16),

                  // 急停按钮
                  _buildEmergencyStop(),
                  const SizedBox(height: 24),

                  // 实时检测日志
                  const _DetectionLogSection(),
                  const SizedBox(height: 100), // 底部留白
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建渐变AppBar
  ///
  /// 假信息条"ROV-01 / 全海区 / -45dBm / 120W"已删除，
  /// 改为真实连接状态徽标 + 真实后端地址。
  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.headerGradient,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题行（旧版艺术：通知铃铛装饰 + 白圈头像）
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '海参检测系统',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.notifications_outlined,
                              color: Colors.white, size: 22),
                          const SizedBox(width: 16),
                          const CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.white24,
                            child:
                                Icon(Icons.person, color: Colors.white, size: 18),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 信息行：真实连接状态 + 后端地址（connectionNotifier）
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
                          Expanded(
                            child: Text(
                              '后端 ${_backendService.serverAddress}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      backgroundColor: AppColors.gradientStart,
    );
  }

  /// 构建视频监控区域（画面按帧通道重建；坐标假值已删除）
  Widget _buildVideoSection() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3A5F), Color(0xFF0F2027)],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
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
                // YOLO检测结果叠加（frame.detections 真实推理）
                if (frame != null && frame.detections.isNotEmpty)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: MobileDetectionPainter(
                        detections: frame.detections,
                      ),
                    ),
                  ),
                // 测量点叠加
                if (_backendService.point1 != null || _backendService.point2 != null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: MobileMeasurePainter(
                        point1: _backendService.point1,
                        point2: _backendService.point2,
                        distance: _backendService.measuredDistance,
                      ),
                    ),
                  ),
                // 左上角实时状态（LIVE 依据真实连接阶段；摄像头来自 frame.camera_id）
                Positioned(
                  top: 12,
                  left: 12,
                  child: _buildLiveBadge(frame),
                ),
                // 测量模式指示
                if (_measureMode)
                  Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('测量模式',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                // 距离显示
                if (_backendService.measuredDistance != null)
                  Positioned(
                    top: 40,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '距离: ${_backendService.measuredDistance!.toStringAsFixed(2)} cm',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                // 右上角帧率/分辨率/≈链路时延（真实帧字段，无源不显示）
                Positioned(
                  top: 12,
                  right: 12,
                  child: _buildVideoInfo(frame),
                ),
                // 双摄切换胶囊（旧版艺术：black54 底圆角 18 + 前视/吸口小胶囊，
                // 选中 primary 底；真实 set_camera 命令，有帧时显示）
                if (frame != null)
                  Positioned(
                    top: 44,
                    right: 12,
                    child: _buildCameraSwitcher(),
                  ),
                // 中下深度信息（真实 ms5837_depth，断链 StaleBadge）
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ValueListenableBuilder<TelemetrySnapshot?>(
                      valueListenable: _backendService.telemetryNotifier,
                      builder: (context, telemetry, _) {
                        final depth = _sensorValueFrom(
                            telemetry, 'ms5837_depth', 'depth_m');
                        return Column(
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('DEPTH',
                                    style: TextStyle(
                                        fontSize: 8,
                                        color: Colors.white.withValues(alpha: 0.6))),
                                const SizedBox(width: 6),
                                StaleBadge(
                                  lastUpdated: telemetry?.lastUpdated,
                                  fontSize: 9,
                                ),
                              ],
                            ),
                            // 动效工具箱：深度滚动插值（真实 ms5837；无源 '--'，不合成兜底值）
                            AnimatedTelemetryValue(
                              value: depth ?? double.nan,
                              decimals: 2,
                              invalidText: '--',
                              style: const TextStyle(
                                  fontSize: 28,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                            Text('m',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white.withValues(alpha: 0.8))),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                // 右下角时间（本地真实时钟，每秒刷新）
                const Positioned(
                  bottom: 12,
                  right: 12,
                  child: _LiveClock(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 左上角实时状态徽标（LIVE 依据真实连接阶段与帧到达）
  Widget _buildLiveBadge(VideoFrame? frame) {
    final cameraId = frame?.cameraId;
    final cameraLabel = cameraId == 'camera_2'
        ? '吸口'
        : cameraId == 'camera_1'
            ? '前视'
            : cameraId ?? '--';
    return ValueListenableBuilder<RovConnectionState>(
      valueListenable: _backendService.connectionNotifier,
      builder: (context, conn, _) {
        final live = conn.phase == RovConnectionPhase.connected && frame != null;
        return Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: live ? AppColors.success : AppColors.error,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(live ? Icons.fiber_manual_record : Icons.link_off,
                      size: 10, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(live ? 'LIVE' : conn.message,
                      style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('CAM · $cameraLabel',
                  style: const TextStyle(fontSize: 10, color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  /// 右上角视频信息（真实帧率/分辨率 + ≈链路时延；无源不显示）
  Widget _buildVideoInfo(VideoFrame? frame) {
    final width = frame?.width;
    final height = frame?.height;
    final resolution = (width != null && height != null) ? '$width×$height' : null;
    final latency = frame?.linkLatencySeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${frame != null ? frame.fps.toStringAsFixed(0) : '--'} fps'
          '${resolution != null ? ' | $resolution' : ''}',
          style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.8)),
        ),
        // ≈链路时延（契约§5）：sent_ts 缺失或时钟倒挂时为 null，不显示
        if (latency != null) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.success,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '≈链路时延 ${(latency * 1000).toStringAsFixed(0)}ms',
              style: const TextStyle(fontSize: 9, color: Colors.white),
            ),
          ),
        ],
      ],
    );
  }

  /// 双摄切换胶囊（旧版样式；activeCameraId 为真实网关回传）
  Widget _buildCameraSwitcher() {
    final active = _backendService.activeCameraId;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam, size: 14, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            active == 'camera_2' ? '吸口相机' : '前视相机',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
          const SizedBox(width: 8),
          _cameraButton('camera_1', '前视', active),
          _cameraButton('camera_2', '吸口', active),
        ],
      ),
    );
  }

  Widget _cameraButton(String id, String label, String? active) {
    final selected = active == id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: GestureDetector(
        onTap: () => _backendService.switchCamera(id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.white24,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  /// 构建视频帧
  Widget _buildVideoFrame(VideoFrame? frame) {
    if (frame != null) {
      return Image.memory(
        frame.jpegBytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    // 无视频时占位（真实连接状态 + 连接/视频源入口）
    return ValueListenableBuilder<RovConnectionState>(
      valueListenable: _backendService.connectionNotifier,
      builder: (context, conn, _) {
        final connected = conn.phase == RovConnectionPhase.connected;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.blue.shade800.withValues(alpha: 0.6),
                Colors.blue.shade900.withValues(alpha: 0.8),
              ],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  connected ? Icons.videocam_off : Icons.link_off,
                  size: 40,
                  color: Colors.white30,
                ),
                const SizedBox(height: 8),
                Text(
                  connected ? '等待视频...' : conn.message,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 视频源配置（仅 RDK 流）
                    OutlinedButton.icon(
                      onPressed: _showVideoSourceSheet,
                      icon: const Icon(Icons.settings_input_antenna, size: 16),
                      label: const Text('RDK 视频源',
                          style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white30),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 连接按钮
                    ElevatedButton(
                      onPressed: () async {
                        if (connected) {
                          await _backendService.disconnect();
                        } else {
                          await _backendService.connect();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            connected ? AppColors.error : AppColors.primary,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      child: Text(
                        connected ? '断开' : '连接',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 显示视频源配置底部弹窗（仅 RDK WebSocket 流，假选项已删除）
  void _showVideoSourceSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) =>
          _VideoSourceBottomSheet(backendService: _backendService),
    );
  }

  /// 处理视频点击（测量模式）
  void _onVideoTap(TapDownDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPos = details.localPosition;
    final size = box.size;
    final relX = localPos.dx / size.width;
    final relY = localPos.dy / size.height;

    if (_backendService.point1 == null) {
      _backendService.setMeasurePoint1(relX, relY);
    } else if (_backendService.point2 == null) {
      _backendService.setMeasurePoint2(relX, relY);
    } else {
      _backendService.clearMeasurePoints();
      _backendService.setMeasurePoint1(relX, relY);
    }
  }

  /// 构建设备控制开关
  ///
  /// 声呐雷达开关已删除：后端对 sonar 命令仅返回 ack 空壳、无真实执行（契约§7）。
  /// 仅保留真实生效的灯光控制（PWM 命令）。
  Widget _buildDeviceControls() {
    return Row(
      children: [
        Expanded(child: _buildDeviceSwitch('照明灯', Icons.lightbulb_outline,
            _lightingOn, (v) {
          setState(() => _lightingOn = v);
          _backendService.setLight(v);
        })),
      ],
    );
  }

  /// 构建单个设备开关
  Widget _buildDeviceSwitch(String label, IconData icon, bool value,
      ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 24, color: value ? AppColors.primary : AppColors.textHint),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  /// 构建方向控制面板（旧版移动端键盘布局：前进主色键 + 上浮/下潜小方钮 +
  /// 左转/中心/右转 + 后退；左倾/右倾为无后端实现的空壳，不复活。
  /// 全部接真实命令：按住推进、松开即停，携带真实推进器动力 speed）
  Widget _buildDirectionControl() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // 上排：前进 + 上浮
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 80),
              _buildDirectionButton(Icons.arrow_upward, '前进',
                  () => _backendService.forward(speed: _thrusterPower),
                  isPrimary: true),
              const SizedBox(width: 40),
              Column(
                children: [
                  _buildSmallButton(Icons.keyboard_arrow_up, '上浮',
                      () => _backendService.ascend(speed: _thrusterPower)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 中排：左转 / 中心停止 / 右转
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildDirectionButton(Icons.arrow_back, '左转',
                  () => _backendService.turnLeft(speed: _thrusterPower)),
              const SizedBox(width: 24),
              _buildCenterControl(),
              const SizedBox(width: 24),
              _buildDirectionButton(Icons.arrow_forward, '右转',
                  () => _backendService.turnRight(speed: _thrusterPower)),
            ],
          ),
          const SizedBox(height: 16),
          // 下排：后退 + 下潜
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 40),
              _buildDirectionButton(Icons.arrow_downward, '后退',
                  () => _backendService.backward(speed: _thrusterPower)),
              const SizedBox(width: 40),
              Column(
                children: [
                  _buildSmallButton(Icons.keyboard_arrow_down, '下潜',
                      () => _backendService.descend(speed: _thrusterPower)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 推进器动力（真实参数：方向命令携带的 speed 值）
          Row(
            children: [
              const Text('推进器动力',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              Expanded(
                child: Slider(
                  value: _thrusterPower,
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  label: '${(_thrusterPower * 100).round()}%',
                  onChanged: (v) => setState(() => _thrusterPower = v),
                ),
              ),
              Text(
                '${(_thrusterPower * 100).round()}%',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建方向按钮（旧版样式：48 圆，前进键主色实底 + 光晕；
  /// 按住推进、松开即停；动效工具箱：按压缩放为纯视觉反馈，
  /// 命令仍由内部 GestureDetector 的 onTapDown/Up/Cancel 真实下发）
  Widget _buildDirectionButton(IconData icon, String label, VoidCallback onPress,
      {bool isPrimary = false}) {
    return Column(
      children: [
        PressableScale(
          child: GestureDetector(
            onTapDown: (_) => onPress(),
            onTapUp: (_) => _backendService.stop(),
            onTapCancel: () => _backendService.stop(),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isPrimary ? AppColors.primary : Colors.white,
                shape: BoxShape.circle,
                border: isPrimary ? null : Border.all(color: AppColors.border),
                boxShadow: isPrimary
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(icon,
                  color: isPrimary ? Colors.white : AppColors.textPrimary),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
      ],
    );
  }

  /// 构建小方钮（旧版样式：40×40 圆角 12，上浮/下潜；按住推进、松开即停）
  Widget _buildSmallButton(IconData icon, String label, VoidCallback onPress) {
    return Column(
      children: [
        PressableScale(
          child: GestureDetector(
            onTapDown: (_) => onPress(),
            onTapUp: (_) => _backendService.stop(),
            onTapCancel: () => _backendService.stop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, size: 20, color: AppColors.textSecondary),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textHint)),
      ],
    );
  }

  /// 构建中心控制（旧版样式：56 主色圆 + 光晕 + gamepad 图标；点击 = 停止）
  Widget _buildCenterControl() {
    return GestureDetector(
      onTap: () => _backendService.stop(),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 16),
          ],
        ),
        child: const Icon(Icons.gamepad, color: Colors.white, size: 24),
      ),
    );
  }

  /// 构建状态卡片组（真实 telemetryNotifier 绑定，断链 StaleBadge）
  ///
  /// 原"报警提醒：无异常"（无告警数据源）、"运行状态：正常"（假值）已删除，
  /// 改为真实运行状态 + 飞控摘要 + 环境水温。
  Widget _buildStatusCards() {
    return ValueListenableBuilder<TelemetrySnapshot?>(
      valueListenable: _backendService.telemetryNotifier,
      builder: (context, telemetry, _) {
        final lastUpdated = telemetry?.lastUpdated;
        final px = telemetry?.pixhawk ?? const <String, dynamic>{};
        final armed = _asBool(px['armed']);
        final mode = px['mode']?.toString();
        final batteryV = (px['battery_v'] as num?)?.toDouble();
        final waterTemp = _sensorValueFrom(telemetry, 'ds18b20_water_1', 'temperature_c') ??
            _sensorValueFrom(telemetry, 'ms5837_depth', 'temperature_c');

        // 运行状态：依据真实链路
        String runStatus;
        Color runColor;
        if (telemetry != null && telemetry.rdk['connected'] == true) {
          runStatus = 'RDK X5 已连接';
          runColor = AppColors.success;
        } else if (telemetry != null && telemetry.pixhawk['connected'] == true) {
          runStatus = 'Pixhawk 已连接';
          runColor = AppColors.success;
        } else if (_backendService.isConnected) {
          runStatus = '后端已连接';
          runColor = AppColors.warning;
        } else {
          runStatus = '未连接';
          runColor = AppColors.error;
        }

        // 动效工具箱：状态卡错峰入场（仅首次挂载播放，遥测刷新不重放）
        return Column(
          children: [
            // 运行状态（真实链路）
            StaggerIn(
              index: 0,
              child: _buildStatusCard(
                icon: Icons.check_circle_outline,
                iconColor: runColor,
                iconBgColor: runColor.withValues(alpha: 0.1),
                title: '运行状态',
                value: runStatus,
                valueColor: AppColors.textPrimary,
                trailing: StaleBadge(lastUpdated: lastUpdated),
              ),
            ),
            const SizedBox(height: 12),
            // 飞控摘要（pixhawk 真实字段）
            StaggerIn(
              index: 1,
              child: _buildStatusCard(
                icon: Icons.flight_takeoff,
                iconColor: AppColors.primary,
                iconBgColor: AppColors.primary.withValues(alpha: 0.1),
                title: '飞控',
                value: px.isEmpty
                    ? '--'
                    : '${armed ? '已解锁' : '已锁定'} · ${mode ?? '--'} · '
                        '${batteryV != null ? batteryV.toStringAsFixed(2) : '--'}V',
                valueColor: AppColors.textPrimary,
                trailing: StaleBadge(lastUpdated: lastUpdated),
              ),
            ),
            const SizedBox(height: 12),
            // 环境水温（真实传感器）
            StaggerIn(
              index: 2,
              child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF87CEEB), Color(0xFF60A5FA)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.thermostat, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('环境水温',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.8))),
                        // 动效工具箱：水温滚动插值（真实传感器；无源 '--'）
                        AnimatedTelemetryValue(
                          value: waterTemp ?? double.nan,
                          invalidText: '--',
                          formatter: (v) => '${v.toStringAsFixed(1)}°C',
                          style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  StaleBadge(lastUpdated: lastUpdated, fontSize: 9),
                ],
              ),
            ),
            ),
          ],
        );
      },
    );
  }

  /// 构建状态卡片
  Widget _buildStatusCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required String value,
    required Color valueColor,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                Text(value,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: valueColor)),
              ],
            ),
          ),
          ?trailing,
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

  /// 构建快捷操作（全部为真实命令）
  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('快捷操作',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            // 测量模式切换（真实两点测距）
            GestureDetector(
              onTap: () {
                setState(() {
                  _measureMode = !_measureMode;
                  if (!_measureMode) {
                    _backendService.clearMeasurePoints();
                  }
                });
              },
              child: Icon(Icons.straighten,
                  size: 20,
                  color: _measureMode ? AppColors.warning : AppColors.textHint),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.8,
          children: [
            _buildQuickActionButton(Icons.arrow_upward, '一键上浮',
                () => _backendService.ascend(speed: 1.0)),
            _buildQuickActionButton(
                Icons.gps_fixed, '坐标归零', () => _backendService.resetPosition()),
            _buildQuickActionButton(Icons.flashlight_on_outlined,
                _lightingOn ? '关闭补光' : '开启补光', () {
              setState(() => _lightingOn = !_lightingOn);
              _backendService.setLight(_lightingOn);
            }),
            _buildQuickActionButton(
                Icons.camera_alt, '快照捕获', () => _backendService.takeSnapshot()),
          ],
        ),
      ],
    );
  }

  /// 构建快捷操作按钮
  Widget _buildQuickActionButton(IconData icon, String label, VoidCallback onTap) {
    // 动效工具箱：按压缩放 + 点击（真实命令经 onTap 下发）
    return PressableScale(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: AppColors.primary),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  /// 构建急停按钮（真实 emergencyStop 命令）
  Widget _buildEmergencyStop() {
    // 动效工具箱：按压缩放反馈（急停命令经 onTap 直发，无确认弹窗的旧版形态）
    return PressableScale(
      onTap: () => _backendService.emergencyStop(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            const Text(
              '急停',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 本地真实时钟（每秒刷新）
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
          style: const TextStyle(
              fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
        ),
        Text(
          '${_now.year}/${_two(_now.month)}/${_two(_now.day)}',
          style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.7)),
        ),
      ],
    );
  }
}

/// 实时检测日志区（真实数据源：每帧 detections[]，保留最近 50 条）
class _DetectionLogSection extends StatefulWidget {
  const _DetectionLogSection();

  @override
  State<_DetectionLogSection> createState() => _DetectionLogSectionState();
}

class _DetectionLogSectionState extends State<_DetectionLogSection> {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('实时检测日志',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Text('数据源：frame.detections',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_entries.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              '暂无检测结果',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: _entries.length,
              separatorBuilder: (_, _) => const Divider(height: 16),
              itemBuilder: (context, index) {
                final e = _entries[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_fmt(e.time),
                        style:
                            const TextStyle(fontSize: 12, color: AppColors.textHint)),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('AI识别',
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.primary)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${e.label} · 置信度 ${(e.confidence * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
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

/// 移动端检测结果绘制器
class MobileDetectionPainter extends CustomPainter {
  final List<DetectionResult> detections;

  MobileDetectionPainter({required this.detections});

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final bgPaint = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.15);

    for (final detection in detections) {
      final rect = Rect.fromLTWH(
        detection.boundingBox.left * size.width,
        detection.boundingBox.top * size.height,
        detection.boundingBox.width * size.width,
        detection.boundingBox.height * size.height,
      );

      // 绘制背景
      canvas.drawRect(rect, bgPaint);
      // 绘制边框
      canvas.drawRect(rect, boxPaint);

      // 绘制标签
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${detection.label} ${(detection.confidence * 100).toInt()}%',
          style: const TextStyle(
            color: Colors.greenAccent,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // 标签背景
      final labelRect = Rect.fromLTWH(
        rect.left,
        rect.top - 16,
        textPainter.width + 8,
        16,
      );
      canvas.drawRect(
          labelRect, Paint()..color = Colors.greenAccent.withValues(alpha: 0.8));
      textPainter.paint(canvas, Offset(rect.left + 4, rect.top - 14));
    }
  }

  @override
  bool shouldRepaint(MobileDetectionPainter oldDelegate) =>
      detections != oldDelegate.detections;
}

/// 移动端测量点绘制器
class MobileMeasurePainter extends CustomPainter {
  final MeasurePoint? point1;
  final MeasurePoint? point2;
  final double? distance;

  MobileMeasurePainter({this.point1, this.point2, this.distance});

  @override
  void paint(Canvas canvas, Size size) {
    final pointPaint = Paint()
      ..color = AppColors.warning
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = AppColors.warning
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // 绘制点1
    if (point1 != null) {
      final p1 = Offset(point1!.x * size.width, point1!.y * size.height);
      canvas.drawCircle(p1, 6, pointPaint);
      canvas.drawCircle(p1, 8, linePaint);

      // 绘制点2和连线
      if (point2 != null) {
        final p2 = Offset(point2!.x * size.width, point2!.y * size.height);
        canvas.drawCircle(p2, 6, pointPaint);
        canvas.drawCircle(p2, 8, linePaint);

        // 连线
        canvas.drawLine(p1, p2, linePaint);
      }
    }
  }

  @override
  bool shouldRepaint(MobileMeasurePainter oldDelegate) =>
      point1 != oldDelegate.point1 ||
      point2 != oldDelegate.point2 ||
      distance != oldDelegate.distance;
}

/// 视频源配置底部弹窗
///
/// 契约§7：仅保留真实生效的 RDK WebSocket 流；RTSP/本地文件/HTTP 图片流
/// 为无真实链路的假选项，全部删除。
class _VideoSourceBottomSheet extends StatefulWidget {
  final RovBackendService backendService;

  const _VideoSourceBottomSheet({required this.backendService});

  @override
  State<_VideoSourceBottomSheet> createState() => _VideoSourceBottomSheetState();
}

class _VideoSourceBottomSheetState extends State<_VideoSourceBottomSheet> {
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
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('视频源配置',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('仅支持 RDK X5 真实视频流。',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          // 配置表单
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _wsHostController,
                  decoration: const InputDecoration(
                    labelText: '后端主机',
                    hintText: 'localhost',
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
          const SizedBox(height: 20),
          // 保存按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveAndClose,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('保存配置'),
            ),
          ),
        ],
      ),
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
