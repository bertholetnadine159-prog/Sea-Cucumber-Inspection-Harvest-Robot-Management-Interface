import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/user_session.dart';
import 'forgot_password_screen.dart';

/// 登录页面
/// 桌面端登录界面，包含毛玻璃效果卡片和水下背景
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = false;
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 处理登录
  Future<void> _handleLogin() async {
    setState(() => _isLoading = true);
    
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    
    // 使用 UserSession 进行登录
    final session = UserSession();
    await session.initialize();
    final success = await session.login(username, password);
    
    setState(() => _isLoading = false);
    
    if (success && mounted) {
      Navigator.pushReplacementNamed(context, '/dashboard');
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录失败，请检查用户名和密码'), backgroundColor: AppColors.error),
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
        child: _buildLoginCard(),
      ),
    );
  }

  /// 构建登录卡片
  Widget _buildLoginCard() {
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
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(
        Icons.waves,
        color: Colors.white,
        size: 36,
      ),
    );
  }

  /// 构建标题
  Widget _buildTitle() {
    return Column(
      children: [
        Text(
          AppConstants.appName,
          style: AppTextStyles.h1.copyWith(
            color: AppColors.textPrimaryLight,
            letterSpacing: 4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          AppConstants.appNameEn,
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
        // 用户名
        _buildLabel('用户名', 'Username'),
        const SizedBox(height: 8),
        _buildUsernameField(),
        const SizedBox(height: 24),
        // 密码
        _buildLabel('密码', 'Password'),
        const SizedBox(height: 8),
        _buildPasswordField(),
        const SizedBox(height: 16),
        // 记住密码 & 忘记密码
        _buildOptions(),
        const SizedBox(height: 32),
        // 登录按钮
        _buildLoginButton(),
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

  /// 构建用户名输入框
  Widget _buildUsernameField() {
    return TextField(
      controller: _usernameController,
      decoration: InputDecoration(
        prefixIcon: const Icon(
          Icons.person_outline,
          color: AppColors.textTertiaryLight,
        ),
        hintText: 'Enter your username',
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

  /// 构建密码输入框
  Widget _buildPasswordField() {
    return TextField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        prefixIcon: const Icon(
          Icons.lock_outline,
          color: AppColors.textTertiaryLight,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
            color: AppColors.textTertiaryLight,
          ),
          onPressed: () {
            setState(() => _obscurePassword = !_obscurePassword);
          },
        ),
        hintText: 'Enter your password',
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

  /// 构建选项行
  Widget _buildOptions() {
    final narrowLayout = MediaQuery.of(context).size.width < 420;

    final rememberMeRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: Checkbox(
            value: _rememberMe,
            onChanged: (value) {
              setState(() => _rememberMe = value ?? false);
            },
            activeColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '记住密码',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondaryLight,
          ),
        ),
      ],
    );

    final forgotButton = TextButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ForgotPasswordScreen(),
          ),
        );
      },
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '忘记密码',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            TextSpan(
              text: ' (Forgot Password)',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );

    if (narrowLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          rememberMeRow,
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: forgotButton,
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: rememberMeRow),
        forgotButton,
      ],
    );
  }

  /// 构建登录按钮
  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
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
                    '登录',
                    style: AppTextStyles.button.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    ' (LOGIN)',
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
