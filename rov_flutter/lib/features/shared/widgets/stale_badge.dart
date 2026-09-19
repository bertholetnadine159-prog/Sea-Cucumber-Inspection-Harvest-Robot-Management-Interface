/// 信号丢失徽标（契约§6：数据断链时的"冻结最后真实值"提示）
///
/// 规则：
/// - `lastUpdated` 距今超过 [staleThreshold]（默认 5 秒）→ 显示"⚠ 信号丢失"；
/// - 数据恢复（lastUpdated 刷新）→ 徽标自动消失；
/// - `lastUpdated == null` 视为从未收到数据，同样显示信号丢失。
///
/// 内部使用 1 秒周期的 Timer 自查，无需外部驱动；组件卸载时自动取消。
///
/// 动效（对外 API 不变，仅加动画曲线）：徽标出现时 150ms 淡入 + 轻微下沉，
/// 数据恢复时淡出后收起；reduceMotion 开启时直接出现/消失。
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/settings_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import 'motion_kit.dart';

/// 信号丢失徽标
class StaleBadge extends StatefulWidget {
  /// 数据最后更新时刻（null = 从未收到数据）
  final DateTime? lastUpdated;

  /// 超时阈值，默认 5 秒
  final Duration staleThreshold;

  /// 超时显示文案
  final String staleText;

  /// 徽标字号缩放（适配卡片/页面两种尺寸场景）
  final double fontSize;

  const StaleBadge({
    super.key,
    required this.lastUpdated,
    this.staleThreshold = const Duration(seconds: 5),
    this.staleText = '⚠ 信号丢失',
    this.fontSize = 12,
  });

  /// 判定当前是否处于断链状态
  static bool isStale(DateTime? lastUpdated,
      {Duration threshold = const Duration(seconds: 5)}) {
    if (lastUpdated == null) return true;
    return DateTime.now().difference(lastUpdated) > threshold;
  }

  @override
  State<StaleBadge> createState() => _StaleBadgeState();
}

class _StaleBadgeState extends State<StaleBadge>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  bool _stale = false;

  /// 出现/消失动画（150ms，与 motion kit 令牌一致；不改变对外 API）
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: AppConstants.animationFast,
    value: 0,
  );
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: _anim,
    curve: MotionTokens.standard,
    reverseCurve: MotionTokens.exit,
  );

  @override
  void initState() {
    super.initState();
    _evaluate();
    // 每秒自查一次年龄，超时出现/恢复消失
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _evaluate());
  }

  @override
  void didUpdateWidget(covariant StaleBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部数据刷新时立即评估，避免等待下一个秒周期
    _evaluate();
  }

  void _evaluate() {
    final stale = StaleBadge.isStale(widget.lastUpdated,
        threshold: widget.staleThreshold);
    if (stale != _stale && mounted) {
      setState(() => _stale = stale);
      if (SettingsProvider().reduceMotion) {
        _anim.value = stale ? 1.0 : 0.0;
      } else {
        stale ? _anim.forward() : _anim.reverse();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _curved.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 数据新鲜且退场动画已结束时，不渲染任何内容（自动消失）；
    // 退场淡出期间仍短暂保留占位，避免文字跳行。
    final visible = _stale || _anim.status == AnimationStatus.reverse;
    if (!visible) return const SizedBox.shrink();

    // 旧版芯片语言（STYLE_SPEC §7.6 RDK 状态条）：10% 同色底 + 全色描边圆角 8
    return FadeTransition(
      opacity: _curved,
      child: SlideTransition(
        // 徽标高度约 20px → 15% ≈ 3px 下沉入场，克制提示不抢焦点
        position: Tween<Offset>(
          begin: const Offset(0, 0.15),
          end: Offset.zero,
        ).animate(_curved),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: widget.fontSize * 0.7,
            vertical: widget.fontSize * 0.35,
          ),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(color: AppColors.warning, width: 1),
          ),
          child: Text(
            widget.staleText,
            style: AppTextStyles.withColor(
              AppTextStyles.label.copyWith(fontSize: widget.fontSize),
              AppColors.warning,
            ),
          ),
        ),
      ),
    );
  }
}
