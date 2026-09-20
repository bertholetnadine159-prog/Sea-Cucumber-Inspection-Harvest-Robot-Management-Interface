/// 悬浮急停球（Emergency Orb）
///
/// 一键触达的全局急停入口，挂在仪表盘 shell 顶层（app.dart 的 DashboardRouter），
/// 登录页路由不挂载：
///
/// - **外观**：警示红渐变球体 + 白色急停图标（沿用 STYLE_SPEC §7.1 急停的
///   "红底白 close"图例）+ 低频呼吸光晕；
/// - **位置**：默认停靠屏幕右缘垂直居中（避开 operate 页居中大胶囊、
///   主控页底部急停条等既有急停按钮，不遮挡它们）；可拖动，松手自动
///   吸附最近的左右边缘（贴边换位），纵向位置保持；
/// - **交互（误触防护）**：按住充能约 500ms 进度环，充满**立即**直发
///   emergencyStop（免确认对话框 = 更快触达）；未充满松手即取消；
///   按住后拖动（超过抖动阈值）同样取消充能——拖动不是触发意图；
/// - **触发瞬间**：全屏红色闪场 + 重触感反馈 + SnackBar；发送成功报
///   「已急停」，未连接/通道不可用（服务层 `_send` 返回 false，命令没有
///   发出）时如实报「急停未发出」，绝不无条件报成功；
/// - **动效**：全部走 Motion Kit 令牌（docs/STYLE_SPEC.md §9，克制基调）；
///   reduceMotion 开启时：呼吸光晕静止、闪场与贴边动画时长归零、按压
///   轻触感关闭；充能环是**功能性误触防护**，500ms 按住时长保留
///   （仅去掉缓动曲线），触发的重触感保留（安全确认）。
///
/// 本组件不绑定、不产生任何业务数据（铁律②）：命令沿既有
/// `RovBackendService().emergencyStop()` 真实链路下发，发送失败必须提示。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/rov_backend_service.dart';
import '../../../core/services/settings_provider.dart';
import '../../../core/theme/app_colors.dart';
import 'motion_kit.dart';

/// 悬浮急停球：仪表盘 shell 级 overlay
class EmergencyOrb extends StatefulWidget {
  const EmergencyOrb({super.key});

  @override
  State<EmergencyOrb> createState() => _EmergencyOrbState();
}

