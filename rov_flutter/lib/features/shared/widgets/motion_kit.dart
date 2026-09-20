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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/settings_provider.dart';
import '../../../core/theme/app_colors.dart';

/// 动效时长 / 曲线令牌
///
/// 时长沿用 AppConstants.animationFast/Normal/Slow（150/300/500ms，STYLE_SPEC §9），
/// 特殊场景（按压、骨架屏脉冲、错峰步长、卡片入场、高光扫过）单独声明。
/// 全仓库动效时长/曲线一律从这里取值，禁止散落魔法数。
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

  /// 按压缩放 - 释放（带回弹沉降；实际曲线由 [MotionSpring] 弹簧给出）
  static const Duration pressOut = Duration(milliseconds: 200);

  /// 骨架屏脉冲周期（单次明→暗→明）
  static const Duration skeletonPulse = Duration(milliseconds: 1200);

  /// 骨架屏高光扫过周期（单次左→右，与脉冲错频避免同步闪烁）
  static const Duration skeletonSweep = Duration(milliseconds: 1600);

  /// 卡片悬浮入场（淡入 + 上浮 + 微缩放）
  static const Duration cardEntrance = Duration(milliseconds: 360);

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

  /// 按压释放兜底曲线（仅在不能走弹簧模拟的场景使用；
  /// 可走弹簧时用 [MotionSpring.releaseBack]，物理过冲更自然）
  static const Curve settle = Curves.easeOutBack;
}

/// 按压释放的弹簧物理
///
/// 轻微欠阻尼（ratio 0.55）：从按压态弹回静息时带一次天然过冲。
/// 行程被按压缩放（默认 3%）限制，过冲约 0.4%——肉眼克制，手感真实。
class MotionSpring {
  MotionSpring._();

  /// 释放回弹弹簧描述
  static final SpringDescription release =
      SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 420.0,
    ratio: 0.55,
  );

  /// 把按压控制器用释放弹簧从当前位置送回 0（静息）。
  ///
  /// 可被后续 `animateTo` 随时打断（再次按下时平滑接管）。
  static void releaseBack(AnimationController controller) {
    controller.animateWith(
      SpringSimulation(release, controller.value, 0.0, 0.0),
    );
  }
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
// ② PressableScale —— spring 感按压 + 阴影随按压变化
// ============================================================================

