import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/user_session.dart';
import '../../core/services/api_client.dart';
import '../../features/shared/widgets/app_background.dart';
import 'forgot_password_screen.dart';

/// 登录页面
/// 桌面端登录界面，包含毛玻璃效果卡片和本地资产深海背景
///
/// Wave 2 真实化说明：
/// - 背景改用共享 AppBackground（本地资产，离线可用），
///   移除远程 URL（AppConstants.underwaterBgUrl）引用；
/// - 接入契约§4 must_change_password：登录成功且该标志为 true 时，
///   弹出强制改密对话框（PUT /api/users/{id}/password），
///   改密成功前不进入主界面。
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

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  /// 处理登录
  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    // 用户名或密码缺失：直接拦截
    if (username.isEmpty || password.isEmpty) {
      _showError('请输入用户名和密码');
      return;
    }

    setState(() => _isLoading = true);

    // 契约§4：先直接调用登录接口，读取 must_change_password 与 user.id
    // （UserSession.login 不透出这两个字段，故此处独立请求一次）
    Map<String, dynamic> resp;
    try {
      resp = await ApiClient.login(username, password);
    } on ApiException catch (e) {
      setState(() => _isLoading = false);
      _showError(e.message);
      return;
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('登录失败：$e');
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    final mustChange = resp['must_change_password'] == true;
    if (mustChange) {
      // 强制改密流程：改密成功前不进入主界面
      final user = resp['user'] as Map<String, dynamic>? ?? {};
      final userId = (user['id'] as num?)?.toInt();
      final token = resp['token']?.toString() ?? '';
      final newPassword = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ForceChangePasswordDialog(
          token: token,
          userId: userId,
          username: username,
          oldPassword: password,
        ),
      );
      if (newPassword == null || newPassword.isEmpty) {
        // 用户放弃改密：停留在登录页，不进入主界面
        return;
      }
      // 改密成功：用新密码建立正式会话（后端改密后已吊销旧会话）
      await _establishSession(username, newPassword);
      return;
    }

    // 正常登录：建立会话并进入主界面
    await _establishSession(username, password);
  }

  /// 建立会话（UserSession.login 内部完成 attachAuth）并跳转主界面
  Future<void> _establishSession(String username, String password) async {
    setState(() => _isLoading = true);
    final session = UserSession();
    final ok = await session.login(username, password);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (ok) {
      Navigator.pushReplacementNamed(context, '/dashboard');
    } else {
      _showError(session.lastLoginError.isEmpty ? '登录失败，请检查用户名和密码' : session.lastLoginError);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        // 本地资产业深海背景 + 暗化遮罩（离线可用，替代远程 URL）
        scrimOpacity: 0.5,
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

/// 强制改密对话框（契约§4）
///
/// 场景：登录响应 must_change_password = true（super_admin 仍在使用初始口令）。
/// 使用登录返回的 Bearer token 调用 PUT /api/users/{id}/password；
/// 改密成功后返回新密码给调用方重新建立会话，成功前不进入主界面。
class _ForceChangePasswordDialog extends StatefulWidget {
  /// 登录响应中的 Bearer token（改密接口鉴权用）
  final String token;

  /// 当前用户 id（来自登录响应 user.id）
  final int? userId;

  /// 用户名（改密成功后重新登录用）
  final String username;

  /// 登录时使用的旧密码（用于本地校验"旧密码"输入）
  final String oldPassword;

  const _ForceChangePasswordDialog({
    required this.token,
    required this.userId,
    required this.username,
    required this.oldPassword,
  });

  @override
  State<_ForceChangePasswordDialog> createState() =>
      _ForceChangePasswordDialogState();
}

class _ForceChangePasswordDialogState extends State<_ForceChangePasswordDialog> {
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _busy = false;
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _errorText;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// 提交改密：PUT /api/users/{id}/password（Bearer，契约§4）
  Future<void> _submit() async {
    final oldPwd = _oldController.text;
    final newPwd = _newController.text;
    final confirmPwd = _confirmController.text;

    if (oldPwd.isEmpty || newPwd.isEmpty || confirmPwd.isEmpty) {
      setState(() => _errorText = '请填写全部密码字段');
      return;
    }
    // 旧密码与登录口令本地校验（后端凭 Bearer token 鉴权身份）
    if (oldPwd != widget.oldPassword) {
      setState(() => _errorText = '旧密码不正确');
      return;
    }
    if (newPwd != confirmPwd) {
      setState(() => _errorText = '两次输入的新密码不一致');
      return;
    }
    if (widget.userId == null) {
      setState(() => _errorText = '登录响应缺少用户 id，无法修改密码');
      return;
    }

    setState(() {
      _busy = true;
      _errorText = null;
    });

    try {
      final response = await http
          .put(
            Uri.parse('${ApiClient.baseUrl}/api/users/${widget.userId}/password'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${widget.token}',
            },
            body: json.encode({'password': newPwd}),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (!mounted) return;
        // 改密成功：返回新密码，由调用方用新密码重建会话并进入主界面
        Navigator.of(context).pop(newPwd);
        return;
      }

      // 解析后端错误信息
      String message = '修改密码失败（HTTP ${response.statusCode}）';
      try {
        final data = json.decode(utf8.decode(response.bodyBytes));
        if (data is Map && data['error'] != null) {
          message = data['error'].toString();
        }
      } catch (_) {
        // 保留默认错误信息
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = '修改密码失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 改密进行中禁止关闭，避免停在半途状态
      canPop: !_busy,
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_reset, color: AppColors.primary),
            SizedBox(width: 8),
            Expanded(child: Text('请修改初始密码')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('当前账号仍在使用初始口令，为保障系统安全，首次登录必须修改密码。'),
              const SizedBox(height: 16),
              TextField(
                controller: _oldController,
                obscureText: _obscureOld,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: '旧密码',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureOld ? Icons.visibility_off : Icons.visibility,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscureOld = !_obscureOld),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newController,
                obscureText: _obscureNew,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: '新密码',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureNew ? Icons.visibility_off : Icons.visibility,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmController,
                obscureText: _obscureConfirm,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: '确认新密码',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                      size: 18,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            // 允许暂不修改：停留在登录页，不进入主界面
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('暂不修改'),
          ),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('确认修改',
                    style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
