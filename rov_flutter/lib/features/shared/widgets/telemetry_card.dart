/// 遥测数据卡片（图标 + 标题 + 数值 + 单位 + 可选信号丢失徽标）
///
/// 设计约定（契约§7 数据真实回传）：
/// - [value] 必须来自真实链路数据；无源时传 null，卡片显示"--"；
/// - [lastUpdated] 用于驱动 [StaleBadge]：断链时徽标出现且数值冻结
///   （由调用方冻结数值，卡片本身不做合成/兜底）。
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

    Widget card = Container(
      constraints: minWidth != null
          ? BoxConstraints(minWidth: minWidth!)
          : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
          color: stale
              ? AppColors.warning.withValues(alpha: 0.5)
              : AppColors.borderLight,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题行：图标 + 标题 + 右侧信号丢失徽标
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: stale ? AppColors.warning : AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.label,
                ),
              ),
              StaleBadge(lastUpdated: lastUpdated, staleThreshold: staleThreshold),
            ],
          ),
          const SizedBox(height: 10),
          // 数值行：数值 + 单位（断链时数值由调用方冻结，此处降低透明度提示）
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
    );

    if (onTap != null) {
      card = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: card,
      );
    }
    return card;
  }
}
