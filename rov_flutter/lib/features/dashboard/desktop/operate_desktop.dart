/// 控制操作页面 - 桌面端
///
/// 功能：实时运行状态、辅助系统控制、方向控制、紧急制动
/// 设计稿对应：win/operate/screen.png
///
/// Wave 2 真实化说明（契约§7 数据真实回传）：
/// - 兜底假深度 5.2m / 假温度 35°C / 假漏水状态"正常"已删除，
///   全部改为 telemetryNotifier 真实绑定（无源显示 "--"）+ 每卡 StaleBadge；
/// - 假"通信延迟 12ms"改为真实 ≈链路时延（videoFrameNotifier.linkLatencySeconds，
///   无 sent_ts 时不显示）；
/// - 机械臂/主泵/自动调平/全景扫描/补光强度滑块/智能纠偏提示均为后端无实现的
///   空壳（仅弹 SnackBar 假反馈），已删除；保留真实命令：灯光（PWM）、
///   吸捕抓取/释放（suction power 100/0）；
/// - 方向键盘原为纯 UI 假按钮（未发送任何命令），替换为共享 ControlPad 并接真实命令；
/// - 紧急停止接真实 emergencyStop 命令，文案不再虚构"切断动力电池/释放气囊"。
library;

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/rov_backend_service.dart';
import '../../shared/widgets/control_pad.dart';
import '../../shared/widgets/stale_badge.dart';
import '../../shared/widgets/confirm_dialog.dart';

/// 控制操作页面桌面端
class OperateDesktop extends StatefulWidget {
  const OperateDesktop({super.key});

  @override
  State<OperateDesktop> createState() => _OperateDesktopState();
}

class _OperateDesktopState extends State<OperateDesktop> {
  // 灯光开关状态（真实 PWM 命令：setLight）
  bool _lightOn = false;

  // 推进器动力（方向命令携带的真实 speed 参数，滑块可调）
  double _thrusterPower = 0.65;

  // 后端服务（RDK X5 遥测）
  final _backendService = RovBackendService();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部标题栏
            _buildHeaderSection(isDark),
            const SizedBox(height: 24),

            // 状态卡片
            _buildStatusCards(isDark),
            const SizedBox(height: 24),

            // 主要内容区域（辅助系统 + 方向控制）
            _buildMainContent(isDark),
            const SizedBox(height: 48),