/// 可按压组件：按下缩放至 [pressScale]，释放经弹簧回弹沉降，
/// 可选触感反馈与"按压抬升阴影"
///
/// - 按下：100ms `Curves.easeOut` 快速到达按压态；
/// - 释放：`MotionSpring.release` 欠阻尼弹簧从当前位置物理回弹，
///   自带一次轻微过冲（缩放短暂越过 1.0 再沉降）——"触感沉降"；
/// - [liftOnPress]：配合 [borderRadius] 在按压缩放的同时把投影从
///   [restShadow] 抬升到 [pressedShadow]（默认静息黑 2%/blur8/(0,2) →
///   按压黑 8%/blur16/(0,6)），形成"卡片被拿起来"的层次反馈；
/// - [hapticFeedback]：按下时触发 `HapticFeedback.selectionClick`
///   （桌面端无振动硬件时为安全空操作）；
/// - [onTap] 为 null 时仅提供视觉反馈，不参与手势竞技（可安全包裹
///   自带 InkWell 的按钮/卡片——点击仍由内部控件处理，缩放照常生效）；
/// - reduceMotion 开启时关闭缩放/阴影/触感，仅保留 child 原行为。
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressScale = 0.97,
    this.hapticFeedback = true,
    this.enabled = true,
    this.liftOnPress = false,
    this.borderRadius,
    this.restShadow,
    this.pressedShadow,
  }) : assert(
          !liftOnPress || borderRadius != null,
          'liftOnPress 需要提供 borderRadius 以对齐被包裹卡片的圆角',
        );

  /// 静息投影（[liftOnPress] 时生效；默认黑 2% / blur8 / (0,2)，旧版标准卡片投影）
  static const BoxShadow defaultRestShadow = BoxShadow(
    color: Color(0x05000000), // black 2%
    blurRadius: 8,
    offset: Offset(0, 2),
  );

  /// 按压投影（[liftOnPress] 时生效；默认黑 8% / blur16 / (0,6)）
  static const BoxShadow defaultPressedShadow = BoxShadow(
    color: Color(0x14000000), // black 8%
    blurRadius: 16,
    offset: Offset(0, 6),
  );

  final Widget child;

  /// 点击回调（可选；child 自带点击处理时可留空）
  final VoidCallback? onTap;

  /// 按下时的缩放比例（默认 0.97，克制）
  final double pressScale;

  /// 是否触发光反馈（HapticFeedback.selectionClick）
  final bool hapticFeedback;

  /// false 时禁用按压反馈与点击
  final bool enabled;

  /// 按压时是否抬升阴影（需同时提供 [borderRadius]）
  final bool liftOnPress;

  /// 阴影层圆角（需与被包裹卡片圆角一致）
  final BorderRadius? borderRadius;

  /// 静息投影（null 用 [defaultRestShadow]）
  final BoxShadow? restShadow;

  /// 按压投影（null 用 [defaultPressedShadow]）
  final BoxShadow? pressedShadow;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  /// 行程：0 = 静息，1 = 全按压。
  /// lowerBound 放开到负值以承接弹簧释放的过冲（缩放短暂越过 1.0）。
  late final AnimationController _controller = AnimationController(
    vsync: this,
    lowerBound: -0.35,
    upperBound: 1.0,
    value: 0.0,
    duration: MotionTokens.pressIn,
  );

  /// 行程 → 缩放（t 可为负 = 弹簧过冲，缩放略大于 1）
  double _scaleFor(double t) => 1.0 + (widget.pressScale - 1.0) * t;

  /// 行程 → 投影（负行程按 0 处理，过冲阶段阴影保持静息态）
  BoxShadow _shadowFor(double t) => BoxShadow.lerp(
        widget.restShadow ?? PressableScale.defaultRestShadow,
        widget.pressedShadow ?? PressableScale.defaultPressedShadow,
        t.clamp(0.0, 1.0),
      )!;

  void _setPressed(bool pressed) {
    if (!mounted || !widget.enabled || Motion.reduceMotion) return;
    if (pressed && widget.hapticFeedback) {
      HapticFeedback.selectionClick();
    }
    if (pressed) {
      _controller.animateTo(
        1.0,
        duration: MotionTokens.pressIn,
        curve: MotionTokens.press,
      );
    } else {
      MotionSpring.releaseBack(_controller);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 无障碍：减少动画 → 完全旁路，child 原样呈现（缩放/阴影/触感全关）
    if (!widget.enabled || Motion.reduceMotion) return widget.child;
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: widget.onTap != null
            ? HitTestBehavior.opaque
            : HitTestBehavior.deferToChild,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = _controller.value;
            Widget inner =
                Transform.scale(scale: _scaleFor(t), child: child!);
            if (widget.liftOnPress) {
              inner = DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: widget.borderRadius,
                  boxShadow: [_shadowFor(t)],
                ),
                child: inner,
              );
            }
            return inner;
          },
          child: widget.child,
        ),
      ),
    );
  }
}

// ============================================================================
// ③ AnimatedTelemetryValue —— 数值变化滚动插值（缓出 + 稳定渲染）
// ============================================================================

/// 遥测数值滚动：新值到来时从"当前显示值"平滑插值到新值
///
/// - 缓出：300ms `easeOutCubic`，快速响应 + 柔和落位；
/// - 打断平滑：动画途中再次变化时，从当前插值继续滚向最新值，不跳变；
/// - 稳定渲染：内部缓存格式化结果与 Text 实例，插值收敛 / 字符串未变化时
///   不重建 Text（渲染树零抖动）；动画结束后控制器自然停止，不空转；
/// - [formatter] 自定义格式（如 `v => '${v.toStringAsFixed(0)}%'`），
///   默认按 [decimals] 位小数输出；
/// - [value] 为 NaN / ±∞（真实链路常见于无源）时显示 [invalidText]（默认"—"）；
///   目标变为非法值时直接呈现占位，不跨非有限值插值；
/// - reduceMotion 开启时直接显示新值。
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

  // 稳定渲染：字符串未变时不重建 Text（identical 实例 → 渲染树直接复用）
  String? _lastText;
  Text? _cachedText;

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
    if (!changed) return;

    if (!widget.value.isFinite) {
      // 目标非法（断链占位）：不跨非有限值插值，直接呈现占位
      _from = widget.value;
      _to = widget.value;
      _controller.value = 1.0;
      return;
    }
    // 从当前插值继续滚动，动画被打断也不跳变
    _from = _displayed;
    _to = widget.value;
    if (Motion.reduceMotion || widget.duration == Duration.zero) {
      _controller.value = 1.0;
    } else {
      _controller.forward(from: 0);
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
      builder: (context, _) {
        final text = _format(_displayed);
        if (text != _lastText) {
          _lastText = text;
          _cachedText = Text(text, style: widget.style);
        }
        return _cachedText!;
      },
    );
  }
}

