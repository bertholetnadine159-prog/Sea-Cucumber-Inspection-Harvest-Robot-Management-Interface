/// 遥测数据卡片（图标 + 标题 + 数值 + 单位 + 可选信号丢失徽标）
///
/// 设计约定（契约§7 数据真实回传）：
/// - [value] 必须来自真实链路数据；无源时传 null，卡片显示"--"；
/// - [lastUpdated] 用于驱动 [StaleBadge]：断链时徽标出现且数值冻结
///   （由调用方冻结数值，卡片本身不做合成/兜底）。
///
/// 视觉按旧版（1cc31e5）状态卡语言还原（STYLE_SPEC §8.1/§6.3）：
/// 白底圆角 16 + 1px borderLight 描边 + 标准投影（black 2% / blur 8 / (0,2)），
/// 48×48 圆形图标 tile（图标色 10% 底）+ caption 标签 + dataMedium 数值 + dataUnit 单位。
library;

import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import 'stale_badge.dart';

/// 遥测卡片
class TelemetryCard extends StatelessWidget {
  /// 卡片标题（如"深度"）
  final String title;

  /// 数值字符串（真实数据；null 显示 "--"）
  final String? value;

  /// 单位（如 m / °C / V）
  final String? unit;

  /// 左侧图标
  final IconData icon;

  /// 数据最后更新时刻（驱动信号丢失徽标）
  final DateTime? lastUpdated;

  /// 断链判定阈值
  final Duration staleThreshold;

  /// 数值高亮色（默认主题文字色；可传 AppColors.warning 等强调）
  final Color? valueColor;

  /// 点击回调（可选，如跳转详情）
  final VoidCallback? onTap;

  /// 卡片最小宽度（响应式网格中使用）
  final double? minWidth;

  const TelemetryCard({
    super.key,
    required this.title,
    required this.icon,
    this.value,
    this.unit,
    this.lastUpdated,
    this.staleThreshold = const Duration(seconds: 5),
    this.valueColor,
    this.onTap,
    this.minWidth,
  });

  @override
  Widget build(BuildContext context) {
    final stale = StaleBadge.isStale(lastUpdated, threshold: staleThreshold);
    final accent = stale ? AppColors.warning : (valueColor ?? AppColors.primary);

    Widget card = Container(
      constraints: minWidth != null
          ? BoxConstraints(minWidth: minWidth!)
          : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        border: Border.all(
          color: stale
              ? AppColors.warning.withValues(alpha: 0.5)
              : AppColors.borderLight,
          width: 1,
        ),
        // 旧版标准卡片投影：black 2% / blur 8 / offset (0,2)
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 旧版 48×48 圆形图标 tile：图标色 10% 底
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 22, color: accent),
          ),
          const SizedBox(width: 16),
          // 标题 + 数值（断链时数值由调用方冻结，此处降低透明度提示）
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondaryLight,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    StaleBadge(
                        lastUpdated: lastUpdated, staleThreshold: staleThreshold),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      value ?? '--',
                      style: AppTextStyles.withColor(
                        AppTextStyles.dataMedium,
                        stale
                            ? (valueColor ?? AppColors.textPrimaryLight)
                                .withValues(alpha: 0.55)
                            : (valueColor ?? AppColors.textPrimaryLight),
                      ),
                    ),
                    if (unit != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        unit!,
                        style: AppTextStyles.dataUnit,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      card = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        child: card,
      );
    }
    return card;
  }
}