class _EmergencyOrbState extends State<EmergencyOrb>
    with TickerProviderStateMixin {
  // ---- 布局常量 ----

  /// 触摸热区边长（含充能环外圈，比球体大一圈提升按中率）
  static const double _hitSize = 64;

  /// 球体直径
  static const double _orbSize = 56;

  /// 贴边吸附后距屏幕边缘的间距
  static const double _edgeMargin = 10;

  /// 拖动可活动范围的屏幕留白
  static const double _boundsMargin = 4;

  /// 按住位移超过此值判定为拖动（并取消充能）
  static const double _dragSlop = 12;

  // ---- 动效令牌（STYLE_SPEC §9） ----

  /// 充能时长：按住约 500ms 充满即触发（功能性误触防护，
  /// reduceMotion 也保留时长，仅去缓动）
  static const Duration _chargeDuration = Duration(milliseconds: 500);

  /// 呼吸光晕周期（reduceMotion 时静止）
  static const Duration _breatheDuration = Duration(milliseconds: 1600);

  /// 红色闪场时长：峰值后自然衰减（reduceMotion 时长归零 = 不闪）
  static const Duration _flashDuration = Duration(milliseconds: 450);

  // ---- 可释放资源（铁律⑤：全部在 dispose 释放） ----

  /// 呼吸光晕：低频往复，只驱动阴影参数（重绘级，不动布局）
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: _breatheDuration,
  );

  /// 充能环进度：按住充能，充满触发，松手回退
  late final AnimationController _charge = AnimationController(
    vsync: this,
    duration: _chargeDuration,
  );

  /// 充能缓动（reduceMotion 时绕过，见 [_chargeValue]）
  late final CurvedAnimation _chargeCurve =
      CurvedAnimation(parent: _charge, curve: MotionTokens.standard);

  /// 红色闪场：静止时值为 1（不透明度 0），触发时 forward(0→1) 呈衰减闪场
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: _flashDuration,
    value: 1.0,
  );

  /// reduceMotion 开关实时跟随（设置页切换无需等整树重建）
  final SettingsProvider _settings = SettingsProvider();

  // ---- 手势状态 ----

  /// 球体热区左上角（shell 坐标）；null 表示尚未按屏幕尺寸初始化
  Offset? _pos;

  /// 最近一次 shell 布局尺寸（拖动松手时吸附计算用）
  Size _shellSize = Size.zero;
  bool _dragging = false;
  bool _fired = false;
  int? _activePointer;
  Offset _pressOrigin = Offset.zero;
  Offset _lastPointer = Offset.zero;

  @override
  void initState() {
    super.initState();
    _charge.addStatusListener(_onChargeStatus);
    _settings.addListener(_onSettingsChanged);
    _syncBreathe();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _charge.removeStatusListener(_onChargeStatus);
    _chargeCurve.dispose();
    _charge.dispose();
    _breathe.dispose();
    _flash.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    _syncBreathe();
    setState(() {}); // reduceMotion 切换即时生效（光晕/闪场/缓动）
  }

  /// 呼吸光晕随 reduceMotion 启停（开启时静止于基础光晕）
  void _syncBreathe() {
    if (Motion.reduceMotion) {
      if (_breathe.isAnimating) {
        _breathe
          ..stop()
          ..value = 0;
      }
    } else if (!_breathe.isAnimating) {
      _breathe.repeat(reverse: true);
    }
  }

  /// 充满即触发（免确认对话框 = 更快触达）
  void _onChargeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _fireStop();
  }

  /// 充能环当前进度（reduceMotion 时去缓动，仅保留功能性时长）
  double get _chargeValue =>
      Motion.reduceMotion ? _charge.value : _chargeCurve.value;

  // ---------------------------------------------------------------------------
  // 触发急停：真实 emergencyStop 链路（对齐 operate 页的失败提示约定）
  // ---------------------------------------------------------------------------

  void _fireStop() {
    if (!mounted || _fired) return;
    _fired = true;
    _charge
      ..stop()
      ..value = 0;
    // 触发瞬间重触感（安全确认，不受 reduceMotion 限制）
    HapticFeedback.heavyImpact();
    // 全屏红色闪场（reduceMotion 时时长归零，直接归于平静）
    _flash
      ..duration = Motion.durationOrZero(_flashDuration)
      ..forward(from: 0);
    // 真实链路：emergencyStop 返回命令是否已交由活动通道发送。
    // 未连接/通道不可用时消息不会发出（服务层不再静默丢弃），此时若仍报
    // "已急停"，操作者会误以为急停已下发——必须如实区分两种结果。
    final sent = RovBackendService().emergencyStop();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(sent ? '已急停' : '急停未发出：后端未连接，请检查连接后重试'),
        backgroundColor: AppColors.error,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 指针交互：按下充能 / 位移转拖拽 / 松手吸附
  // ---------------------------------------------------------------------------

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return; // 已有手指操作中，忽略第二指
    _activePointer = event.pointer;
    _pressOrigin = event.position;
    _fired = false;
    if (!Motion.reduceMotion) HapticFeedback.selectionClick();
    _charge
      ..duration = _chargeDuration
      ..forward(from: 0);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer || _fired) return;
    if (_dragging) {
      final delta = event.position - _lastPointer;
      _lastPointer = event.position;
      setState(() {
        _pos = _clamp((_pos ?? Offset.zero) + delta, _shellSize);
      });
      return;
    }
    if ((event.position - _pressOrigin).distance > _dragSlop) {
      // 转为拖动：充能立即取消（拖动 ≠ 触发意图）
      _charge
        ..stop()
        ..value = 0;
      _dragging = true;
      _lastPointer = event.position;
      if (!Motion.reduceMotion) HapticFeedback.selectionClick();
      setState(() {});
    }
  }

  void _onPointerUp(PointerUpEvent event) => _endPointer(event.pointer);

  void _onPointerCancel(PointerCancelEvent event) => _endPointer(event.pointer);

  void _endPointer(int pointer) {
    if (pointer != _activePointer) return;
    _activePointer = null;
    if (_dragging) {
      _dragging = false;
      _snapToNearestEdge();
      return;
    }
    if (!_fired) {
      // 未充满松手 → 取消充能（快速回退）
      _charge
        ..duration = MotionTokens.fast
        ..reverse();
    }
  }

  /// 吸附最近的左右边缘（贴边换位），纵向位置保持
  void _snapToNearestEdge() {
    final size = _shellSize;
    final current = _pos;
    if (size == Size.zero || current == null) return;
    final centerX = current.dx + _hitSize / 2;
    final targetX = centerX < size.width / 2
        ? _edgeMargin
        : size.width - _hitSize - _edgeMargin;
    setState(() {
      _pos = Offset(math.max(_boundsMargin, targetX), current.dy);
    });
  }

  // ---------------------------------------------------------------------------
  // 布局与外观
  // ---------------------------------------------------------------------------

  /// 将热区左上角限制在屏幕内
  Offset _clamp(Offset p, Size size) {
    final maxX = math.max(_boundsMargin, size.width - _hitSize - _boundsMargin);
    final maxY = math.max(_boundsMargin, size.height - _hitSize - _boundsMargin);
    return Offset(
      p.dx.clamp(_boundsMargin, maxX).toDouble(),
      p.dy.clamp(_boundsMargin, maxY).toDouble(),
    );
  }

  /// 默认停靠位：屏幕右缘垂直居中
  Offset _defaultPos(Size size) => Offset(
        size.width - _hitSize - _edgeMargin,
        (size.height - _hitSize) / 2,
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        _shellSize = size;
        // 首帧初始化默认停靠位；窗口尺寸变化后保持球体在屏内
        _pos = _clamp(_pos ?? _defaultPos(size), size);

        return Stack(
          children: [
            // ① 触发瞬间全屏红色闪场（不拦截任何指针）
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _flash,
                  builder: (context, _) {
                    if (_flash.value >= 1) return const SizedBox.shrink();
                    final t = Motion.reduceMotion
                        ? _flash.value
                        : Curves.easeOutCubic.transform(_flash.value);
                    return Opacity(
                      opacity: 0.30 * (1 - t),
                      child: const ColoredBox(color: AppColors.error),
                    );
                  },
                ),
              ),
            ),
            // ② 悬浮急停球（拖拽中实时跟手，松手吸附带 motion_kit 缓动）
            AnimatedPositioned(
              duration: _dragging
                  ? Duration.zero
                  : Motion.durationOrZero(MotionTokens.normal),
              curve: MotionTokens.standard,
              left: _pos!.dx,
              top: _pos!.dy,
              child: _buildOrb(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOrb() {
    return Semantics(
      button: true,
      label: '悬浮急停：按住约半秒充能后立即下发紧急停止',
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: AnimatedBuilder(
          // 只重建热区内部（呼吸光晕 + 充能环），不惊动外层布局
          animation: Listenable.merge([_breathe, _charge]),
          builder: (context, _) {
            final breathe = Motion.reduceMotion ? 0.0 : _breathe.value;
            return Container(
              width: _hitSize,
              height: _hitSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  // 呼吸光晕：只动阴影（重绘级），不动布局
                  BoxShadow(
                    color:
                        AppColors.error.withValues(alpha: 0.30 + 0.25 * breathe),
                    blurRadius: 14 + 10 * breathe,
                    spreadRadius: 1 + 2 * breathe,
                  ),
                ],
              ),
              child: PressableScale(
                // 触感由充能起点/触发瞬间统一给出，避免双重反馈
                hapticFeedback: false,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 警示红渐变球体 + 白色急停图标
                    Container(
                      width: _orbSize,
                      height: _orbSize,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          center: const Alignment(-0.3, -0.4),
                          colors: [
                            Color.lerp(AppColors.error, Colors.white, 0.22)!,
                            AppColors.error,
                            Color.lerp(AppColors.error, Colors.black, 0.15)!,
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.55),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    // 充能进度环（误触防护：按住约 500ms 充满即触发）
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ChargeRingPainter(progress: _chargeValue),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 充能进度环：淡白轨道 + 白色进度弧（自 12 点方向顺时针充满）
class _ChargeRingPainter extends CustomPainter {
  _ChargeRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.0;
    final rect = (Offset.zero & size).deflate(stroke);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white.withValues(alpha: 0.28);
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    if (progress <= 0) return;
    final sweep = progress.clamp(0.0, 1.0).toDouble() * math.pi * 2;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc);
  }

  @override
  bool shouldRepaint(_ChargeRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
