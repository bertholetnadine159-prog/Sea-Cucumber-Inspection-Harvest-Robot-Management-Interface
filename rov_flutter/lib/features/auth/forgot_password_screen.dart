import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';

/// 忘记密码页面
/// 桌面端忘记密码界面，包含毛玻璃效果卡片和水下背景
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// 处理发送重置链接
  Future<void> _handleResetPassword() async {
    setState(() => _isLoading = true);
    
    final email = _emailController.text.trim();
    
    // 模拟网络请求
    await Future.delayed(const Duration(seconds: 1));
    
    setState(() => _isLoading = false);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('重置链接已发送到 $email，请查收邮件'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 水下背景图
          _buildBackground(),
          // 蓝色遮罩层
          _buildOverlay(),
          // 主体内容
          _buildContent(),
          // 底部版权
          _buildFooter(),
        ],
      ),
    );
  }

  /// 构建背景图
  Widget _buildBackground() {
    return Positioned.fill(
      child: CachedNetworkImage(
        imageUrl: AppConstants.underwaterBgUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: AppColors.backgroundDark,
        ),
        errorWidget: (context, url, error) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withValues(alpha: 0.8),
                AppColors.gradientEnd.withValues(alpha: 0.8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建蓝色遮罩层
  Widget _buildOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.backgroundDark.withValues(alpha: 0.2),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  /// 构建主体内容
  Widget _buildContent() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _buildCard(),
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
                // 表单
                _buildForm(),
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

  /// 构建表单
  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '请输入您的注册邮箱，我们将向您发送密码重置链接。',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: 24),
        // 邮箱
        _buildLabel('邮箱地址', 'Email Address'),
        const SizedBox(height: 8),
        _buildEmailField(),
        const SizedBox(height: 32),
        // 发送按钮
        _buildSubmitButton(),
        const SizedBox(height: 24),
        // 返回登录
        _buildBackToLoginButton(),
      ],
    );
  }

  /// 构建标签
  Widget _buildLabel(String chinese, String english) {
    return Row(
      children: [
        Text(
          chinese,
          style: AppTextStyles.label.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondaryLight,
          ),
        ),
        Text(
          ' / ',
          style: AppTextStyles.label.copyWith(
            color: AppColors.textTertiaryLight,
          ),
        ),
        Text(
          english,
          style: AppTextStyles.englishSubtitle.copyWith(
            fontSize: 12,
            color: AppColors.textSecondaryLight,
          ),
        ),
      ],
    );
  }

  /// 构建邮箱输入框
  Widget _buildEmailField() {
    return TextField(
      controller: _emailController,
      decoration: InputDecoration(
        prefixIcon: const Icon(
          Icons.mail_outline,
          color: AppColors.textTertiaryLight,
        ),
        hintText: 'Enter your email address',
        hintStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textTertiaryLight,
        ),
        filled: true,
        fillColor: AppColors.backgroundLightAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  /// 构建发送按钮
  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleResetPassword,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          shadowColor: AppColors.primary.withValues(alpha: 0.3),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '发送重置链接',
                    style: AppTextStyles.button.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    ' (SEND LINK)',
                    style: AppTextStyles.englishSubtitle.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// 返回登录界面
  Widget _buildBackToLoginButton() {
    return Center(
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
