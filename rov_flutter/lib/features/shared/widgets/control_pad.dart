/// 方向控制键盘（回调式，桌面/移动端复用）
///
/// 纯 UI 组件：按下/松开通过回调抛出方向，命令发送由调用方负责
/// （桌面端鼠标长按、移动端触屏均可复用）。
///
/// 布局：
/// ```
///        [ 上浮 ]（includeVertical 时显示在右侧）
///  [前进]
///  [左][停][右]
///  [后退]
///        [ 下潜 ]
/// ```
///
/// 可访问性：按钮触控目标 ≥48dp（移动端下限），语义标签齐全。
library;

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// 控制方向
enum ControlDirection { forward, backward, left, right, up, down }

/// 方向回调（携带方向）
typedef ControlDirectionCallback = void Function(ControlDirection direction);

/// 方向控制键盘
class ControlPad extends StatelessWidget {
  /// 指针按下回调（长按推进场景）
  final ControlDirectionCallback? onPress;

  /// 指针松开回调（松开即停）
  final ControlDirectionCallback? onRelease;

  /// 中央停止键点击回调
  final VoidCallback? onStop;

  /// 是否包含上浮/下潜竖排键（默认包含，六方向）
  final bool includeVertical;

  /// 单键尺寸（px），默认 56，最小 48（触摸目标下限）
  final double buttonSize;

  /// 按键间距
  final double spacing;

  /// 主色（默认 AppColors.primary）
  final Color accentColor;

  const ControlPad({
    super.key,
    this.onPress,
    this.onRelease,
    this.onStop,
    this.includeVertical = true,
    this.buttonSize = 56,
    this.spacing = 8,
    this.accentColor = AppColors.primary,
  }) : assert(buttonSize >= 48, '触控目标不得小于 48dp');

  @override
  Widget build(BuildContext context) {
    final size = buttonSize;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 十字方向区（前进/后退/左转/右转 + 中央停止）
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dirButton(ControlDirection.forward, Icons.arrow_upward, '前进'),
            SizedBox(height: spacing),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dirButton(ControlDirection.left, Icons.arrow_back, '左转'),
                SizedBox(width: spacing),
                _stopButton(size),
                SizedBox(width: spacing),
                _dirButton(ControlDirection.right, Icons.arrow_forward, '右转'),
              ],
            ),
            SizedBox(height: spacing),
            _dirButton(ControlDirection.backward, Icons.arrow_downward, '后退'),
          ],
        ),
        // 上浮/下潜竖排区
        if (includeVertical) ...[
          SizedBox(width: spacing * 2),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dirButton(ControlDirection.up, Icons.keyboard_double_arrow_up, '上浮'),
              SizedBox(height: spacing),
              _dirButton(
                  ControlDirection.down, Icons.keyboard_double_arrow_down, '下潜'),
            ],
          ),
        ],
      ],
    );
  }

  /// 方向按键（按下/松开双回调，支持长按推进）
  Widget _dirButton(ControlDirection dir, IconData icon, String label) {
    return _PadButton(
      size: buttonSize,
      icon: icon,
      semanticLabel: label,
      tooltip: label,
      color: accentColor,
      onPress: onPress != null ? () => onPress!(dir) : null,
      onRelease: onRelease != null ? () => onRelease!(dir) : null,
    );
  }

  /// 中央停止键（红色，紧急语义）
  Widget _stopButton(double size) {
    return _PadButton(
      size: size,
      icon: Icons.stop,
      semanticLabel: '停止',
      tooltip: '停止',
      color: AppColors.danger,
      onPress: onStop,
      onRelease: null,
      tapMode: true,
    );
  }
}

/// 键盘单键：基于 Listener 的按下/松开事件（兼容鼠标与触屏）
class _PadButton extends StatelessWidget {
  final double size;
  final IconData icon;
  final String semanticLabel;
  final String tooltip;
  final Color color;

  /// tapMode=true 时仅响应点击（停止键）；false 时响应按下/松开
  final bool tapMode;
  final VoidCallback? onPress;
  final VoidCallback? onRelease;

  const _PadButton({
    required this.size,
    required this.icon,
    required this.semanticLabel,
    required this.tooltip,
    required this.color,
    this.onPress,
    this.onRelease,
    this.tapMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: tapMode ? onPress : null,
          child: Center(
            child: Icon(icon, size: size * 0.42, color: color),
          ),
        ),
      ),
    );

    final gesture = Listener(
      onPointerDown: tapMode ? null : (_) => onPress?.call(),
      onPointerUp: tapMode ? null : (_) => onRelease?.call(),
      onPointerCancel: tapMode ? null : (_) => onRelease?.call(),
      child: button,
    );

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Tooltip(message: tooltip, child: gesture),
    );
  }
}
