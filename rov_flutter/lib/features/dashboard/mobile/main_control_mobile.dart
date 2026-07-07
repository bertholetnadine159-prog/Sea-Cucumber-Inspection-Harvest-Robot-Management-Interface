/// 主控界面 - 移动端
/// 
/// 功能：视频监控、设备控制、方向控制、状态显示、快捷操作、实时日志
/// 设计稿对应：app/main_control/screen.png
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/rov_backend_service.dart';

/// 移动端主控界面
class MainControlMobile extends StatefulWidget {
  const MainControlMobile({super.key});

  @override
  State<MainControlMobile> createState() => _MainControlMobileState();
}

class _MainControlMobileState extends State<MainControlMobile> {
  // 设备开关状态
  bool _lightingOn = true;
  bool _sonarOn = true;
  bool _laserOn = false;
  bool _autoNavOn = false;
  
  // 后端服务
  final _backendService = RovBackendService();
  
  // 测量模式
  bool _measureMode = false;
  
  // 推进器动力
  double _thrusterPower = 0.65;
  
  // 状态定时器
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
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
                  _buildLogSection(),
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
                  // 标题行
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
                          Icon(Icons.notifications_outlined, color: Colors.white.withOpacity(0.9)),
                          const SizedBox(width: 16),
                          const CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.white24,
                            child: Icon(Icons.person, color: Colors.white, size: 18),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 信息行
                  Row(
                    children: [
                      _buildInfoChip('ROV-01'),
                      const SizedBox(width: 8),
                      _buildInfoChip('全海区'),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '⬛ -45dBm   ⚡ 120W',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ),
                      ),
                    ],
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

  /// 构建信息标签
  Widget _buildInfoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.white,
        ),
      ),
    );
  }

  /// 构建视频监控区域
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
                  painter: MobileDetectionPainter(
                    detections: _backendService.detections,
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
            // 左上角录制标记
            Positioned(
              top: 12,
              left: 12,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _backendService.isConnected ? AppColors.success : AppColors.error,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_backendService.isConnected ? Icons.fiber_manual_record : Icons.link_off, size: 10, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(_backendService.isConnected ? 'LIVE' : '离线', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
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
                    child: const Text('CAM-01', style: TextStyle(fontSize: 10, color: Colors.white)),
                  ),
                ],
              ),
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
                      color: AppColors.warning.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('测量模式', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
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
                      color: AppColors.success.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '距离: ${_backendService.measuredDistance!.toStringAsFixed(2)} cm',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            // 右上角分辨率信息
            Positioned(
              top: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${_backendService.frameRate} fps', style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.8))),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('⏱ 45ms', style: TextStyle(fontSize: 9, color: Colors.white)),
                  ),
                ],
              ),
            ),
            // 左下角坐标
            Positioned(
              bottom: 12,
              left: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('COORDINATES', style: TextStyle(fontSize: 8, color: Colors.white.withOpacity(0.6))),
                  const Text('N  38°55\'', style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)),
                  const Text('E 121°38\'', style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            // 中间深度信息
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Column(
                  children: [
                    Text('DEPTH', style: TextStyle(fontSize: 8, color: Colors.white.withOpacity(0.6))),
                    const Text('42.5', style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('m', style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.8))),
                  ],
                ),
              ),
            ),
            // 右下角时间
            Positioned(
              bottom: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_getCurrentTime(), style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(_getCurrentDate(), style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.7))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 获取当前时间
  String _getCurrentTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  /// 获取当前日期
  String _getCurrentDate() {
    final now = DateTime.now();
    return '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
  }

  /// 构建视频帧
  Widget _buildVideoFrame() {
    final frame = _backendService.currentFrame;
    if (frame != null) {
      return Image.memory(
        frame,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.blue.shade800.withOpacity(0.6),
            Colors.blue.shade900.withOpacity(0.8),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _backendService.isConnected ? Icons.videocam_off : Icons.link_off,
              size: 40,
              color: Colors.white30,
            ),
            const SizedBox(height: 8),
            Text(
              _backendService.isConnected ? '等待视频...' : _backendService.connectionStatus,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 视频源选择
                OutlinedButton.icon(
                  onPressed: _showVideoSourceSheet,
                  icon: const Icon(Icons.settings_input_antenna, size: 16),
                  label: Text(_getVideoSourceLabel(), style: const TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white30),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
                const SizedBox(width: 8),
                // 连接按钮
                ElevatedButton(
                  onPressed: () async {
                    if (_backendService.isConnected) {
                      await _backendService.disconnect();
                    } else {
                      await _backendService.connectVideoSource();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _backendService.isConnected ? AppColors.error : AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: Text(
                    _backendService.isConnected ? '断开' : '连接',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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

  /// 显示视频源选择底部弹窗
  void _showVideoSourceSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _VideoSourceBottomSheet(backendService: _backendService),
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
  Widget _buildDeviceControls() {
    return Row(
      children: [
        Expanded(child: _buildDeviceSwitch('照明系统', Icons.lightbulb_outline, _lightingOn, (v) {
          setState(() => _lightingOn = v);
          _backendService.setLight(v);
        })),
        const SizedBox(width: 12),
        Expanded(child: _buildDeviceSwitch('声呐雷达', Icons.radar, _sonarOn, (v) {
          setState(() => _sonarOn = v);
          _backendService.setSonar(v);
        })),
      ],
    );
  }

  /// 构建单个设备开关
  Widget _buildDeviceSwitch(String label, IconData icon, bool value, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
              Switch(
                value: value,
                onChanged: onChanged,
                activeColor: AppColors.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Icon(icon, size: 28, color: value ? AppColors.primary : AppColors.textHint),
        ],
      ),
    );
  }

  /// 构建方向控制面板
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
          // 上浮按钮 (右侧)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 80),
              _buildDirectionButton(Icons.arrow_upward, '前进', () => _backendService.forward(speed: _thrusterPower), isPrimary: true),
              const SizedBox(width: 40),
              Column(
                children: [
                  _buildSmallButton(Icons.keyboard_arrow_up, '上浮', () => _backendService.ascend(speed: _thrusterPower)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 左中右
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildDirectionButton(Icons.arrow_back, '左转', () => _backendService.turnLeft(speed: _thrusterPower)),
              const SizedBox(width: 24),
              _buildCenterControl(),
              const SizedBox(width: 24),
              _buildDirectionButton(Icons.arrow_forward, '右转', () => _backendService.turnRight(speed: _thrusterPower)),
            ],
          ),
          const SizedBox(height: 16),
          // 下方按钮组
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSmallButton(Icons.rotate_left, '左倾', () {}),
              _buildSmallButton(Icons.rotate_right, '右倾', () {}),
              const SizedBox(width: 40),
              _buildDirectionButton(Icons.arrow_downward, '后退', () => _backendService.backward(speed: _thrusterPower)),
              const SizedBox(width: 40),
              Column(
                children: [
                  _buildSmallButton(Icons.keyboard_arrow_down, '下潜', () => _backendService.descend(speed: _thrusterPower)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建方向按钮
  Widget _buildDirectionButton(IconData icon, String label, VoidCallback onPressed, {bool isPrimary = false}) {
    return Column(
      children: [
        GestureDetector(
          onTapDown: (_) => onPressed(),
          onTapUp: (_) => _backendService.stop(),
          onTapCancel: () => _backendService.stop(),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isPrimary ? AppColors.primary : Colors.white,
              shape: BoxShape.circle,
              border: isPrimary ? null : Border.all(color: AppColors.border),
              boxShadow: isPrimary ? [
                BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4)),
              ] : null,
            ),
            child: Icon(icon, color: isPrimary ? Colors.white : AppColors.textPrimary),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
      ],
    );
  }

  /// 构建小按钮
  Widget _buildSmallButton(IconData icon, String label, VoidCallback onPressed) {
    return Column(
      children: [
        GestureDetector(
          onTapDown: (_) => onPressed(),
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
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textHint)),
      ],
    );
  }

  /// 构建中心控制
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
            BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 16),
          ],
        ),
        child: const Icon(Icons.gamepad, color: Colors.white, size: 24),
      ),
    );
  }

  /// 构建状态卡片组
  Widget _buildStatusCards() {
    return Column(
      children: [
        // 报警提醒
        _buildStatusCard(
          icon: Icons.error_outline,
          iconColor: AppColors.error,
          iconBgColor: AppColors.error.withOpacity(0.1),
          title: '报警提醒',
          value: '无异常',
          valueColor: AppColors.textPrimary,
        ),
        const SizedBox(height: 12),
        // 运行状态
        _buildStatusCard(
          icon: Icons.check_circle_outline,
          iconColor: AppColors.success,
          iconBgColor: AppColors.success.withOpacity(0.1),
          title: '运行状态',
          value: '正常',
          valueColor: AppColors.textPrimary,
        ),
        const SizedBox(height: 12),
        // 环境水温 (特殊蓝色卡片)
        Container(
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
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.thermostat, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('环境水温', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8))),
                  const Text('22.5°C', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
            ],
          ),
        ),
      ],
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: valueColor)),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建快捷操作
  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('快捷操作', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Row(
              children: [
                // 测量模式切换
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _measureMode = !_measureMode;
                      if (!_measureMode) {
                        _backendService.clearMeasurePoints();
                      }
                    });
                  },
                  child: Icon(Icons.straighten, size: 20, color: _measureMode ? AppColors.warning : AppColors.textHint),
                ),
                const SizedBox(width: 8),
                Icon(Icons.bolt, size: 20, color: AppColors.primary),
              ],
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
            _buildQuickActionButton(Icons.arrow_upward, '一键上浮', () => _backendService.ascend(speed: 1.0)),
            _buildQuickActionButton(Icons.gps_fixed, '坐标归零', () => _backendService.resetPosition()),
            _buildQuickActionButton(Icons.flashlight_on_outlined, _lightingOn ? '关闭补光' : '开启补光', () {
              setState(() => _lightingOn = !_lightingOn);
              _backendService.setLight(_lightingOn);
            }),
            _buildQuickActionButton(Icons.camera_alt, '快照捕获', () => _backendService.takeSnapshot()),
          ],
        ),
      ],
    );
  }

  /// 构建快捷操作按钮
  Widget _buildQuickActionButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
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

  /// 构建急停按钮
  Widget _buildEmergencyStop() {
    return GestureDetector(
      onTap: () => _backendService.emergencyStop(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.1),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppColors.error.withOpacity(0.3)),
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
            Text(
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

  /// 构建实时检测日志
  Widget _buildLogSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.receipt_long, size: 18, color: AppColors.textSecondary),
                SizedBox(width: 8),
                Text('实时检测日志', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            Text('实时流', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
          ],
        ),
        const SizedBox(height: 16),
        // 日志项
        _buildLogItem('14:20:12', 'AI分析', '海参群落密度符合捕捞预期', '当前深度: 52.4m | 浊度: 1.2 NTU'),
        const Divider(height: 24),
        _buildLogItem('14:20:05', 'AI识别', '发现大型海参个体', '(坐标 12.5, 45.8)'),
      ],
    );
  }

  /// 构建日志项
  Widget _buildLogItem(String time, String tag, String title, String detail) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(time, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(tag, style: const TextStyle(fontSize: 10, color: AppColors.primary)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(detail, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
            ],
          ),
        ),
      ],
    );
  }
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
      ..color = Colors.greenAccent.withOpacity(0.15);

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
      canvas.drawRect(labelRect, Paint()..color = Colors.greenAccent.withOpacity(0.8));
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
class _VideoSourceBottomSheet extends StatefulWidget {
  final RovBackendService backendService;

  const _VideoSourceBottomSheet({required this.backendService});

  @override
  State<_VideoSourceBottomSheet> createState() => _VideoSourceBottomSheetState();
}

class _VideoSourceBottomSheetState extends State<_VideoSourceBottomSheet> {
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
              const Text('视频源配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 视频源类型选择
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: VideoSourceType.values.map((type) {
                final isSelected = _selectedType == type;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_getTypeLabel(type)),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedType = type);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),
          // 配置表单
          _buildConfigForm(),
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
            const Text('Python后端服务器', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _wsHostController,
                    decoration: const InputDecoration(
                      labelText: '主机',
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
          ],
        );
      case VideoSourceType.localFile:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('本地视频文件', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: _localPathController,
              decoration: const InputDecoration(
                labelText: '文件路径',
                hintText: '/storage/emulated/0/video.mp4',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        );
      case VideoSourceType.rtsp:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('RTSP摄像头地址', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: _rtspUrlController,
              decoration: const InputDecoration(
                labelText: 'RTSP URL',
                hintText: 'rtsp://192.168.1.100:554/stream',
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
            const Text('HTTP图片流地址', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
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
