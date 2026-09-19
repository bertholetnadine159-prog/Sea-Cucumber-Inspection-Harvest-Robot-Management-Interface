/// 通用状态徽标（成功/警告/危险/信息/中性）
///
/// 用于连接状态、模式指示、系统健康度等小尺寸状态展示。
library;

import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// 状态等级
enum AppStatusLevel {
  /// 正常/在线（绿色）
  success,

  /// 警告/降级（黄色）
  warning,

  /// 危险/离线（红色）
  danger,

  /// 信息/主色（蓝色）
  info,

  /// 中性（灰色）
  neutral,
}

/// 状态徽标：圆角药丸 + 圆点 + 文案
class StatusBadge extends StatelessWidget {
  final String text;
  final AppStatusLevel level;
  final double fontSize;

  const StatusBadge({
    super.key,
    required this.text,
    this.level = AppStatusLevel.neutral,
    this.fontSize = 12,
  });

  Color get _color {
    switch (level) {
      case AppStatusLevel.success:
        return AppColors.success;
      case AppStatusLevel.warning:
        return AppColors.warning;
      case AppStatusLevel.danger:
        return AppColors.danger;
      case AppStatusLevel.info:
        return AppColors.primary;
      case AppStatusLevel.neutral:
        return AppColors.textSecondaryLight;
    }
  }

  /// 常用语义快捷构造：已连接
  factory StatusBadge.online({String text = '已连接'}) =>
      StatusBadge(text: text, level: AppStatusLevel.success);

  /// 常用语义快捷构造：重连中
  factory StatusBadge.reconnecting({String text = '重连中'}) =>
      StatusBadge(text: text, level: AppStatusLevel.warning);

  /// 常用语义快捷构造：离线
  factory StatusBadge.offline({String text = '离线'}) =>
      StatusBadge(text: text, level: AppStatusLevel.danger);

  @override
  Widget build(BuildContext context) {
    final color = _color;
    // 旧版芯片语言（STYLE_SPEC §7.6）：圆角 8 描边芯片，10% 同色底 + 全色描边
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: fontSize * 0.55,
            height: fontSize * 0.55,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: AppTextStyles.withColor(
              AppTextStyles.label.copyWith(fontSize: fontSize),
              color,
            ),
          ),
        ],
      ),
    );
  }
}
