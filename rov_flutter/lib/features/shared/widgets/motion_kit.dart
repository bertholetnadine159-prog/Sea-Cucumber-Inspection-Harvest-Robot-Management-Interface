/// SeaUI 企业级动效工具箱（Motion Kit）
///
/// 设计原则（对齐 docs/STYLE_SPEC.md §9"整体动效克制"的基调）：
/// 1. **克制**：只做淡入 + 微位移（3%~4% 画幅）与轻缩放，无弹跳大动画、无视差；
/// 2. **60fps 优先**：全部动效只驱动 opacity / transform（GPU 合成层），
///    不触发重布局（layout），不用逐帧重绘的自绘动画；
/// 3. **服务状态感知**：动效只出现在"状态发生变化"的位置
///    （路由切换 / 页签切换 / 按压反馈 / 数值刷新 / 加载中 / 列表入场）；
/// 4. **尊重无障碍**：所有动效均检查 [Motion.reduceMotion]
///    （SettingsProvider.reduceMotion，设置页可开关），
///    开启后一律短路为直接呈现目标状态。
///
/// 本文件只提供通用组件，不绑定任何业务数据；真实数据接线由页面层完成
/// （RovBackendService 三通道 / StaleBadge 等既有绑定不受影响）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/settings_provider.dart';
import '../../../core/theme/app_colors.dart';

/// 动效时长 / 曲线令牌
///
/// 时长沿用 AppConstants.animationFast/Normal/Slow（150/300/500ms，STYLE_SPEC §9），
/// 特殊场景（按压、骨架屏脉冲、错峰步长）单独声明。
class MotionTokens {
  MotionTokens._();

  // ---- 时长 ----

  /// 快速：状态点变色、文本淡入淡出（150ms）
  static const Duration fast = AppConstants.animationFast;

  /// 标准：页签切换、数值滚动、列表入场（300ms）
  static const Duration normal = AppConstants.animationNormal;

  /// 慢速：整页级路由转场（500ms）
  static const Duration slow = AppConstants.animationSlow;

  /// 登录 → 主界面路由转场（对齐现状 400ms，STYLE_SPEC §9）
  static const Duration pageRoute = Duration(milliseconds: 400);

  /// 主界面路由转场（对齐现状 500ms，STYLE_SPEC §9）
  static const Duration dashboardRoute = Duration(milliseconds: 500);

  /// 按压缩放 - 按下（快到达，短促）
  static const Duration pressIn = Duration(milliseconds: 100);

  /// 按压缩放 - 释放（带回弹沉降）
  static const Duration pressOut = Duration(milliseconds: 200);

  /// 骨架屏脉冲周期（单次明→暗→明）
  static const Duration skeletonPulse = Duration(milliseconds: 1200);

  /// 列表错峰步长（相邻两项的入场间隔）
  static const Duration staggerStep = Duration(milliseconds: 40);

  /// 错峰总延迟上限（超出后各项同时入场，避免长列表等太久）
  static const Duration maxStaggerDelay = Duration(milliseconds: 480);

  // ---- 曲线 ----

  /// 入场标准曲线（STYLE_SPEC §9 现状：easeOutCubic）
  static const Curve standard = Curves.easeOutCubic;

  /// 退场曲线（加速离场，入场/退场非对称更干净）
  static const Curve exit = Curves.easeInCubic;

  /// 双向过渡（旧页签切换 easeInOut 的克制版）
  static const Curve emphasized = Curves.easeInOutCubic;

  /// 按下曲线（快速到达按压态）
  static const Curve press = Curves.easeOut;

  /// 释放曲线（easeOutBack 微过冲 → "触感沉降"，幅度被 3% 缩放行程天然限制）
  static const Curve settle = Curves.easeOutBack;
}

/// 全局动效开关入口
///
/// reduceMotion 由 SettingsProvider 承载（单例），ROVApp 监听设置变化时
/// 会整树重建，因此组件在 build / 触发动画时读取即为最新值。
class Motion {
  Motion._();

  /// 是否"减少动画"（无障碍开关）
  static bool get reduceMotion => SettingsProvider().reduceMotion;

  /// reduceMotion 开启时返回 Duration.zero，否则原样返回
  static Duration durationOrZero(Duration normal) =>
      reduceMotion ? Duration.zero : normal;
}

// ============================================================================
// ① AppPageTransition —— 页面级转场（登录→主界面、页签切换）
// ============================================================================

