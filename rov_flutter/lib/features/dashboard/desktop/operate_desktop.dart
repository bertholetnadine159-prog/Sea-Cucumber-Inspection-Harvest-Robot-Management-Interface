/// 控制操作页面 - 桌面端
/// 
/// 功能：实时运行状态、辅助系统控制、方向控制、紧急制动
/// 设计稿对应：win/operate/screen.png
library;

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// 控制操作页面桌面端
class OperateDesktop extends StatefulWidget {
  const OperateDesktop({super.key});

  @override
  State<OperateDesktop> createState() => _OperateDesktopState();
}

class _OperateDesktopState extends State<OperateDesktop> {
  // 前端补光强度
  double _lightIntensity = 0.75;
  
  // 控制状态
  bool _armExpanded = false;
  bool _mainPumpOn = true;
  bool _autoLevel = false;
  bool _panoramaScan = false;
  
  // 实时数据
  double _depth = 5.2;
  int _temperature = 35;
  String _leakStatus = '正常';

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

  /// 构建顶部标题区域
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
        // 通信延迟
        Container(
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
                '12ms',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建状态卡片
  Widget _buildStatusCards(bool isDark) {
    return Row(
      children: [
        // 探测深度
        Expanded(
          child: _buildStatusCard(
            title: '探测深度',
            value: _depth.toStringAsFixed(1),
            unit: 'm',
            icon: Icons.waves,
            iconBgColor: AppColors.primary.withOpacity(0.1),
            iconColor: AppColors.primary,
            valueColor: AppColors.primary,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 24),
        // 机器温度
        Expanded(
          child: _buildStatusCard(
            title: '机器温度',
            value: _temperature.toString(),
            unit: '°C',
            icon: Icons.thermostat,
            iconBgColor: Colors.transparent,
            iconColor: isDark ? AppColors.textSecondaryDark : AppColors.textHint,
            valueColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 24),
        // 漏水检测
        Expanded(
          child: _buildStatusCard(
            title: '漏水检测',
            value: _leakStatus,
            unit: '',
            icon: Icons.verified_user,
            iconBgColor: Colors.transparent,
            iconColor: AppColors.success,
            valueColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            isText: true,
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  /// 构建单个状态卡片
  Widget _buildStatusCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required Color valueColor,
    required bool isDark,
    bool isText = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.borderDark : AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
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
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
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
          // 数值
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: isText ? 32 : 36,
                  fontWeight: FontWeight.bold,
                  color: valueColor,
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
          // 状态指示
          Row(
            children: [
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
          child: Column(
            children: [
              _buildAuxiliarySystemCard(isDark),
              const SizedBox(height: 24),
              _buildSmartCorrectionCard(isDark),
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

  /// 构建辅助系统卡片
  Widget _buildAuxiliarySystemCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.borderDark : AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
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
            '控制补光灯、云台及机械臂',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textHint,
            ),
          ),
          const SizedBox(height: 32),
          // 补光强度滑块
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.light_mode, size: 16, color: isDark ? AppColors.textSecondaryDark : AppColors.textHint),
                  const SizedBox(width: 8),
                  Text(
                    '前端补光强度',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Text(
                '${(_lightIntensity * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.primary.withOpacity(0.2),
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withOpacity(0.1),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: _lightIntensity,
              onChanged: (value) {
                setState(() => _lightIntensity = value);
              },
              onChangeEnd: (value) {
                _showControlFeedback('补光强度已设置为 ${(value * 100).toInt()}%');
              },
            ),
          ),
          const SizedBox(height: 24),
          // 控制按钮网格
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 2.5,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildToggleControlButton(Icons.anchor, '机械臂展开', _armExpanded, isDark, () {
                setState(() => _armExpanded = !_armExpanded);
                _showControlFeedback('机械臂${_armExpanded ? "已展开" : "已收起"}');
              }),
              _buildToggleControlButton(Icons.power_settings_new, '关闭主泵', !_mainPumpOn, isDark, () {
                setState(() => _mainPumpOn = !_mainPumpOn);
                _showControlFeedback('主泵${_mainPumpOn ? "已开启" : "已关闭"}');
              }),
              _buildToggleControlButton(Icons.tune, '姿态自动调平', _autoLevel, isDark, () {
                setState(() => _autoLevel = !_autoLevel);
                _showControlFeedback('姿态自动调平${_autoLevel ? "已启用" : "已禁用"}');
              }),
              _buildToggleControlButton(Icons.track_changes, '全景扫描', _panoramaScan, isDark, () {
                setState(() => _panoramaScan = !_panoramaScan);
                _showControlFeedback('全景扫描${_panoramaScan ? "已启动" : "已停止"}');
              }),
            ],
          ),
        ],
      ),
    );
  }

  /// 显示控制反馈
  void _showControlFeedback(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 构建可切换状态的控制按钮
  Widget _buildToggleControlButton(IconData icon, String label, bool isActive, bool isDark, VoidCallback onTap) {
    return Material(
      color: isActive ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: isDark ? AppColors.surfaceDark : const Color(0xFFF8FAFC),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isActive ? AppColors.primary : (isDark ? AppColors.borderDark : AppColors.border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isActive ? AppColors.primary : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondary)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: isActive ? AppColors.primary : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimary),
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建智能纠偏系统提示卡片
  Widget _buildSmartCorrectionCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
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
                  '智能纠偏系统',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '当前水流速度较快，系统已自动启用动力补偿。',
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

  /// 构建方向控制卡片
  Widget _buildDirectionControlCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.borderDark : AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
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
                        ),
                      ),
                    ),
                    // 中心控制器
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
                    ),
                    const SizedBox(height: 40),
                    _buildSquareButton(
                      icon: Icons.expand_more,
                      label: '下潜',
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建方向按钮（按下时亮起）
  Widget _buildDirectionButton({
    required IconData icon,
    required String label,
    required bool isDark,
    bool isPrimary = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PressableButton(
          isPrimary: isPrimary,
          icon: icon,
          onPressed: () => _handleDirectionCommand(label),
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

  /// 处理方向控制命令
  void _handleDirectionCommand(String direction) {
    _showControlFeedback('执行: $direction');
    // 这里可以添加实际的通信逻辑
  }

  /// 构建方形控制按钮（按下时亮起）
  Widget _buildSquareButton({
    required IconData icon,
    required String label,
    required bool isDark,
    bool flipIcon = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PressableSquareButton(
          icon: icon,
          flipIcon: flipIcon,
          onPressed: () => _handleDirectionCommand(label),
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

  /// 构建中心控制器
  Widget _buildCenterControl(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.primary.withOpacity(0.1),
                Colors.transparent,
              ],
            ),
            border: Border.all(color: (isDark ? AppColors.borderDark : AppColors.border).withOpacity(0.5)),
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
                    color: AppColors.primary.withOpacity(0.4),
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
                    color: Colors.white.withOpacity(0.4),
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
            color: AppColors.primary.withOpacity(0.1),
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
    );
  }

  /// 构建紧急制动系统
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
          // 描述
          Text(
            '按下此按钮将立即切断动力电池输出并释放上浮气囊',
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
            shadowColor: AppColors.error.withOpacity(0.3),
            child: InkWell(
              onTap: () {
                // 显示确认对话框
                _showEmergencyStopDialog();
              },
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

  /// 显示紧急停止确认对话框
  void _showEmergencyStopDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: AppColors.error),
            SizedBox(width: 8),
            Text('紧急停止确认'),
          ],
        ),
        content: const Text('确定要执行紧急停止吗？这将立即切断动力电池输出并释放上浮气囊。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // 执行紧急停止
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('紧急停止命令已发送'),
                  backgroundColor: AppColors.error,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('确认停止', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

/// 可按压的圆形方向按钮（按下时亮起蓝色）
class _PressableButton extends StatefulWidget {
  final bool isPrimary;
  final IconData icon;
  final VoidCallback onPressed;

  const _PressableButton({
    this.isPrimary = false,
    required this.icon,
    required this.onPressed,
  });

  @override
  State<_PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<_PressableButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    // 按下时显示蓝色，否则显示白色（或主按钮默认样式）
    final bool showActive = _isPressed;
    
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
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
                    color: AppColors.primary.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
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

/// 可按压的方形按钮（上浮/下潜按钮，按下时亮起蓝色）
class _PressableSquareButton extends StatefulWidget {
  final IconData icon;
  final bool flipIcon;
  final VoidCallback onPressed;

  const _PressableSquareButton({
    required this.icon,
    this.flipIcon = false,
    required this.onPressed,
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
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
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
                    color: AppColors.primary.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Transform.flip(
          flipY: widget.flipIcon,
          child: Icon(
            widget.icon,
            size: 28,
            color: showActive ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
