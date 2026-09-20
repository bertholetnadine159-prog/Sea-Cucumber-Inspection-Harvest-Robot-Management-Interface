import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';
import '../../features/shared/widgets/app_background.dart';
import '../shared/widgets/motion_kit.dart';

/// 管理员联系方式（占位常量：部署时由运营方填写真实电话/邮箱/工单入口）
const String kAdminContact = '管理员联系方式：电话 0000-000000 / 邮箱 admin@example.com';

/// 忘记密码页面
/// 桌面端忘记密码界面：本系统无邮件自助重置通道（原"发送重置链接"为
/// 无真实后端的假交互，已删除），改为如实提示联系管理员重置密码。
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        // 旧版艺术背景（login_bg_original.jpg 本地资产，离线可用）
        // + 旧版遮罩：backgroundDark @ 20% + BackdropFilter blur 2（§4/§5.1）
        scrimOpacity: 0.20,
        child: Stack(
          children: [
            // 主体内容
            _buildContent(),
            // 底部版权
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  /// 构建主体内容
  Widget _buildContent() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        // 动效工具箱：卡片首次挂载 淡入+微位移上浮（reduceMotion 直接呈现）
        child: AppPageTransition(child: _buildCard()),
      ),
    );
  }

  /// 构建忘记密码卡片
  Widget _buildCard() {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth - 48).clamp(280.0, 480.0);
    final horizontalPadding = screenWidth < 420 ? 24.0 : 48.0;
    final verticalPadding = screenWidth < 420 ? 32.0 : 48.0;

    return SizedBox(
      width: cardWidth,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: cardWidth,
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            decoration: BoxDecoration(
              color: AppColors.glassWhite,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 40,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                _buildLogo(),
                const SizedBox(height: 24),
                // 标题
                _buildTitle(),
                const SizedBox(height: 48),
                // 说明（旧版卡片节奏：标题后 48；内容为真实的
                // "联系管理员重置"提示，不还原旧版假发送表单）
                _buildNotice(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建Logo
  Widget _buildLogo() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(
        Icons.lock_reset,
        color: AppColors.primary,
        size: 36,
      ),
    );
  }

  /// 构建标题
  Widget _buildTitle() {
    return Column(
      children: [
        Text(
          '找回密码',
          style: AppTextStyles.h1.copyWith(
            color: AppColors.textPrimaryLight,
            letterSpacing: 4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'RESET PASSWORD',
          style: AppTextStyles.englishSubtitle.copyWith(
            letterSpacing: 4,
            color: AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }

  /// 构建说明区域（如实告知：无自助重置，请联系管理员）
  Widget _buildNotice() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '本系统暂不支持自助找回密码。为保障海上作业数据安全，'
          '密码重置由系统管理员在后台统一操作。',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondaryLight,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.support_agent, color: AppColors.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '请联系管理员重置密码',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textPrimaryLight,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      kAdminContact,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // 返回登录
        _buildBackToLoginButton(),
      ],
    );
  }

  /// 返回登录界面
  Widget _buildBackToLoginButton() {
    return Center(
      // 动效工具箱：按压缩放反馈（点击仍由 TextButton 处理）
      child: PressableScale(
        child: TextButton.icon(
          onPressed: () {
            Navigator.pop(context);
          },
          icon: const Icon(
            Icons.arrow_back,
            color: AppColors.primary,
            size: 16,
          ),
          label: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '返回登录',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(
                  text: ' (Back to Login)',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ),
    );
  }

  /// 构建底部版权
  Widget _buildFooter() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              AppConstants.copyright,
              style: AppTextStyles.caption.copyWith(
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '|',
                style: AppTextStyles.caption.copyWith(
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ),
            Text(
              AppConstants.version,
              style: AppTextStyles.timestamp.copyWith(
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