/// 页面转场：淡入 + 微位移上浮
///
/// 两种用法：
/// 1. **路由转场**（登录→主界面）：
///    ```dart
///    PageRouteBuilder(
///      pageBuilder: ...,
///      transitionsBuilder: AppPageTransition.routeTransitionsBuilder,
///      transitionDuration: Motion.durationOrZero(MotionTokens.pageRoute),
///    )
///    ```
/// 2. **页签切换**（配合 AnimatedSwitcher，旧页淡出、新页淡入交叉进行）：
///    ```dart
///    AnimatedSwitcher(
///      duration: Motion.durationOrZero(MotionTokens.normal),
///      transitionBuilder: (child, animation) =>
///          AppPageTransition(animation: animation, child: child),
///      child: KeyedSubtree(key: ValueKey(currentIndex), child: page),
///    )
///    ```
class AppPageTransition extends StatelessWidget {
  const AppPageTransition({
    super.key,
    required this.child,
    this.animation,
    this.offset = const Offset(0, 0.04),
    this.duration = MotionTokens.normal,
  });

  /// 页面内容
  final Widget child;

  /// 外部驱动的进度动画（AnimatedSwitcher / PageRouteBuilder 传入）；
  /// 为 null 时组件自驱动：挂载后播放一次入场（可用于任意面板首帧入场）。
  final Animation<double>? animation;

  /// 入场位移（画幅比例；默认上浮 4%）
  final Offset offset;

  /// 自驱动模式的时长（外部驱动时由调用方控制）
  final Duration duration;

  /// PageRouteBuilder.transitionsBuilder 直连签名。
  /// reduceMotion 开启时直接返回 child（无转场）。
  static Widget routeTransitionsBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return AppPageTransition(animation: animation, child: child);
  }

  @override
  Widget build(BuildContext context) {
    // 无障碍：减少动画 → 直接呈现
    if (Motion.reduceMotion) return child;
    final external = animation;
    if (external != null) {
      return _DrivenFadeSlide(animation: external, offset: offset, child: child);
    }
    return _SelfFadeSlide(offset: offset, duration: duration, child: child);
  }
}

/// 外部动画驱动的 淡入+微位移
class _DrivenFadeSlide extends StatefulWidget {
  const _DrivenFadeSlide({
    required this.animation,
    required this.offset,
    required this.child,
  });

  final Animation<double> animation;
  final Offset offset;
  final Widget child;

  @override
  State<_DrivenFadeSlide> createState() => _DrivenFadeSlideState();
}

class _DrivenFadeSlideState extends State<_DrivenFadeSlide> {
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: widget.animation,
    curve: MotionTokens.standard,
    reverseCurve: MotionTokens.exit,
  );

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _fadeSlideTree(_curved, widget.offset, widget.child);
  }
}

/// 自驱动入场：挂载后播放一次 淡入+微位移
class _SelfFadeSlide extends StatefulWidget {
  const _SelfFadeSlide({
    required this.offset,
    required this.duration,
    required this.child,
  });

  final Offset offset;
  final Duration duration;
  final Widget child;

  @override
  State<_SelfFadeSlide> createState() => _SelfFadeSlideState();
}

class _SelfFadeSlideState extends State<_SelfFadeSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: Motion.reduceMotion ? 1.0 : 0.0,
  );
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: _controller,
    curve: MotionTokens.standard,
  );

  @override
  void initState() {
    super.initState();
    if (!Motion.reduceMotion) _controller.forward();
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _fadeSlideTree(_curved, widget.offset, widget.child);
  }
}

/// 共享合成树：只动 opacity / translate（GPU 合成，不触发重布局）
Widget _fadeSlideTree(
  Animation<double> curved,
  Offset offset,
  Widget child,
) {
  return FadeTransition(
    opacity: curved,
    child: SlideTransition(
      position: Tween<Offset>(begin: offset, end: Offset.zero).animate(curved),
      child: child,
    ),
  );
}

// ============================================================================
// ② PressableScale —— 按压缩放 + 触感反馈曲线
// ============================================================================