            // 紧急制动系统
            _buildEmergencyStop(isDark),
          ],
        ),
      ),
    );
  }

  /// 构建顶部标题区域（通信延迟改为真实 ≈链路时延，无 sent_ts 时不显示）
  Widget _buildHeaderSection(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 左侧标题
        Row(
          children: [
            const Icon(Icons.bolt, color: AppColors.primary, size: 24),
            const SizedBox(width: 12),
            Text(
              '实时运行状态',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              ),
            ),
          ],
        ),
        // 右侧：真实 ≈链路时延（来自视频帧 sent_ts）
        ValueListenableBuilder<VideoFrame?>(
          valueListenable: _backendService.videoFrameNotifier,
          builder: (context, frame, _) {
            final latency = frame?.linkLatencySeconds;
            if (latency == null) return const SizedBox.shrink();
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '≈链路时延: ',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '${(latency * 1000).toStringAsFixed(0)}ms',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  /// 构建状态卡片（真实 telemetryNotifier 绑定，无源 "--"，断链 StaleBadge）
  Widget _buildStatusCards(bool isDark) {
    return ValueListenableBuilder<TelemetrySnapshot?>(
      valueListenable: _backendService.telemetryNotifier,
      builder: (context, telemetry, _) {
        final lastUpdated = telemetry?.lastUpdated;
        final depth = _sensorValueFrom(telemetry, 'ms5837_depth', 'depth_m');
        final temperature = _sensorValueFrom(telemetry, 'ds18b20_water_1', 'temperature_c') ??
            _sensorValueFrom(telemetry, 'ms5837_depth', 'temperature_c');
        final batteryV = (telemetry?.pixhawk['battery_v'] as num?)?.toDouble();
        return Row(
          children: [
            // 探测深度（ms5837_depth.depth_m）
            Expanded(
              child: _buildStatusCard(
                title: '探测深度',
                value: depth?.toStringAsFixed(2),
                unit: 'm',
                icon: Icons.waves,
                iconBgColor: AppColors.primary.withValues(alpha: 0.1),
                iconColor: AppColors.primary,
                valueColor: AppColors.primary,
                lastUpdated: lastUpdated,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 24),
            // 机器温度（ds18b20_water_1 / ms5837_depth）
            Expanded(
              child: _buildStatusCard(
                title: '机器温度',
                value: temperature?.toStringAsFixed(1),
                unit: '°C',
                icon: Icons.thermostat,
                iconBgColor: Colors.transparent,
                iconColor: isDark ? AppColors.textSecondaryDark : AppColors.textHint,
                valueColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                lastUpdated: lastUpdated,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 24),
            // 电池电压（pixhawk.battery_v；原"漏水检测"无真实传感器，已删除）
            Expanded(
              child: _buildStatusCard(
                title: '电池电压',
                value: batteryV?.toStringAsFixed(2),
                unit: 'V',
                icon: Icons.battery_charging_full,
                iconBgColor: Colors.transparent,
                iconColor: AppColors.success,
                valueColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                lastUpdated: lastUpdated,
                isDark: isDark,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 从遥测快照读取某个传感器的标量值（无源返回 null，禁止合成兜底值）
  double? _sensorValueFrom(TelemetrySnapshot? telemetry, String sensor, String key) {
    final data = telemetry?.sensors[sensor];
    if (data is Map && data['ok'] == true && data['values'] is Map) {
      final value = data['values'][key];
      if (value is num) return value.toDouble();
    }
    return null;
  }

  /// 构建单个状态卡片
  ///
  /// [value] 为 null 时显示 "--"（契约§7：无源不显示假值）；
  /// 断链时由 StaleBadge 提示"信号丢失"并冻结最后真实值。
  Widget _buildStatusCard({
    required String title,
    required String? value,
    required String unit,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required Color valueColor,
    required bool isDark,
    DateTime? lastUpdated,
  }) {
    final stale = StaleBadge.isStale(lastUpdated);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: stale ? AppColors.warning.withValues(alpha: 0.5) : AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题和图标
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                  ),
                ),
              ),
              Container(
                padding: iconBgColor != Colors.transparent
                    ? const EdgeInsets.all(6)
                    : EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 数值（无源 "--"）
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value ?? '--',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: valueColor.withValues(alpha: stale ? 0.55 : 1.0),
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 20,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // 断链徽标（数据新鲜时自动消失；原假"实时读取中 (±0.02)"已删除）
          Align(
            alignment: Alignment.centerLeft,
            child: StaleBadge(lastUpdated: lastUpdated),
          ),
        ],
      ),
    );
  }

  /// 构建主要内容区域
  Widget _buildMainContent(bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：辅助系统
        Expanded(
          flex: 4,
          child: _buildAuxiliarySystemCard(isDark),
        ),
        const SizedBox(width: 24),
        // 右侧：方向控制
        Expanded(
          flex: 8,
          child: _buildDirectionControlCard(isDark),
        ),
      ],
    );
  }

  /// 构建辅助系统卡片
  ///
  /// 仅保留真实生效命令：灯光（PWM）、吸捕抓取/释放（suction power 100/0）。
  /// 机械臂/主泵/自动调平/全景扫描/补光强度滑块为后端无实现的空壳，已删除。
  Widget _buildAuxiliarySystemCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.borderDark : AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Text(
            '辅助系统',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '灯光与吸捕（仅展示后端真实执行的命令）',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textHint,
            ),
          ),
          const SizedBox(height: 24),
          // 灯光开关（真实 PWM 命令）
          _buildLightToggle(isDark),
          const SizedBox(height: 16),
          // 吸捕抓取/释放（真实 suction 命令：grab=100 / release=0）
          Text(
            '吸捕控制',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSuctionButton(
                  icon: Icons.download,
                  label: '抓取（吸力 100%）',
                  isDark: isDark,
                  onTap: () {
                    _backendService.grab();
                    _showControlFeedback('已发送吸捕抓取命令（吸力 100%）');
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSuctionButton(
                  icon: Icons.upload,
                  label: '释放（吸力 0%）',
                  isDark: isDark,
                  onTap: () {
                    _backendService.release();
                    _showControlFeedback('已发送吸捕释放命令（吸力 0%）');
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '机械臂/主泵/自动调平/全景扫描后端无实现，已移除空壳开关',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }

  /// 灯光开关（真实 PWM 命令 setLight）
  Widget _buildLightToggle(bool isDark) {
    final active = _lightOn;
    return Material(
      color: active ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          setState(() => _lightOn = !_lightOn);
          _backendService.setLight(_lightOn);
          _showControlFeedback('已发送灯光${_lightOn ? "开启" : "关闭"}命令');
        },
        borderRadius: BorderRadius.circular(12),
        hoverColor: isDark ? AppColors.surfaceDark : const Color(0xFFF8FAFC),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: active ? AppColors.primary : (isDark ? AppColors.borderDark : AppColors.border)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.light_mode,
                size: 18,
                color: active ? AppColors.primary : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '灯光${active ? '（已发送开启）' : '（已发送关闭）'}',
                  style: TextStyle(
                    fontSize: 14,
                    color: active ? AppColors.primary : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimary),
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              Switch(
                value: active,
                onChanged: (v) {
                  setState(() => _lightOn = v);
                  _backendService.setLight(v);
                  _showControlFeedback('已发送灯光${v ? "开启" : "关闭"}命令');
                },
                activeColor: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 吸捕按钮
  Widget _buildSuctionButton({
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: isDark ? AppColors.surfaceDark : const Color(0xFFF8FAFC),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? AppColors.borderDark : AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示控制反馈（仅用于真实命令的发送回执提示）
  void _showControlFeedback(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 构建方向控制卡片（共享 ControlPad，接真实命令：按住推进、松开即停）
  Widget _buildDirectionControlCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.borderDark : AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Center(
            child: ControlPad(
              buttonSize: 64,
              spacing: 10,
              onPress: _sendDirection,
              onRelease: (_) => _backendService.stop(),
              onStop: () => _backendService.stop(),
            ),
          ),
          const SizedBox(height: 16),
          // 推进器动力（真实参数：方向命令携带的 speed 值）
          SizedBox(
            width: 320,
            child: Row(
              children: [
                Text(
                  '推进器动力',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                  ),
                ),
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
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '按住推进、松开即停（命令实时下发至 RDK）',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }

  /// 方向命令分发（携带真实推进器动力参数）
  void _sendDirection(ControlDirection dir) {
    final speed = _thrusterPower;
    switch (dir) {
      case ControlDirection.forward:
        _backendService.forward(speed: speed);
      case ControlDirection.backward:
        _backendService.backward(speed: speed);
      case ControlDirection.left:
        _backendService.turnLeft(speed: speed);
      case ControlDirection.right:
        _backendService.turnRight(speed: speed);
      case ControlDirection.up:
        _backendService.ascend(speed: speed);
      case ControlDirection.down:
        _backendService.descend(speed: speed);
    }
  }

  /// 构建紧急制动系统（真实 emergencyStop 命令 + 确认对话框）
  Widget _buildEmergencyStop(bool isDark) {
    return Center(
      child: Column(
        children: [
          // 标题
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 16, color: AppColors.error),
              SizedBox(width: 8),
              Text(
                '紧急制动系统',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 描述（不再虚构"切断动力电池/释放气囊"）
          Text(
            '按下后立即向 ROV 下发紧急停止命令，停止全部推进器',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textHint,
            ),
          ),
          const SizedBox(height: 24),
          // 紧急停止按钮
          Material(
            color: AppColors.error,
            borderRadius: BorderRadius.circular(30),
            elevation: 8,
            shadowColor: AppColors.error.withValues(alpha: 0.3),
            child: InkWell(
              onTap: _showEmergencyStopDialog,
              borderRadius: BorderRadius.circular(30),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 80,
                  vertical: 16,
                ),
                child: const Text(
                  '紧急停止 (STOP)',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示紧急停止确认对话框（确认后发送真实命令）
  Future<void> _showEmergencyStopDialog() async {
    final ok = await ConfirmDialog.show(
      context,
      title: '紧急停止确认',
      message: '确定要执行紧急停止吗？将立即停止全部推进器。',
      confirmText: '确认停止',
    );
    if (!ok) return;
    if (!mounted) return;
    try {
      _backendService.emergencyStop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('紧急停止命令已发送'),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (e) {
      // 命令发送失败必须提示，不允许静默吞掉
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('紧急停止命令发送失败：$e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}
