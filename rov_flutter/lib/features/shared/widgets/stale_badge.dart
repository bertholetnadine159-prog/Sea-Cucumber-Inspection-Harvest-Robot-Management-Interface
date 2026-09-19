/// 信号丢失徽标（契约§6：数据断链时的"冻结最后真实值"提示）
///
/// 规则：
/// - `lastUpdated` 距今超过 [staleThreshold]（默认 5 秒）→ 显示"⚠ 信号丢失"；
/// - 数据恢复（lastUpdated 刷新）→ 徽标自动消失；
/// - `lastUpdated == null` 视为从未收到数据，同样显示信号丢失。
///
/// 内部使用 1 秒周期的 Timer 自查，无需外部驱动；组件卸载时自动取消。
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

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

class _StaleBadgeState extends State<StaleBadge> {
  Timer? _timer;
  bool _stale = false;

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
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 数据新鲜时不渲染任何内容（自动消失）
    if (!_stale) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.fontSize * 0.6,
        vertical: widget.fontSize * 0.35,
      ),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(widget.fontSize * 0.7),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: Text(
        widget.staleText,
        style: AppTextStyles.withColor(
          AppTextStyles.label.copyWith(fontSize: widget.fontSize),
          AppColors.warning,
        ),
      ),
    );
  }
}
