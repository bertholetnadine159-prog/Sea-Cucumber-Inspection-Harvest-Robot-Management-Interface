/// 危险操作确认对话框（红色变体）
///
/// 用法：
/// ```dart
/// final ok = await ConfirmDialog.show(
///   context,
///   title: '紧急停止',
///   message: '确认立即停止全部推进器？',
///   confirmText: '确认停止',
/// );
/// if (ok) { ... }
/// ```
library;

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// 危险操作确认对话框
class ConfirmDialog extends StatelessWidget {
  /// 对话框标题
  final String title;

  /// 正文说明（解释后果）
  final String message;

  /// 确认按钮文案
  final String confirmText;

  /// 取消按钮文案
  final String cancelText;

  /// 是否危险操作（红色确认按钮）；false 时确认按钮用主色
  final bool danger;

  /// 确认按钮图标（可选，如 Icons.warning_amber_rounded）
  final IconData? confirmIcon;

  const ConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmText = '确认',
    this.cancelText = '取消',
    this.danger = true,
    this.confirmIcon,
  });

  /// 静态弹出，返回 true 表示用户确认
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = '确认',
    String cancelText = '取消',
    bool danger = true,
    IconData? confirmIcon,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // 危险操作需显式选择，避免误触关闭
      builder: (_) => ConfirmDialog(
        title: title,
        message: message,
        confirmText: confirmText,
        cancelText: cancelText,
        danger: danger,
        confirmIcon: confirmIcon,
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final actionColor = danger ? AppColors.danger : AppColors.primary;

    return AlertDialog(
      backgroundColor: AppColors.surfaceLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: danger
              ? AppColors.danger.withValues(alpha: 0.4)
              : AppColors.borderLight,
          width: 1,
        ),
      ),
      title: Row(
        children: [
          if (confirmIcon != null) ...[
            Icon(confirmIcon, color: actionColor, size: 24),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.withColor(
                AppTextStyles.h3,
                danger ? AppColors.danger : AppColors.textPrimaryLight,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: AppTextStyles.bodyMedium,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondaryLight,
            minimumSize: const Size(64, 44), // 触控目标 ≥44px
          ),
          child: Text(cancelText),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: actionColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(88, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(confirmText),
        ),
      ],
    );
  }
}
