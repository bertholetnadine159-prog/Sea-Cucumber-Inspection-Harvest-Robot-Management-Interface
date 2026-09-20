/// 方向控制键盘（回调式，桌面/移动端复用）
///
/// 纯 UI 组件：按下/松开通过回调抛出方向，命令发送由调用方负责
/// （桌面端鼠标长按、移动端触屏均可复用）。
///
/// 视觉按旧版（1cc31e5）方向盘语言还原（STYLE_SPEC §7.3A/§7.3B）：
/// - 方向键：白底 + borderLight 描边圆角 8，前进/后退纵长、左转/右转横长，
///   图标用 `keyboard_arrow_*` 主色 + caption 10 标签；
/// - 上浮/下潜：`expand_less/more` 方形描边键；
/// - 中心键：主色圆 + 白色图标 + 主色光晕（30% / blur16 / spread2），
///   点击 = 停止；
/// - 按压亮起（§7.3B）：按下瞬间底变主色、图标变白、阴影换主色光晕
///   （40% / blur12 / (0,4)）；松开/取消恢复白底描边
///   （黑 5% / blur4 / (0,2)）。
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
///
/// 动效（motion kit 令牌化，§7.3B 视觉不变）：
/// - 按下/松开的底色、描边、阴影交叉过渡 100ms（AnimatedContainer，
///   reduceMotion 时时长归零 = 瞬时切换）；
/// - 键帽 spring 感按压：按下 100ms 缩至 0.96，释放经欠阻尼弹簧
///   （MotionSpring.releaseBack）物理回弹，自带轻微过冲；
/// - 修复：中心停止键（tapMode）点击后 `_pressed` 曾永久滞留在
///   按压态——现按下视觉绑定 onTapDown/Up/Cancel，回调仍只在
///   onTap 触发一次（命令语义不变）。
library;

import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import 'motion_kit.dart';

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
    // 旧版几何：纵长/横长键比 1:1.2
    final longSide = size * 1.2;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 十字方向区（前进/后退/左转/右转 + 中央停止）
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dirButton(ControlDirection.forward, Icons.keyboard_arrow_up, '前进',
                width: size, height: longSide),
            SizedBox(height: spacing),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dirButton(ControlDirection.left, Icons.keyboard_arrow_left,
                    '左转',
                    width: longSide, height: size),
                SizedBox(width: spacing),
                _stopButton(size),
                SizedBox(width: spacing),
                _dirButton(ControlDirection.right, Icons.keyboard_arrow_right,
                    '右转',
                    width: longSide, height: size),
              ],
            ),
            SizedBox(height: spacing),
            _dirButton(ControlDirection.backward, Icons.keyboard_arrow_down,
                '后退',
                width: size, height: longSide),
          ],
        ),
        // 上浮/下潜竖排区（旧版 expand_less/more 方形描边键）
        if (includeVertical) ...[
          SizedBox(width: spacing * 2),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dirButton(
                  ControlDirection.up, Icons.expand_less, '上浮',
                  width: size, height: size),
              SizedBox(height: spacing),
              _dirButton(
                  ControlDirection.down, Icons.expand_more, '下潜',
                  width: size, height: size),
            ],
          ),
        ],
      ],
    );
  }

  /// 方向按键（按下/松开双回调，支持长按推进）
  Widget _dirButton(ControlDirection dir, IconData icon, String label,
      {required double width, required double height}) {
    return _PadButton(
      width: width,
      height: height,
      icon: icon,
      semanticLabel: label,
      tooltip: label,
      color: accentColor,
      onPress: onPress != null ? () => onPress!(dir) : null,
      onRelease: onRelease != null ? () => onRelease!(dir) : null,
    );
  }

  /// 中央停止键（旧版：主色圆 + 光晕，点击 = 停止）
  Widget _stopButton(double size) {
    return _PadButton(
      width: size,
      height: size,
      icon: Icons.videogame_asset,
      semanticLabel: '停止',
      tooltip: '停止',
      color: accentColor,
      circle: true,
      glow: true,
      onPress: onStop,
      onRelease: null,
      tapMode: true,
    );
  }
}

/// 键盘单键：基于 Listener 的按下/松开事件（兼容鼠标与触屏）
/// 带旧版 §7.3B 按压亮起视觉：按下主色底白图标 + 主色光晕。
class _PadButton extends StatefulWidget {
  final double width;
  final double height;
  final IconData icon;
  final String semanticLabel;
  final String tooltip;
  final Color color;

  /// 圆形键（中心停止键）
  final bool circle;

  /// 静息态即带主色光晕（中心停止键）
  final bool glow;

