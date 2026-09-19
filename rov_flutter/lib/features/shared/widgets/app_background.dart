/// 应用水下背景组件（旧版艺术还原）
///
/// 视觉还原自 1cc31e5 登录页 `_buildBackground/_buildOverlay`：
/// - 背景图：旧版 googleusercontent 原图（已本地化为
///   `assets/images/login_bg_original.jpg`，字节同源，离线可用），
///   BoxFit.cover 全屏；
/// - 占位：纯 `AppColors.backgroundDark` 色块；
/// - 加载失败兜底：`primary @ 80% → gradientEnd @ 80%` 左上→右下
///   线性渐变（旧版明确的降级艺术处理）；
/// - 全屏叠层：`backgroundDark @ scrimOpacity`（旧版 20%）+
///   `BackdropFilter(blur 2, 2)` 整页轻模糊，位于背景图之上、卡片之下。
///
/// 登录/忘记密码页（features/auth）以 `AppBackground(scrimOpacity: …, child: …)`
/// 方式使用，构造签名保持兼容。
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';

/// 水下背景 + 旧版遮罩/模糊
class AppBackground extends StatelessWidget {
  /// 背景图资产路径（默认旧版艺术图本地化资产）
  final String assetPath;

  /// 全屏暗化遮罩不透明度（0~1，旧版艺术为 0.20）
  final double scrimOpacity;

  /// 遮罩渐变（提供时替代纯色遮罩）
  final Gradient? scrimGradient;

  /// 前景内容
  final Widget? child;

  const AppBackground({
    super.key,
    this.assetPath = AppConstants.loginBgAsset,
    this.scrimOpacity = 0.20, // 旧版：backgroundDark @ 20%
    this.scrimGradient,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 占位：旧版 CachedNetworkImage placeholder = backgroundDark 色块
        const ColoredBox(color: AppColors.backgroundDark),
        // 旧版艺术图（本地化原图）；失败兜底 = 主色80%→紫80% 渐变
        Image.asset(
          assetPath,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xCC3B82F6), // primary @ 80%
                  Color(0xCC9370DB), // gradientEnd @ 80%
                ],
              ),
            ),
          ),
        ),
        // 旧版全屏叠层：backgroundDark @ scrimOpacity + BackdropFilter blur 2
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: scrimGradient,
              color: scrimGradient == null
                  ? AppColors.backgroundDark
                      .withValues(alpha: scrimOpacity.clamp(0.0, 1.0))
                  : null,
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        ?child,
      ],
    );
  }
}
