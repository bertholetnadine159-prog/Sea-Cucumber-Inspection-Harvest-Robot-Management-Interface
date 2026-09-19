/// 应用深海背景组件（本地资产，离线可用）
///
/// 背景图由 `tools/make_login_bg.py` 程序化生成
/// （assets/images/login_bg.png，1920×1080 深海渐变+波浪光斑）。
///
/// Wave 2 迁移提示：登录页/忘记密码页当前使用
/// `AppConstants.underwaterBgUrl`（远程 URL，离线破图），迁移时将
/// `CachedNetworkImage` 替换为本组件即可。
library;

import 'package:flutter/material.dart';

/// 深海背景 + 暗化遮罩
class AppBackground extends StatelessWidget {
  /// 背景图资产路径
  final String assetPath;

  /// 遮罩不透明度（0~1），用于保证前景文字对比度
  final double scrimOpacity;

  /// 遮罩渐变（默认自上而下加深）
  final Gradient? scrimGradient;

  /// 前景内容
  final Widget? child;

  const AppBackground({
    super.key,
    this.assetPath = 'assets/images/login_bg.png',
    this.scrimOpacity = 0.45,
    this.scrimGradient,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = scrimGradient ??
        LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: scrimOpacity * 0.7),
            Colors.black.withValues(alpha: scrimOpacity),
            Colors.black.withValues(alpha: scrimOpacity * 1.2 > 1.0
                ? 1.0
                : scrimOpacity * 1.2),
          ],
        );

    return Stack(
      fit: StackFit.expand,
      children: [
        // 深海渐变底（图片加载失败时的兜底视觉，非数据兜底）
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0B1F3A), Color(0xFF061527)],
            ),
          ),
        ),
        // 本地背景图（程序化生成，离线可用）
        Image.asset(
          assetPath,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        // 暗化遮罩：保证白色前景文字的 WCAG AA 对比度
        DecoratedBox(
          decoration: BoxDecoration(gradient: gradient),
        ),
        ?child,
      ],
    );
  }
}