/// 可按压组件：按下缩放至 [pressScale]，释放带回弹沉降，可选触感反馈
///
/// - 按下：100ms `Curves.easeOut` 快速到达按压态；
/// - 释放：200ms `Curves.easeOutBack` 反向播放 → 释放瞬间轻微"压实再回弹"，
///   形成触感反馈曲线（行程被 3% 缩放限制，肉眼克制）；
/// - [hapticFeedback]：按下时触发 `HapticFeedback.selectionClick`
///   （桌面端无振动硬件时为安全空操作）；
/// - [onTap] 为 null 时仅提供视觉反馈，不参与手势竞技（可安全包裹
///   自带 InkWell 的按钮/卡片——点击仍由内部控件处理，缩放照常生效）；
/// - reduceMotion 开启时关闭缩放与触感，仅保留 child 原行为。
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressScale = 0.97,
    this.hapticFeedback = true,
    this.enabled = true,
  });

  final Widget child;

  /// 点击回调（可选；child 自带点击处理时可留空）
  final VoidCallback? onTap;

  /// 按下时的缩放比例（默认 0.97，克制）
  final double pressScale;

  /// 是否触发光反馈（HapticFeedback.selectionClick）
  final bool hapticFeedback;

  /// false 时禁用按压反馈与点击
  final bool enabled;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MotionTokens.pressIn,
    value: Motion.reduceMotion ? 1.0 : 0.0,
  );
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: _controller,
    curve: MotionTokens.press,
    reverseCurve: MotionTokens.settle,
  );

  void _setPressed(bool pressed) {
    if (!mounted || !widget.enabled || Motion.reduceMotion) return;
    if (pressed && widget.hapticFeedback) {
      HapticFeedback.selectionClick();
    }
    _controller.duration =
        pressed ? MotionTokens.pressIn : MotionTokens.pressOut;
    pressed ? _controller.forward() : _controller.reverse();
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: widget.onTap != null
            ? HitTestBehavior.opaque
            : HitTestBehavior.deferToChild,
        child: ScaleTransition(
          scale:
              Tween<double>(begin: 1.0, end: widget.pressScale).animate(_curved),
          child: widget.child,
        ),
      ),
    );
  }
}

// ============================================================================
// ③ AnimatedTelemetryValue —— 数值变化滚动插值
// ============================================================================

/// 遥测数值滚动：新值到来时从"当前显示值"平滑插值到新值
///
/// - 打断平滑：动画途中再次变化时，从当前插值继续滚向最新值，不跳变；
/// - [formatter] 自定义格式（如 `v => '${v.toStringAsFixed(0)}%'`），
///   默认按 [decimals] 位小数输出；
/// - [value] 为 NaN / ±∞（真实链路常见于无源）时显示 [invalidText]（默认"—"）；
/// - 只重建一个 Text，不触发布局动画；reduceMotion 开启时直接显示新值。
///
/// 注意：本组件不产生数据，数值必须由页面层从真实链路（telemetryNotifier）
/// 传入——无源时传 `double.nan` 即显示占位，不做任何合成兜底。
class AnimatedTelemetryValue extends StatefulWidget {
  const AnimatedTelemetryValue({
    super.key,
    required this.value,
    this.decimals = 1,
    this.formatter,
    this.style,
    this.duration = MotionTokens.normal,
    this.invalidText = '—',
  });

  /// 目标数值（真实链路数据；NaN/±∞ 显示占位）
  final double value;

  /// 默认格式化的小数位数（[formatter] 为 null 时生效）
  final int decimals;

  /// 自定义格式化
  final String Function(double value)? formatter;

  /// 数值样式（如 AppTextStyles.dataMedium）
  final TextStyle? style;

  /// 单次滚动时长
  final Duration duration;

  /// 非法值占位文案
  final String invalidText;

  @override
  State<AnimatedTelemetryValue> createState() => _AnimatedTelemetryValueState();
}