  /// tapMode=true 时仅响应点击（停止键）；false 时响应按下/松开
  final bool tapMode;
  final VoidCallback? onPress;
  final VoidCallback? onRelease;

  const _PadButton({
    required this.width,
    required this.height,
    required this.icon,
    required this.semanticLabel,
    required this.tooltip,
    required this.color,
    this.circle = false,
    this.glow = false,
    this.onPress,
    this.onRelease,
    this.tapMode = false,
  });

  @override
  State<_PadButton> createState() => _PadButtonState();
}

class _PadButtonState extends State<_PadButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;

  /// 键帽缩放行程：0 = 静息，1 = 全按压；下界放开承接弹簧释放过冲
  late final AnimationController _press = AnimationController(
    vsync: this,
    lowerBound: -0.35,
    upperBound: 1.0,
    value: 0.0,
    duration: MotionTokens.pressIn,
  );

  /// 按压视觉（缩放 + 阴影/底色），不触发命令回调
  void _setVisualPressed(bool pressed) {
    setState(() => _pressed = pressed);
    if (Motion.reduceMotion) return;
    if (pressed) {
      _press.animateTo(
        1.0,
        duration: MotionTokens.pressIn,
        curve: MotionTokens.press,
      );
    } else {
      MotionSpring.releaseBack(_press);
    }
  }

  void _handlePress() {
    _setVisualPressed(true);
    widget.onPress?.call();
  }

  void _handleRelease() {
    _setVisualPressed(false);
    widget.onRelease?.call();
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(
        widget.circle ? 999 : AppConstants.radiusMd);

    // 静息态：白底 + 1.5px borderLight 描边 + 黑5% blur4 (0,2)
    // 按下态（§7.3B）：主色底 + 白图标 + 主色光晕 40% blur12 (0,4)
    // （按下态描边用与填充同色，避免 none↔all 插值跳变，交叉过渡更平滑）
    final BoxDecoration decoration = _pressed
        ? BoxDecoration(
            color: widget.color,
            borderRadius: radius,
            border: Border.all(color: widget.color, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.40),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          )
        : BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: radius,
            border: Border.all(
              color: AppColors.borderLight,
              width: 1.5,
            ),
            boxShadow: [
              if (widget.glow)
                BoxShadow(
                  // 旧版中心钮光晕：主色 30% / blur16 / spread 2
                  color: widget.color.withValues(alpha: 0.30),
                  blurRadius: 16,
                  spreadRadius: 2,
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
            ],
          );

    final bool showLabel = !widget.circle;
    final label = Text(
      widget.semanticLabel,
      style: AppTextStyles.withColor(
        AppTextStyles.caption.copyWith(fontSize: 10, height: 1.1),
        _pressed ? Colors.white : AppColors.textHint,
      ),
    );

    // 底色/描边/阴影交叉过渡（§7.3B"按压亮起"的令牌化版本；
    // reduceMotion 时 Motion.durationOrZero → 瞬时切换）
    final button = AnimatedContainer(
      duration: Motion.durationOrZero(MotionTokens.pressIn),
      curve: MotionTokens.press,
      width: widget.width,
      height: widget.height,
      decoration: decoration,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          // tapMode（中心停止键）：按下视觉绑定 down/up/cancel，
          // 命令回调只在 onTap 触发一次——修复点击后视觉滞留按压态
          onTapDown: widget.tapMode ? (_) => _setVisualPressed(true) : null,
          onTapUp: widget.tapMode ? (_) => _setVisualPressed(false) : null,
          onTapCancel:
              widget.tapMode ? () => _setVisualPressed(false) : null,
          onTap: widget.tapMode ? () => widget.onPress?.call() : null,
          child: Center(
            child: showLabel
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.icon,
                        size: widget.width * 0.4,
                        color: _pressed ? Colors.white : widget.color,
                      ),
                      const SizedBox(height: 2),
                      label,
                    ],
                  )
                : Icon(
                    widget.icon,
                    size: widget.width * 0.44,
                    color: Colors.white,
                  ),
          ),
        ),
      ),
    );

    // 键帽 spring 感按压：0.96 缩放 + 弹簧释放过冲
    // （只动 transform，不重布局；reduceMotion 时控制器恒 0 = 无缩放）
    final scaled = ScaleTransition(
      scale: Tween<double>(begin: 1.0, end: 0.96).animate(_press),
      child: button,
    );

    final gesture = Listener(
      onPointerDown: widget.tapMode ? null : (_) => _handlePress(),
      onPointerUp: widget.tapMode ? null : (_) => _handleRelease(),
      onPointerCancel: widget.tapMode ? null : (_) => _handleRelease(),
      child: scaled,
    );

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: Tooltip(message: widget.tooltip, child: gesture),
    );
  }
}
