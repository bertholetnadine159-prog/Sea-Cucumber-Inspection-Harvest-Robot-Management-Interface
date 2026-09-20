/// 控制操作页面 - 桌面端（旧版 1cc31e5 视觉还原 + 真实数据绑定）
///
/// 功能：实时运行状态、辅助系统控制、方向控制、紧急制动
/// 设计稿对应：win/operate/screen.png
///
/// 视觉还原自旧版：三张状态卡（底部"实时读取中"状态行）、辅助系统卡 +
/// 提示卡左列、500×400 方向控制卡（按压亮起按钮 + HOVER 中心件 + 上浮/下潜
/// 右列）、急停大胶囊；全部样式按 STYLE_SPEC §8.2 逐条对齐。
///
/// Wave 2 真实化说明（契约§7，样式照抄、数据接真）：
/// - 状态卡数值：telemetryNotifier 真实绑定（无源显示 "--"），断链 StaleBadge；
///   数据新鲜时显示旧版"实时读取中 (±0.02)"状态行（真实状态驱动）；
/// - 右上"通信延迟"胶囊：真实 ≈链路时延（videoFrameNotifier.linkLatencySeconds，
///   无 sent_ts 时胶囊自动隐藏）；
/// - 机械臂/主泵/自动调平/全景扫描为后端无实现的空壳，不得复活；
///   保留真实命令：灯光（PWM）、吸捕抓取/释放（suction power 100/0）；
/// - 方向按钮接真实命令：按住推进（onTapDown 发令）、松开即停（onTapUp/
///   onTapCancel 停止），携带真实推进器动力 speed 参数；
/// - 旧版提示卡"水流较快已自动补偿"为虚构文案，改为真实操作协议说明；
/// - 紧急停止接真实 emergencyStop 命令。
library;

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/rov_backend_service.dart';
import '../../shared/utils/command_link.dart';
import '../../shared/widgets/motion_kit.dart';
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
  void initState() {
    super.initState();
    // 低频通知（命令回执等）仅触发本页 setState；高频数据走 notifier 通道
    _backendService.addListener(_onBackendUpdate);
  }

  @override
  void dispose() {
    _backendService.removeListener(_onBackendUpdate);
    super.dispose();
  }

  void _onBackendUpdate() {
    if (mounted) setState(() {});
  }

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

  /// 构建顶部标题区域（旧版"通信延迟"胶囊样式；数据为真实 ≈链路时延）
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
        // 右侧：真实 ≈链路时延（来自视频帧 sent_ts，无源不显示）
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
                    '通信延迟: ',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '≈${(latency * 1000).toStringAsFixed(0)}ms',
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
              // 动效工具箱：三卡错峰入场（仅首次挂载播放）
              child: StaggerIn(
                index: 0,
                child: _buildStatusCard(
                  title: '探测深度',
                  value: depth,
                  decimals: 2,
                  unit: 'm',
                  icon: Icons.waves,
                  iconBgColor: AppColors.primary.withValues(alpha: 0.1),
                  iconColor: AppColors.primary,
                  valueColor: AppColors.primary,
                  lastUpdated: lastUpdated,
                  isDark: isDark,
                ),
              ),
            ),
            const SizedBox(width: 24),
            // 机器温度（ds18b20_water_1 / ms5837_depth）
            Expanded(
              child: StaggerIn(
                index: 1,
                child: _buildStatusCard(
                  title: '机器温度',
                  value: temperature,
                  decimals: 1,
                  unit: '°C',
                  icon: Icons.thermostat,
                  iconBgColor: Colors.transparent,
                  iconColor: isDark ? AppColors.textSecondaryDark : AppColors.textHint,
                  valueColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                  lastUpdated: lastUpdated,
                  isDark: isDark,
                ),
              ),
            ),
            const SizedBox(width: 24),
            // 电池电压（pixhawk.battery_v；原"漏水检测"无真实传感器，已删除）
            Expanded(
              child: StaggerIn(
                index: 2,
                child: _buildStatusCard(
                  title: '电池电压',
                  value: batteryV,
                  decimals: 2,
                  unit: 'V',
                  icon: Icons.battery_charging_full,
                  iconBgColor: Colors.transparent,
                  iconColor: AppColors.success,
                  valueColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                  lastUpdated: lastUpdated,
                  isDark: isDark,
                ),
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

  /// 构建单个状态卡片（旧版样式）
  ///
  /// [value] 为 null 时显示 "--"（契约§7：无源不显示假值）；
  /// 底部状态行：数据新鲜时为旧版"实时读取中 (±0.02)"注记（真实状态驱动），
  /// 断链时由 StaleBadge 提示"信号丢失"并冻结最后真实值。
  Widget _buildStatusCard({
    required String title,
    required double? value,
    required int decimals,
    required String unit,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required Color valueColor,
    required bool isDark,
    DateTime? lastUpdated,
    bool isText = false,
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
          // 数值（无源 "--"；动效工具箱：真实遥测滚动插值，断链时半透明冻结）
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              AnimatedTelemetryValue(
                value: value ?? double.nan,
                decimals: decimals,
                invalidText: '--',
                style: TextStyle(
                  fontSize: isText ? 32 : 36,
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
          const SizedBox(height: 16),
          // 底部状态行：旧版注记样式，仅数据新鲜时显示；断链时 StaleBadge
          Row(
            children: [
              if (stale)
                StaleBadge(lastUpdated: lastUpdated)
              else ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF87171),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '实时读取中 (±0.02)',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 构建主要内容区域（旧版：左列 辅助系统卡 + 24 + 提示卡；右 方向控制卡）
  Widget _buildMainContent(bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：辅助系统
        Expanded(
          flex: 4,
          child: Column(
            children: [
              _buildAuxiliarySystemCard(isDark),
              const SizedBox(height: 24),
              _buildHintCard(isDark),
            ],
          ),
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

  /// 构建辅助系统卡片（旧版卡片样式；仅保留真实生效命令）
  ///
  /// 机械臂/主泵/自动调平/全景扫描为后端无实现的空壳（仅弹 SnackBar 假反馈），
  /// 按契约§7-③不得复活；保留真实命令：灯光（PWM）、吸捕抓取/释放。
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
            '灯光与吸捕',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textHint,
            ),
          ),
          const SizedBox(height: 32),
          // 灯光开关（旧版切换钮样式；真实 PWM 命令 setLight）
          _buildToggleControlButton(
            Icons.light_mode,
            '灯光：${_lightOn ? '已开启' : '已关闭'}',
            _lightOn,
            isDark,
            () {
              setState(() => _lightOn = !_lightOn);
              _backendService.setLight(_lightOn);
              _showControlFeedback('已发送灯光${_lightOn ? "开启" : "关闭"}命令');
            },
          ),
          const SizedBox(height: 24),
          // 吸捕抓取/释放（真实 suction 命令：grab=100 / release=0）
          Text(
            '吸捕控制',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildToggleControlButton(
                  Icons.download,
                  '抓取（吸力 100%）',
                  false,
                  isDark,
                  () {
                    _backendService.grab();
                    _showControlFeedback('已发送吸捕抓取命令，吸力 100%');
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildToggleControlButton(
                  Icons.upload,
                  '释放（吸力 0%）',
                  false,
                  isDark,
                  () {
                    _backendService.release();
                    _showControlFeedback('已发送吸捕释放命令，吸力 0%');
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 推进器动力（真实参数：方向命令携带的 speed 值）
          Row(
            children: [
              Text(
                '推进器动力',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 6,
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: AppColors.primary.withValues(alpha: 0.2),
                    thumbColor: AppColors.primary,
                    overlayColor: AppColors.primary.withValues(alpha: 0.1),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
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
              ),
              Text(
                '${(_thrusterPower * 100).round()}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
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

  /// 构建可切换状态的控制按钮（旧版 `_buildToggleControlButton` 样式：
  /// 激活 primary 10% 底 + primary 描边 + 文字转主色加粗，未激活透明底描边）
  Widget _buildToggleControlButton(
    IconData icon,
    String label,
    bool isActive,
    bool isDark,
    VoidCallback onTap,
  ) {
    // 动效工具箱：按压缩放反馈（点击仍由内部 InkWell 处理）
    return PressableScale(
      child: Material(
        color: isActive ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: isDark ? AppColors.surfaceDark : const Color(0xFFF8FAFC),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isActive
                      ? AppColors.primary
                      : (isDark ? AppColors.borderDark : AppColors.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isActive
                      ? AppColors.primary
                      : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondary),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: isActive
                          ? AppColors.primary
                          : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimary),
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建提示卡（旧版"智能纠偏卡"视觉：primary 5% 底 + primary 20% 描边
  /// + info 图标；旧版虚构文案已换成真实操作协议说明）
  Widget _buildHintCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info, color: AppColors.primary, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '操作说明',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '方向按钮按住推进、松开即停；'
                  '当前推进器动力 ${(_thrusterPower * 100).round()}%。',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建方向控制卡片（旧版 500×400 布局：按压亮起方向钮 + HOVER 中心件 +
  /// 右列上浮/下潜；全部接真实命令：按住推进、松开即停）
  Widget _buildDirectionControlCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(48),
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
            child: SizedBox(
              width: 500,
              height: 400,
              child: Row(
                children: [
                  // 左侧主控制区域
                  Expanded(
                    flex: 3,
                    child: Stack(
                      children: [
                        // 前进按钮（顶部中央）
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: _buildDirectionButton(
                              icon: Icons.arrow_upward,
                              label: '前进',
                              isPrimary: true,
                              isDark: isDark,
                              onPress: () =>
                                  _backendService.forward(speed: _thrusterPower),
                            ),
                          ),
                        ),
                        // 左转按钮（左侧中央）
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: _buildDirectionButton(
                              icon: Icons.arrow_back,
                              label: '左转',
                              isDark: isDark,
                              onPress: () =>
                                  _backendService.turnLeft(speed: _thrusterPower),
                            ),
                          ),
                        ),
                        // 右转按钮（右侧中央）
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: _buildDirectionButton(
                              icon: Icons.arrow_forward,
                              label: '右转',
                              isDark: isDark,
                              onPress: () =>
                                  _backendService.turnRight(speed: _thrusterPower),
                            ),
                          ),
                        ),
                        // 后退按钮（底部中央）
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: _buildDirectionButton(
                              icon: Icons.arrow_downward,
                              label: '后退',
                              isDark: isDark,
                              onPress: () =>
                                  _backendService.backward(speed: _thrusterPower),
                            ),
                          ),
                        ),
                        // 中心控制器（点击 = 停止）
                        Center(
                          child: _buildCenterControl(isDark),
                        ),
                      ],
                    ),
                  ),
                  // 右侧上浮/下潜区域
                  SizedBox(
                    width: 80,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildSquareButton(
                          icon: Icons.expand_less,
                          label: '上浮',
                          isDark: isDark,
                          onPress: () => _backendService.ascend(speed: _thrusterPower),
                        ),
                        const SizedBox(height: 40),
                        _buildSquareButton(
                          icon: Icons.expand_more,
                          label: '下潜',
                          isDark: isDark,
                          onPress: () => _backendService.descend(speed: _thrusterPower),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '按住推进、松开即停',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建方向按钮（旧版按压亮起样式；真实命令：onTapDown 发令、松开即停）
  Widget _buildDirectionButton({
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onPress,
    bool isPrimary = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PressableButton(
          isPrimary: isPrimary,
          icon: icon,
          onPress: onPress,
          onRelease: () => _backendService.stop(),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textHint,
          ),
        ),
      ],
    );
  }

  /// 构建方形控制按钮（旧版按压亮起样式；真实命令：按住上浮/下潜、松开即停）
  Widget _buildSquareButton({
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onPress,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PressableSquareButton(
          icon: icon,
          onPress: onPress,
          onRelease: () => _backendService.stop(),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textHint,
          ),
        ),
      ],
    );
  }

  /// 构建中心控制器（旧版 HOVER 视觉：RadialGradient 外圈 + primary 内圆
  /// + 光晕 + 白点 + HOVER 徽标；点击 = 发送停止命令）
  Widget _buildCenterControl(bool isDark) {
    return GestureDetector(
      onTap: () {
        _backendService.stop();
        _showControlFeedback('已停止全部推进器');
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.1),
                  Colors.transparent,
                ],
              ),
              border: Border.all(
                  color: (isDark ? AppColors.borderDark : AppColors.border)
                      .withValues(alpha: 0.5)),
            ),
            child: Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'HOVER',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建紧急制动系统（旧版急停大胶囊样式；真实 emergencyStop 命令 + 确认对话框）
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
          // 描述（不虚构"切断动力电池/释放气囊"）
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
            // 动效工具箱：按压缩放反馈（确认对话框流程不变）
            child: PressableScale(
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
    // 急停闭环（与悬浮急停球/主控页同一口径，EmergencyStopFlow）：
    // 快路径经主通道下发后等待后端 ack，「已急停」只在 ack.success=true 后
    // 显示；被后端拒绝（forbidden/unauthorized）时全局红色常驻告警直到恢复。
    final report = await EmergencyStopFlow.fire();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(report.text),
        backgroundColor: report.isError ? AppColors.error : AppColors.success,
      ),
    );
  }
}

/// 可按压的圆形方向按钮（旧版样式：按下瞬间底变 primary、图标变白、
/// 主色光晕；真实命令：onTapDown 发令，onTapUp/onTapCancel 停止）
class _PressableButton extends StatefulWidget {
  final bool isPrimary;
  final IconData icon;
  final VoidCallback onPress;
  final VoidCallback onRelease;

  const _PressableButton({
    this.isPrimary = false,
    required this.icon,
    required this.onPress,
    required this.onRelease,
  });

  @override
  State<_PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<_PressableButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    // 按下时显示蓝色，否则显示白色
    final bool showActive = _isPressed;

    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
        widget.onPress();
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onRelease();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
        widget.onRelease();
      },
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: showActive ? AppColors.primary : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: showActive ? AppColors.primary : AppColors.border,
            width: 1.5,
          ),
          boxShadow: showActive
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Icon(
          widget.icon,
          size: 28,
          color: showActive
              ? Colors.white
              : (widget.isPrimary ? AppColors.primary : AppColors.textSecondary),
        ),
      ),
    );
  }
}

/// 可按压的方形按钮（旧版样式：上浮/下潜按钮，按下时亮起蓝色）
class _PressableSquareButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPress;
  final VoidCallback onRelease;

  const _PressableSquareButton({
    required this.icon,
    required this.onPress,
    required this.onRelease,
  });

  @override
  State<_PressableSquareButton> createState() => _PressableSquareButtonState();
}

class _PressableSquareButtonState extends State<_PressableSquareButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool showActive = _isPressed;

    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
        widget.onPress();
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onRelease();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
        widget.onRelease();
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: showActive ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: showActive ? AppColors.primary : AppColors.border,
            width: 1.5,
          ),
          boxShadow: showActive
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Icon(
          widget.icon,
          size: 28,
          color: showActive ? Colors.white : AppColors.textSecondary,
        ),
      ),
    );
  }
}