class _AnimatedTelemetryValueState extends State<AnimatedTelemetryValue>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: _controller,
    curve: MotionTokens.standard,
  );
  late double _from = widget.value;
  late double _to = widget.value;

  bool get _isValid => !widget.value.isNaN && !widget.value.isInfinite;

  /// 当前应显示的插值
  ///
  /// `_from` 为 NaN/±∞（此前无源显示占位）时无法插值，
  /// 直接呈现新值——数据从"无源"到"有源"的第一帧即显示真实值。
  double get _displayed {
    if (!_from.isFinite) return _to;
    return _from + (_to - _from) * _curved.value;
  }

  @override
  void didUpdateWidget(covariant AnimatedTelemetryValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    // NaN != NaN 恒为 true：两者皆 NaN（持续无源）不触发动画
    final changed = widget.value != oldWidget.value &&
        !(widget.value.isNaN && oldWidget.value.isNaN);
    if (changed) {
      // 从当前插值继续滚动，动画被打断也不跳变
      _from = _displayed;
      _to = widget.value;
      if (Motion.reduceMotion || widget.duration == Duration.zero) {
        _controller.value = 1.0;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _format(double v) {
    if (!_isValid) return widget.invalidText;
    return widget.formatter?.call(v) ?? v.toStringAsFixed(widget.decimals);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Text(
        _format(_displayed),
        style: widget.style,
      ),
    );
  }
}

// ============================================================================
// ④ SkeletonLoader —— 加载骨架
// ============================================================================

/// 加载骨架：圆角占位块 + 低频明暗脉冲
///
/// - 脉冲只做 opacity（0.55 ↔ 1.0），单块无重绘压力，成片也稳定 60fps；
/// - 多行时末行默认 60% 宽，模拟文本收尾（[lastLineFactor] 可调，传 null 等宽）；
/// - 底色默认随明暗主题取 borderLight / borderDark；
/// - reduceMotion 开启时脉冲静止（固定 55% 透明度的静态骨架）。
class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({
    super.key,
    this.width,
    this.height = 14,
    this.lines = 1,
    this.spacing = 8,
    this.borderRadius,
    this.baseColor,
    this.lastLineFactor = 0.6,
  });

  /// 单块宽度（null 时撑满父容器约束）
  final double? width;

  /// 单行高度
  final double height;

  /// 行数（>1 时纵向排列，间距 [spacing]）
  final int lines;

  /// 多行间距
  final double spacing;

  /// 圆角（默认按行高取半 = 胶囊形）
  final BorderRadius? borderRadius;

  /// 底色（默认随主题取 border 色）
  final Color? baseColor;

  /// 末行宽度比例（null = 与其他行等宽）
  final double? lastLineFactor;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: MotionTokens.skeletonPulse,
  );

  @override
  void initState() {
    super.initState();
    if (!Motion.reduceMotion) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant SkeletonLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 设置页切换 reduceMotion 时跟随
    if (Motion.reduceMotion) {
      if (_pulse.isAnimating) _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.baseColor ??
        (Theme.of(context).brightness == Brightness.dark
            ? AppColors.borderDark
            : AppColors.borderLight);
    final radius =
        widget.borderRadius ?? BorderRadius.circular(widget.height / 2);

    Widget block({double? widthFactor}) {
      final content = Container(
        height: widget.height,
        decoration: BoxDecoration(color: base, borderRadius: radius),
      );
      final faded = FadeTransition(
        opacity: Tween<double>(begin: 0.55, end: 1.0).animate(
          CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
        ),
        child: content,
      );
      if (widthFactor == null) return faded;
      return FractionallySizedBox(
        widthFactor: widthFactor,
        alignment: Alignment.centerLeft,
        child: faded,
      );
    }

    if (widget.lines <= 1) {
      return SizedBox(
        width: widget.width,
        child: block(),
      );
    }

    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.lines; i++) ...[
            if (i > 0) SizedBox(height: widget.spacing),
            block(
              widthFactor: (i == widget.lines - 1) ? widget.lastLineFactor : null,
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// ⑤ StaggerIn —— 列表错峰入场
// ============================================================================

/// 列表项错峰入场：按 [index] 依次延迟 [step]，淡入 + 微位移
///
/// ```dart
/// Column(children: [
///   for (var i = 0; i < items.length; i++)
///     StaggerIn(index: i, child: items[i]),
/// ])
/// ```
///
/// - 总延迟封顶 [MotionTokens.maxStaggerDelay]：长列表尾部不再干等；
/// - 仅首次挂载播放（入场动画），后续数据刷新不重复打扰；
/// - reduceMotion 开启时直接呈现。
class StaggerIn extends StatefulWidget {
  const StaggerIn({
    super.key,
    required this.child,
    this.index = 0,
    this.step = MotionTokens.staggerStep,
    this.delay = Duration.zero,
    this.duration = MotionTokens.normal,
    this.offset = const Offset(0, 0.03),
  });

  final Widget child;

  /// 列表中的序号（决定错峰延迟 = delay + step × index，封顶见类注释）
  final int index;

  /// 相邻项延迟步长
  final Duration step;

  /// 额外起始延迟
  final Duration delay;

  /// 单项入场时长
  final Duration duration;

  /// 入场位移（画幅比例；默认上浮 3%）
  final Offset offset;

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: Motion.reduceMotion ? 1.0 : 0.0,
  );
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: _controller,
    curve: MotionTokens.standard,
  );

  /// delay + step × index，封顶 maxStaggerDelay
  Duration get _startDelay {
    final total = widget.delay + widget.step * widget.index;
    return total > MotionTokens.maxStaggerDelay
        ? MotionTokens.maxStaggerDelay
        : total;
  }

  @override
  void initState() {
    super.initState();
    if (!Motion.reduceMotion) {
      Future.delayed(_startDelay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduceMotion) return widget.child;
    return _fadeSlideTree(_curved, widget.offset, widget.child);
  }
}
