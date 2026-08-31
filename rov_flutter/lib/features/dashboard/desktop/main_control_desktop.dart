import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/rov_backend_service.dart';

/// 桌面端主控界面
/// 包含实时监控画面、设备控制、方向控制面板和状态信息
class MainControlDesktop extends StatefulWidget {
  const MainControlDesktop({super.key});

  @override
  State<MainControlDesktop> createState() => _MainControlDesktopState();
}

class _MainControlDesktopState extends State<MainControlDesktop> {
  // 设备开关状态
  bool _lightingOn = true;
  bool _sonarOn = true;
  bool _laserOn = false;
  bool _autoCruise = false;
  
  // 后端服务
  final _backendService = RovBackendService();
  
  // 测量模式
  bool _measureMode = false;
  
  // 推进器动力
  double _thrusterPower = 0.65;
  
  // 连接状态定时器
  Timer? _statusTimer;
  
  // 键盘焦点
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _backendService.addListener(_onBackendUpdate);
    // 启动状态更新定时器
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

  /// 处理键盘事件
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

  /// 构建主体内容
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

  /// 构建标题栏
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
            Text(
              '正在连接: ROV-DEEPSEA-01 · 大连金海区检测点',
              style: AppTextStyles.bodySmall.copyWith(
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
        Row(
          children: [
            _buildStatusChip(Icons.signal_cellular_alt, '信号强度: 强 (-45dBm)', AppColors.success, isDark),
            const SizedBox(width: 12),
            _buildStatusChip(Icons.bolt, '能耗: 120W', AppColors.warning, isDark),
          ],
        ),
      ],
    );
  }

  /// 构建状态芯片
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

  /// 构建视频监控区
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
          child: Stack(
            children: [
              // 视频画面 - 从Python后端接收
              Positioned.fill(
                child: GestureDetector(
                  onTapDown: _measureMode ? _onVideoTap : null,
                  child: _buildVideoFrame(),
                ),
              ),
              // YOLO检测结果叠加
              if (_backendService.detections.isNotEmpty)
                Positioned.fill(
                  child: CustomPaint(
                    painter: DetectionOverlayPainter(
                      detections: _backendService.detections,
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
              // 渐变遮罩
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
              // 左上角录制状态
              Positioned(
                top: 16,
                left: 16,
                child: _buildRecordingBadge(),
              ),
              // 右上角信息
              Positioned(
                top: 16,
                right: 16,
                child: _buildVideoInfo(),
              ),
              // 连接状态
              Positioned(
                top: 16,
                left: 200,
                child: _buildConnectionStatus(),
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
              // 左下角坐标
              Positioned(
                bottom: 64,
                left: 24,
                child: _buildCoordinates(),
              ),
              // 右下角时间
              Positioned(
                bottom: 64,
                right: 24,
                child: _buildDateTime(),
              ),
              // 底部控制提示
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: _buildControlHints(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建视频帧显示
  Widget _buildVideoFrame() {
    final frame = _backendService.currentFrame;
    if (frame != null) {
      return Image.memory(
        frame,
        fit: BoxFit.cover,
        gaplessPlayback: true, // 防止闪烁
      );
    }
    // 无视频时显示占位图
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _backendService.isConnected ? Icons.videocam_off : Icons.link_off,
              size: 64,
              color: Colors.white30,
            ),
            const SizedBox(height: 16),
            Text(
              _backendService.isConnected ? '等待视频流...' : '未连接到后端服务',
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              '服务器: ${_backendService.serverAddress}',
              style: const TextStyle(color: Colors.white30, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(
              _backendService.rdkStatus['connected'] == true
                  ? 'RDK X5: ${_backendService.rdkStatus['host']} 已连接'
                  : 'RDK X5: 未连接（等待后端桥接）',
              style: TextStyle(
                color: _backendService.rdkStatus['connected'] == true ? AppColors.success : Colors.white30,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            if (!_backendService.isConnected)
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
  }

  /// 构建连接状态
  Widget _buildConnectionStatus() {
    final isConnected = _backendService.isConnected;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 视频源选择按钮
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
                    _getVideoSourceLabel(),
                    style: AppTextStyles.caption.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // RDK X5 双摄像头切换（前视 / 吸口近距）
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _backendService.switchCamera(
              _backendService.activeCameraId == 'camera_2' ? 'camera_1' : 'camera_2',
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
                    _backendService.activeCameraId == 'camera_2' ? '吸口相机' : '前视相机',
                    style: AppTextStyles.caption.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // 连接状态
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
                _backendService.connectionStatus,
                style: AppTextStyles.caption.copyWith(color: Colors.white),
              ),
              const SizedBox(width: 8),
              // 连接/断开按钮
              InkWell(
                onTap: () async {
                  if (isConnected) {
                    await _backendService.disconnect();
                  } else {
                    await _backendService.connectVideoSource();
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
  }

  /// 获取视频源标签
  String _getVideoSourceLabel() {
    switch (_backendService.videoSourceType) {
      case VideoSourceType.websocket:
        return 'WebSocket';
      case VideoSourceType.localFile:
        return '本地文件';
      case VideoSourceType.rtsp:
        return 'RTSP';
      case VideoSourceType.httpStream:
        return 'HTTP流';
    }
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

  /// 构建录制状态徽章
  Widget _buildRecordingBadge() {
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
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '实时画面 - 01号摄像头',
            style: AppTextStyles.caption.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }

  /// 构建视频信息
  Widget _buildVideoInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '30 fps | 1920×1080',
          style: AppTextStyles.timestamp.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt, size: 12, color: AppColors.warning),
            const SizedBox(width: 4),
            Text(
              '延迟: 45ms',
              style: AppTextStyles.caption.copyWith(color: AppColors.warning),
            ),
          ],
        ),
      ],
    );
  }

  /// 构建坐标显示
  Widget _buildCoordinates() {
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
            '当前坐标',
            style: AppTextStyles.caption.copyWith(color: AppColors.textTertiaryLight),
          ),
          const SizedBox(height: 4),
          Text(
            "N 38°55' / E 121°38'",
            style: AppTextStyles.coordinate.copyWith(
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建时间显示
  Widget _buildDateTime() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '16:36:20',
          style: AppTextStyles.dataLarge.copyWith(
            color: Colors.white,
            fontSize: 32,
          ),
        ),
        Text(
          '2026/02/14',
          style: AppTextStyles.timestamp.copyWith(
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  /// 构建控制提示
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

  /// 构建设备控制条
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
          _buildDivider(),
          _buildSwitchItem('声呐雷达', _sonarOn, (v) {
            setState(() => _sonarOn = v);
            _backendService.setSonar(v);
          }),
          _buildDivider(),
          _buildSwitchItem('激光测距', _laserOn, (v) {
            setState(() => _laserOn = v);
            _backendService.setLaser(v);
          }),
          _buildDivider(),
          _buildSwitchItem('自动巡航', _autoCruise, (v) {
            setState(() => _autoCruise = v);
            _backendService.setAutoCruise(v);
          }),
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
          activeColor: AppColors.primary,
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(width: 1, height: 32, color: AppColors.borderLight);
  }

  /// 构建方向控制面板
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
          // 圆形背景
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
          // 中心按钮 - 紧急停止
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

  /// 构建右侧面板
  Widget _buildRightPanel() {
    return Column(
      children: [
        // 状态卡片
        _buildStatusCard(Icons.error_outline, '报警提醒', '无异常', AppColors.textSecondaryLight),
        const SizedBox(height: 16),
        _buildStatusCard(Icons.check_circle_outline, '运行状态', _runStatusText(), _runStatusColor()),
        const SizedBox(height: 16),
        _buildTemperatureCard(),
        const SizedBox(height: 16),
        // 快捷操作
        _buildQuickActions(),
        const SizedBox(height: 16),
        // 实时日志
        _buildLogPanel(),
      ],
    );
  }

  Widget _buildStatusCard(IconData icon, String label, String value, Color iconColor) {
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.caption),
              Text(value, style: AppTextStyles.h3),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTemperatureCard() {
    final waterTemp = _sensorValue('ds18b20_water_1', 'temperature_c') ??
        _sensorValue('ms5837_depth', 'temperature_c');
    final depth = _sensorValue('ms5837_depth', 'depth_m');
    final frontDistance = _sensorValue('ultrasonic_front_suction_mouth', 'distance_m');
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('环境水温', style: AppTextStyles.caption.copyWith(color: AppColors.primary)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(waterTemp?.toStringAsFixed(1) ?? '--', style: AppTextStyles.dataMedium.copyWith(color: AppColors.primary)),
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
        ],
      ),
    );
  }

  /// 从 RDK X5 遥测里读取某个传感器的标量值
  double? _sensorValue(String sensor, String key) {
    final data = _backendService.sensorData[sensor];
    if (data is Map && data['ok'] == true && data['values'] is Map) {
      final value = data['values'][key];
      if (value is num) return value.toDouble();
    }
    return null;
  }

  /// 运行状态文本：优先显示 RDK X5 链路状态
  String _runStatusText() {
    if (_backendService.rdkStatus['connected'] == true) {
      return 'RDK X5 已连接';
    }
    if (_backendService.pixhawkStatus['connected'] == true) {
      return 'Pixhawk 已连接';
    }
    if (_backendService.isConnected) {
      return '后端已连接';
    }
    return '未连接';
  }

  Color _runStatusColor() {
    if (_backendService.rdkStatus['connected'] == true ||
        _backendService.pixhawkStatus['connected'] == true ||
        _backendService.isConnected) {
      return AppColors.success;
    }
    return AppColors.error;
  }

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
                  // 测量模式切换
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
              _buildActionButtonWithCallback(Icons.vertical_align_top, '一键上浮', AppColors.warning, () => _backendService.ascend(speed: 1.0)),
              _buildActionButtonWithCallback(Icons.refresh, '坐标归零', AppColors.primary, () => _backendService.resetPosition()),
              _buildActionButtonWithCallback(Icons.wb_incandescent, _lightingOn ? '关闭补光' : '开启补光', AppColors.warning, () {
                setState(() => _lightingOn = !_lightingOn);
                _backendService.setLight(_lightingOn);
              }),
              _buildActionButtonWithCallback(Icons.photo_camera, '快照捕获', AppColors.success, () => _backendService.takeSnapshot()),
            ],
          ),
          const SizedBox(height: 16),
          // 紧急停止
          SizedBox(
            width: double.infinity,
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
                      Text('紧急停止', style: AppTextStyles.bodyMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text('STOP', style: AppTextStyles.caption.copyWith(color: Colors.white.withValues(alpha: 0.8))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 推进器动力
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('推进器动力', style: AppTextStyles.caption),
                  Text('65%', style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: 0.65,
                backgroundColor: AppColors.borderLight,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color) {
    return Material(
      color: AppColors.surfaceLight,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {},
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
              Text(label, style: AppTextStyles.caption),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtonWithCallback(IconData icon, String label, Color color, VoidCallback onTap) {
    return Material(
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
    );
  }

  Widget _buildLogPanel() {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          // 标题
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
          // 日志列表
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildLogItem('14:20:12', 'AI识别', '海参群落密度符合捕捞预期', '当前深度: 52.4m | 浊度: 1.2 NTU'),
                const SizedBox(height: 16),
                _buildLogItem('14:20:05', 'AI识别', '发现大型海参个体', '(坐标 12.5, 45.8)'),
                const SizedBox(height: 16),
                _buildLogItem('14:19:58', '系统', '云台转向电机响应正常', '', isSystem: true),
              ],
            ),
          ),
          // 查看更多
          InkWell(
            onTap: () {},
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.borderLight)),
              ),
              child: Text(
                '查看完整历史记录',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(String time, String tag, String title, String subtitle, {bool isSystem = false}) {
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
                color: isSystem ? AppColors.backgroundLightAlt : AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                tag,
                style: AppTextStyles.caption.copyWith(
                  color: isSystem ? AppColors.textSecondaryLight : AppColors.primary,
                ),
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
class _VideoSourceConfigDialog extends StatefulWidget {
  final RovBackendService backendService;

  const _VideoSourceConfigDialog({required this.backendService});

  @override
  State<_VideoSourceConfigDialog> createState() => _VideoSourceConfigDialogState();
}

class _VideoSourceConfigDialogState extends State<_VideoSourceConfigDialog> {
  late VideoSourceType _selectedType;
  final _wsHostController = TextEditingController();
  final _wsPortController = TextEditingController();
  final _localPathController = TextEditingController();
  final _rtspUrlController = TextEditingController();
  final _httpUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedType = widget.backendService.videoSourceType;
    _wsHostController.text = 'localhost';
    _wsPortController.text = '8765';
    _localPathController.text = widget.backendService.localVideoPath;
    _rtspUrlController.text = widget.backendService.rtspUrl;
    _httpUrlController.text = widget.backendService.httpStreamUrl;
  }

  @override
  void dispose() {
    _wsHostController.dispose();
    _wsPortController.dispose();
    _localPathController.dispose();
    _rtspUrlController.dispose();
    _httpUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('视频源配置'),
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 视频源类型选择
            const Text('选择视频源类型:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: VideoSourceType.values.map((type) {
                return ChoiceChip(
                  label: Text(_getTypeLabel(type)),
                  selected: _selectedType == type,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedType = type);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            // 配置表单
            _buildConfigForm(),
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

  String _getTypeLabel(VideoSourceType type) {
    switch (type) {
      case VideoSourceType.websocket:
        return 'WebSocket';
      case VideoSourceType.localFile:
        return '本地视频';
      case VideoSourceType.rtsp:
        return 'RTSP流';
      case VideoSourceType.httpStream:
        return 'HTTP图片流';
    }
  }

  Widget _buildConfigForm() {
    switch (_selectedType) {
      case VideoSourceType.websocket:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Python后端WebSocket服务器'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _wsHostController,
                    decoration: const InputDecoration(
                      labelText: '主机地址',
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
        );
      case VideoSourceType.localFile:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('本地视频文件路径（支持 mp4, avi 等格式）'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _localPathController,
                    decoration: const InputDecoration(
                      labelText: '文件路径',
                      hintText: 'C:/videos/underwater.mp4',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _selectLocalFile,
                  child: const Text('浏览'),
                ),
              ],
            ),
          ],
        );
      case VideoSourceType.rtsp:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('RTSP摄像头流地址'),
            const SizedBox(height: 8),
            TextField(
              controller: _rtspUrlController,
              decoration: const InputDecoration(
                labelText: 'RTSP URL',
                hintText: 'rtsp://192.168.1.100:554/stream1',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        );
      case VideoSourceType.httpStream:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('HTTP图片流地址（每次请求返回最新帧）'),
            const SizedBox(height: 8),
            TextField(
              controller: _httpUrlController,
              decoration: const InputDecoration(
                labelText: 'HTTP URL',
                hintText: 'http://192.168.1.100:8080/frame.jpg',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        );
    }
  }

  Future<void> _selectLocalFile() async {
    // 使用 file_picker 选择文件
    // 简化处理：这里只是设置文本框
    // 实际项目中应使用 FilePicker.platform.pickFiles()
  }

  void _saveAndClose() {
    widget.backendService.setVideoSourceType(_selectedType);
    
    switch (_selectedType) {
      case VideoSourceType.websocket:
        final host = _wsHostController.text.trim();
        final port = int.tryParse(_wsPortController.text) ?? 8765;
        widget.backendService.setServerAddress(host, port);
        break;
      case VideoSourceType.localFile:
        widget.backendService.setLocalVideoPath(_localPathController.text.trim());
        break;
      case VideoSourceType.rtsp:
        widget.backendService.setRtspUrl(_rtspUrlController.text.trim());
        break;
      case VideoSourceType.httpStream:
        widget.backendService.setHttpStreamUrl(_httpUrlController.text.trim());
        break;
    }

    Navigator.of(context).pop();
  }
}