// ============================================================================
// ④ SkeletonLoader —— 加载骨架（脉冲 + 高光扫过）
// ============================================================================

/// 加载骨架：圆角占位块 + 低频明暗脉冲 + 高光扫过
///
/// - 脉冲只做 opacity（0.55 ↔ 1.0），单块无重绘压力，成片也稳定 60fps；
/// - 高光：一条白色渐变带周期性左→右扫过（[MotionTokens.skeletonSweep]），
///   只做 paint 平移（FractionalTranslation，不重布局），ClipRRect 裁到块内；
/// - 多行时末行默认 60% 宽，模拟文本收尾（[lastLineFactor] 可调，传 null 等宽）；
/// - 底色默认随明暗主题取 borderLight / borderDark；
/// - reduceMotion 开启时脉冲与高光全部静止（固定 55% 透明度的静态骨架）。
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
    with TickerProviderStateMixin {
  /// 明暗脉冲（opacity 0.55 ↔ 1.0）
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: MotionTokens.skeletonPulse,
  );
  late final CurvedAnimation _pulseFade = CurvedAnimation(
    parent: _pulse,
    curve: Curves.easeInOut,
  );

  /// 高光扫过（paint 平移，线性匀速更像"光掠过"）
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: MotionTokens.skeletonSweep,
  );

  /// 高光带（宽度 55%，两端透明渐变）
  static final Widget _highlightBand = DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.45),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ),
    ),
  );

  void _syncAnimations() {
    // 设置页切换 reduceMotion 时跟随
    if (Motion.reduceMotion) {
      if (_pulse.isAnimating) _pulse.stop();
      if (_sweep.isAnimating) _sweep.stop();
    } else {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
      if (!_sweep.isAnimating) _sweep.repeat();
    }
  }

  @override
  void initState() {
    super.initState();
    _syncAnimations();
  }

  @override
  void didUpdateWidget(covariant SkeletonLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimations();
  }

  @override
  void dispose() {
    _pulseFade.dispose();
    _pulse.dispose();
    _sweep.dispose();
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
    final reduce = Motion.reduceMotion;

    Widget block({double? widthFactor}) {
      final content = Container(
        height: widget.height,
        decoration: BoxDecoration(color: base, borderRadius: radius),
      );
      // reduceMotion：静态骨架（沿用既有 55% 透明度），无任何动画层
      final Widget core = reduce
          ? Opacity(opacity: 0.55, child: content)
          : FadeTransition(opacity: _pulseFade, child: content);

      Widget layered = core;
      if (!reduce) {
        // 高光扫过：paint 平移（FractionalTranslation），ClipRRect 裁进块内。
        // 行程按"带自宽"计：-1.15（完全在左外）→ +1.85（完全在右外）。
        layered = ClipRRect(
          borderRadius: radius,
          child: Stack(
            children: [
              core,
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _sweep,
                  builder: (context, child) => FractionalTranslation(
                    translation: Offset(-1.15 + 3.0 * _sweep.value, 0),
                    child: child!,
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 0.55,
                    heightFactor: 1.0,
                    alignment: Alignment.centerLeft,
                    child: _highlightBand,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      if (widthFactor == null) return layered;
      return FractionallySizedBox(
        widthFactor: widthFactor,
        alignment: Alignment.centerLeft,
        child: layered,
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
/// - 延迟用可取消 [Timer] 承载，卸载即取消（不持有跨生命周期的回调）；
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
  Timer? _delayTimer;

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
      _delayTimer = Timer(_startDelay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _delayTimer = null;
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

// ============================================================================
// ⑥ CardEntrance —— 卡片悬浮入场
// ============================================================================

/// 卡片悬浮入场：淡入 + 上浮（4%）+ 微缩放（[fromScale] → 1.0）
///
/// 比 [StaggerIn] 多一维缩放，"卡片浮上来落位"的层次感更强；
/// 适合面板内成组卡片的首次呈现。
///
/// - 延迟用 `Interval` 曲线在控制器时间轴内实现——**零 Timer**，
///   不存在跨生命周期的回调，卸载即随控制器释放；
/// - 只驱动 opacity / transform（GPU 合成层），不触发重布局；
/// - reduceMotion 开启时直接呈现。
class CardEntrance extends StatefulWidget {
  const CardEntrance({
    super.key,
    required this.child,
    this.duration = MotionTokens.cardEntrance,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 0.04),
    this.fromScale = 0.98,
  });

  final Widget child;

  /// 入场时长（不含延迟）
  final Duration duration;

  /// 起始延迟（Interval 实现，非 Timer）
  final Duration delay;

  /// 入场位移（画幅比例；默认上浮 4%）
  final Offset offset;

  /// 起始缩放（默认 0.98，克制）
  final double fromScale;

  @override
  State<CardEntrance> createState() => _CardEntranceState();
}

class _CardEntranceState extends State<CardEntrance>
    with SingleTickerProviderStateMixin {
  Duration get _total => widget.delay + widget.duration;

  double get _delayFraction {
    final totalUs = _total.inMicroseconds;
    if (totalUs <= 0) return 0.0;
    return (widget.delay.inMicroseconds / totalUs).clamp(0.0, 1.0);
  }

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _total,
    value: Motion.reduceMotion ? 1.0 : 0.0,
  );

  /// 延迟段由 Interval 前段（值恒 0）承担，随后走 standard 缓出
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: _controller,
    curve: Interval(_delayFraction, 1.0, curve: MotionTokens.standard),
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
    if (Motion.reduceMotion) return widget.child;
    return FadeTransition(
      opacity: _curved,
      child: ScaleTransition(
        scale:
            Tween<double>(begin: widget.fromScale, end: 1.0).animate(_curved),
        child: SlideTransition(
          position:
              Tween<Offset>(begin: widget.offset, end: Offset.zero)
                  .animate(_curved),
          child: widget.child,
        ),
      ),
    );
  }
}

// ============================================================================
// ⑦ MotionSwitcher —— 区块淡入切换（AnimatedSwitcher 令牌化封装）
// ============================================================================

/// 区块淡入切换：child 变化时旧块淡出（exit 曲线）、新块淡入 + 微位移
/// （standard 曲线），时长/曲线全部取自 [MotionTokens]
///
/// ```dart
/// MotionSwitcher(
///   child: KeyedSubtree(key: ValueKey(currentIndex), child: page),
/// )
/// ```
///
/// - child 必须携带不同 key（如 `KeyedSubtree(key: ValueKey(...))`）才会触发切换；
/// - reduceMotion 开启时直接呈现新 child（无交叉过渡）。
class MotionSwitcher extends StatelessWidget {
  const MotionSwitcher({
    super.key,
    required this.child,
    this.duration = MotionTokens.normal,
    this.offset = const Offset(0, 0.03),
  });

  /// 切换内容（需带 key）
  final Widget child;

  /// 切换时长（默认 standard 300ms）
  final Duration duration;

  /// 新块入场位移（画幅比例；默认上浮 3%）
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    // 无障碍：减少动画 → 无交叉过渡，直接呈现
    if (Motion.reduceMotion) return child;
    return AnimatedSwitcher(
      duration: Motion.durationOrZero(duration),
      switchInCurve: MotionTokens.standard,
      switchOutCurve: MotionTokens.exit,
      transitionBuilder: (child, animation) => _DrivenFadeSlide(
        animation: animation,
        offset: offset,
        child: child,
      ),
      child: child,
    );
  }
}
