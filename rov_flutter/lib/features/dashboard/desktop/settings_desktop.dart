/// 设置页面 - 桌面端
///
/// 功能：系统设置、显示设置、语言与地区、账户与安全。
/// Wave 2 变更（数据与设置真实化）：
/// - 双数据源消除：全部读写走 SettingsProvider（core 单一数据源），
///   删除本页自写 settings.json 的逻辑；显示设置变更即时生效
///   （SettingsProvider → app.dart 已有链路）。
/// - 语言与地区：移除语言选择器与时区/日期/时间假设置，改为只读说明
///   （国际化预留）。
/// - 显示区：高对比度开关移除（AppTheme 不支持，不留假开关）；
///   主题/字号/UI缩放/减少动画保留且真实生效。
/// - 账户与安全：真实化——当前用户/角色来自 GET /api/me，修改密码走
///   PUT /api/users/{id}/password，退出登录真实（UserSession.logout）。
///   删除双因素/自动锁定/生物识别/登录历史/删除账户等假功能。
/// - 系统区：自启动开关诚实标注"安装版生效"；RDK X5 地址配置经
///   WS set_rdk_config（需 admin），成功/失败均有明确反馈。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/services/user_session.dart';
import '../../../core/services/settings_provider.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/rov_backend_service.dart';
import '../../shared/widgets/motion_kit.dart';

/// 设置页面桌面端
class SettingsDesktop extends StatefulWidget {
  const SettingsDesktop({super.key});

  @override
  State<SettingsDesktop> createState() => _SettingsDesktopState();
}

class _SettingsDesktopState extends State<SettingsDesktop> {
  /// 当前选中的设置菜单项
  int _selectedMenuItem = 0;

  /// 全局设置提供者（单一数据源，core 轮已整理）
  final _settingsProvider = SettingsProvider();

  // === 系统区：RDK X5 地址（初值由 /api/health 回填真实网关地址） ===
  final TextEditingController _rdkHostController = TextEditingController();
  final TextEditingController _rdkPortController = TextEditingController();
  bool _rdkFieldsFilled = false;
  Map<String, dynamic>? _health;
  String? _healthError;

  // === 账户与安全：当前用户（GET /api/me） ===
  Map<String, dynamic>? _me;
  String? _meError;
  bool _meLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHealth();
    _loadMe();
  }

  @override
  void dispose() {
    _rdkHostController.dispose();
    _rdkPortController.dispose();
    super.dispose();
  }

  // ============ 数据加载 ============

  /// 读取 /api/health：回填 RDK 真实网关地址 + 连接状态展示
  Future<void> _loadHealth() async {
    try {
      final health = await ApiClient.health();
      if (!mounted) return;
      setState(() {
        _health = health;
        _healthError = null;
        if (!_rdkFieldsFilled) {
          final rdk = health['rdk'] as Map<String, dynamic>? ?? {};
          final host = rdk['host']?.toString();
          final port = rdk['port']?.toString();
          if (host != null && host.isNotEmpty) _rdkHostController.text = host;
          if (port != null && port.isNotEmpty) _rdkPortController.text = port;
          _rdkFieldsFilled = true;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _healthError = e.toString());
    }
  }

  /// 读取当前登录用户（GET /api/me）
  Future<void> _loadMe() async {
    final token = UserSession().authToken;
    if (token == null || token.isEmpty) {
      _setMe(null, '登录会话已失效，请重新登录');
      return;
    }
    try {
      final data = await _MeApi.fetch(token);
      _setMe(data, null);
    } catch (e) {
      _setMe(null, '$e');
    }
  }

  void _setMe(Map<String, dynamic>? me, String? error) {
    if (!mounted) return;
    setState(() {
      _me = me;
      _meError = error;
      _meLoading = false;
    });
  }

  // ============ RDK X5 地址配置（WS set_rdk_config，需 admin） ============

  /// 保存 RDK X5 地址：经 WS set_rdk_config 通道（后端要求 admin 角色），
  /// ack.success 即真实结果，成功/失败都有明确反馈。
  Future<void> _saveRdkConfig() async {
    final host = _rdkHostController.text.trim();
    final port = int.tryParse(_rdkPortController.text.trim());
    if (host.isEmpty || port == null || port < 1 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入合法的 RDK X5 IP 和端口'), backgroundColor: AppColors.error),
      );
      return;
    }
    final token = UserSession().authToken;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录会话已失效，请重新登录'), backgroundColor: AppColors.error),
      );
      return;
    }

    String? error;
    try {
      // 注意：WS 通道指向 PC 后端（如 localhost:8765），而非 RDK 网关地址；
      // set_rdk_config 由后端受理并转发/持久化到网关配置。
      final ack = await _UiSocketRequest.send(
        hostPort: RovBackendService().serverAddress,
        token: token,
        message: {'type': 'set_rdk_config', 'host': host, 'port': port, 'token': token},
      );
      if (ack['success'] != true) {
        error = ack['message']?.toString() ?? '后端拒绝：需要管理员角色';
      }
    } catch (e) {
      error = '$e';
    }

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('RDK 配置失败：$error'), backgroundColor: AppColors.error),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('RDK 地址已更新为 $host:$port，后端正在重连网关'), backgroundColor: AppColors.success),
    );
    _loadHealth();
  }

  // ============ 修改密码（PUT /api/users/{id}/password） ============

  void _showChangePasswordDialog() {
    final me = _me;
    final userId = (me?['id'] as num?)?.toInt();
    if (me == null || userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_meError ?? '尚未获取到当前用户信息'), backgroundColor: AppColors.error),
      );
      return;
    }
    final newController = TextEditingController();
    final confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('账户：${me['username'] ?? ''}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            TextField(
              controller: newController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '新密码', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: confirmController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '确认新密码', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final password = newController.text;
              if (password.isEmpty || password != confirmController.text) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('两次输入的密码不一致或为空'), backgroundColor: AppColors.error),
                );
                return;
              }
              final token = UserSession().authToken;
              if (token == null || token.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('登录会话已失效，请重新登录'), backgroundColor: AppColors.error),
                );
                return;
              }
              try {
                await _MeApi.changePassword(token, userId, password);
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('修改失败：$e'), backgroundColor: AppColors.error),
                  );
                }
                return;
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('密码修改成功'), backgroundColor: AppColors.success),
                );
              }
            },
            child: const Text('确认修改'),
          ),
        ],
      ),
    );
  }

  // ============ 其他操作 ============

  /// 清除缓存（真实删除系统临时目录内容）
  Future<void> _clearCache() async {
    try {
      final dir = await getTemporaryDirectory();
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
        await dir.create();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('缓存已清除'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清除缓存失败: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// 退出登录（真实：清除会话与后端 WS 鉴权，返回登录页）
  void _logout() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定退出当前账户吗？退出后需重新登录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              UserSession().logout();
              Navigator.pushReplacementNamed(context, '/');
            },
            child: const Text('确认退出', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  // ============ 页面构建 ============

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: Row(
        children: [
          _buildSidebar(isDark),
          Expanded(
            child: Container(
              color: isDark ? AppColors.surfaceDark : Colors.white,
              child: _buildContent(isDark),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建左侧边栏
  Widget _buildSidebar(bool isDark) {
    return Container(
      width: 256,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('配置中心', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textHint, letterSpacing: 1.2)),
            ),
          ),
          // 动效工具箱：侧栏菜单错峰入场（仅首次挂载播放）
          StaggerIn(index: 0, child: _buildMenuItem(0, Icons.computer, '系统设置')),
          StaggerIn(index: 1, child: _buildMenuItem(1, Icons.desktop_windows, '显示设置')),
          StaggerIn(index: 2, child: _buildMenuItem(2, Icons.language, '语言与地区')),
          StaggerIn(index: 3, child: _buildMenuItem(3, Icons.security, '账户与安全')),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info, size: 18, color: AppColors.primary.withValues(alpha: 0.7)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('显示设置即时生效；RDK 地址修改即时下发到后端。', style: TextStyle(fontSize: 12, color: AppColors.primary, height: 1.5)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(int index, IconData icon, String label) {
    final isSelected = _selectedMenuItem == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedMenuItem = index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.05) : Colors.transparent,
            border: Border(right: BorderSide(color: isSelected ? AppColors.primary : Colors.transparent, width: 3)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: isSelected ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 12),
              Text(label, style: TextStyle(fontSize: 14, color: isSelected ? AppColors.primary : AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    switch (_selectedMenuItem) {
      case 1:
        return _buildDisplaySettings();
      case 2:
        return _buildLanguageSettings();
      case 3:
        return _buildSecuritySettings();
      case 0:
      default:
        return _buildSystemSettings();
    }
  }

  // ==================== 系统设置 ====================
  Widget _buildSystemSettings() {
    final rdk = _health?['rdk'] as Map<String, dynamic>? ?? {};
    final connected = rdk['connected'] == true;
    final lastError = rdk['last_error']?.toString() ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageTitle(Icons.computer, '系统设置'),
          const SizedBox(height: 32),

          // 启动选项（诚实标注：不做假实现）
          _buildSectionTitle('启动选项'),
          const SizedBox(height: 16),
          _buildSwitchOption(
            '开机自动启动',
            '安装版注册系统启动项后生效',
            false,
            (_) {},
            enabled: false,
          ),

          _buildDivider(),

          // RDK X5 网线直连
          _buildSectionTitle('RDK X5 连接'),
          const SizedBox(height: 12),
          _buildRdkStatusChip(connected, rdk, lastError),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _rdkHostController,
                  decoration: const InputDecoration(
                    labelText: 'RDK X5 IP 地址',
                    hintText: '自动获取',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _rdkPortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '端口',
                    hintText: '默认 8080',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _saveRdkConfig,
                icon: const Icon(Icons.cable),
                label: const Text('保存并连接'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '修改需管理员权限，保存后自动重连网关',
            style: TextStyle(fontSize: 11, color: AppColors.textHint),
          ),

          _buildDivider(),

          // 维护（仅保留真实实现）
          _buildSectionTitle('维护'),
          const SizedBox(height: 16),
          _buildActionButton('清除缓存', Icons.cleaning_services, _clearCache),
        ],
      ),
    );
  }

  /// RDK 连接状态提示（来自 /api/health 真实状态）
  Widget _buildRdkStatusChip(bool connected, Map<String, dynamic> rdk, String lastError) {
    if (_healthError != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.error),
        ),
        child: Text('健康状态读取失败：$_healthError', style: const TextStyle(color: AppColors.error)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: connected ? AppColors.success.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: connected ? AppColors.success : AppColors.error),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.check_circle : Icons.error_outline,
            color: connected ? AppColors.success : AppColors.error,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            connected
                ? '已连接 RDK X5 ${rdk['host']}:${rdk['port']}'
                : (lastError.isNotEmpty ? '未连接：$lastError' : '未连接，请确认网线直连、板卡 IP 与本机网段一致'),
            style: TextStyle(color: connected ? AppColors.success : AppColors.error),
          ),
        ],
      ),
    );
  }

  // ==================== 显示设置 ====================
  Widget _buildDisplaySettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageTitle(Icons.desktop_windows, '显示设置'),
          const SizedBox(height: 8),
          const Text('以下设置修改后即时生效并自动保存', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
          const SizedBox(height: 32),

          // 主题模式（即时生效）
          _buildSectionTitle('主题模式'),
          const SizedBox(height: 16),
          _buildThemeSelector(),

          _buildDivider(),

          // 字体设置（即时生效）
          _buildSectionTitle('字体设置'),
          const SizedBox(height: 16),
          _buildSliderOption(
            '全局字体大小',
            '${_settingsProvider.fontSize.round()} pt',
            _settingsProvider.fontSize,
            10,
            20,
            (v) => _settingsProvider.setFontSize(v),
          ),
          const SizedBox(height: 24),
          _buildFontPreview(),

          _buildDivider(),

          // 界面缩放（即时生效）
          _buildSectionTitle('界面缩放'),
          const SizedBox(height: 16),
          _buildSliderOption(
            'UI缩放比例',
            '${(_settingsProvider.uiScale * 100).round()}%',
            _settingsProvider.uiScale,
            0.75,
            1.5,
            (v) => _settingsProvider.setUiScale(v),
          ),

          _buildDivider(),

          // 无障碍选项（减少动画真实生效；高对比度因 AppTheme 不支持已移除）
          _buildSectionTitle('无障碍'),
          const SizedBox(height: 16),
          _buildSwitchOption(
            '减少动画效果',
            '减少界面过渡动画，提升性能',
            _settingsProvider.reduceMotion,
            (v) => _settingsProvider.setReduceMotion(v),
          ),

          const SizedBox(height: 32),
          Row(
            children: [
              _buildOutlineButton('恢复默认值', () {
                _settingsProvider.resetToDefaults();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已恢复默认显示设置'), backgroundColor: AppColors.success),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSelector() {
    return AnimatedBuilder(
      animation: _settingsProvider,
      builder: (context, _) {
        return Row(
          children: [
            _buildThemeOption(0, Icons.light_mode, '明亮模式', '适合白天使用'),
            const SizedBox(width: 16),
            _buildThemeOption(1, Icons.dark_mode, '深色模式', '减少眼睛疲劳'),
            const SizedBox(width: 16),
            _buildThemeOption(2, Icons.brightness_auto, '跟随系统', '自动切换主题'),
          ],
        );
      },
    );
  }

  Widget _buildThemeOption(int mode, IconData icon, String title, String subtitle) {
    final isSelected = _settingsProvider.themeMode == mode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      // 动效工具箱：按压缩放反馈（主题切换仍由内部 InkWell 处理）
      child: PressableScale(
        child: Material(
        color: isSelected
            ? AppColors.primary.withValues(alpha: 0.1)
            : (isDark ? AppColors.backgroundDarkAlt : Colors.white),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            _settingsProvider.setThemeMode(mode); // 立即经 Provider 生效
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppColors.primary : (isDark ? AppColors.borderDark : AppColors.border),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(icon, size: 32, color: isSelected ? AppColors.primary : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondary)),
                const SizedBox(height: 12),
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isSelected ? AppColors.primary : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimary))),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(fontSize: 12, color: isSelected ? AppColors.primary.withValues(alpha: 0.7) : (isDark ? AppColors.textSecondaryDark : AppColors.textHint))),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildFontPreview() {
    final fontSize = _settingsProvider.fontSize;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('预览效果', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
          const SizedBox(height: 12),
          Text('海参检测机器人管理系统', style: TextStyle(fontSize: fontSize + 4, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text('界面文字随全局字号实时缩放', style: TextStyle(fontSize: fontSize, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('正文示例：数值与图表均来自真实设备回传', style: TextStyle(fontSize: fontSize - 2, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  // ==================== 语言与地区 ====================
  Widget _buildLanguageSettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageTitle(Icons.language, '语言与地区'),
          const SizedBox(height: 32),

          _buildSectionTitle('系统语言'),
          const SizedBox(height: 16),
          // 只读展示：国际化预留（本版本仅中文，不做假切换）
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.translate, color: AppColors.primary),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('中文（简体）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      SizedBox(height: 4),
                      Text('界面语言', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          _buildDivider(),

          _buildSectionTitle('地区格式'),
          const SizedBox(height: 8),
          const Text(
            '时区、日期与时间格式跟随操作系统区域设置。',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  // ==================== 账户与安全 ====================
  Widget _buildSecuritySettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageTitle(Icons.security, '账户与安全'),
          const SizedBox(height: 32),

          // 账户信息（GET /api/me 真实数据）
          _buildSectionTitle('账户信息'),
          const SizedBox(height: 16),
          _buildAccountInfoCard(),

          _buildDivider(),

          // 密码设置（真实 PUT /api/users/{id}/password）
          _buildSectionTitle('密码设置'),
          const SizedBox(height: 16),
          _buildActionButton('修改密码', Icons.lock, _showChangePasswordDialog),
          const SizedBox(height: 8),
          const Text(
            '密码修改需管理员权限，修改后即时生效。',
            style: TextStyle(fontSize: 11, color: AppColors.textHint),
          ),

          _buildDivider(),

          // 危险区（旧版视觉：error 5% 底 + error 30% 描边圆角 12 +
          // warning 图标 + "危险区域" 14 bold error；删除账户无真实接口不提供，
          // 仅保留真实的退出登录）
          _buildSectionTitle('会话'),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning, size: 20, color: AppColors.error),
                    SizedBox(width: 8),
                    Text('危险区域',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.error)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '退出登录将清除本地登录状态并断开后端连接，需重新登录。',
                  style: const TextStyle(fontSize: 12, color: AppColors.textHint, height: 1.5),
                ),
                const SizedBox(height: 16),
                _buildDangerButton('退出登录', _logout),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 账户信息卡片（来自 GET /api/me：用户名/真实姓名/角色/ID）
  Widget _buildAccountInfoCard() {
    if (_meLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.all(Radius.circular(12)),
          border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
        ),
        // 动效工具箱：加载骨架（reduceMotion 时为静态骨架）
        child: const SkeletonLoader(lines: 2, spacing: 12, height: 14),
      );
    }
    if (_me == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Text('⚠ 无法获取当前用户信息：$_meError', style: const TextStyle(color: AppColors.error, fontSize: 13)),
      );
    }

    final displayName = (_me!['real_name']?.toString().isNotEmpty == true)
        ? _me!['real_name'].toString()
        : _me!['username']?.toString() ?? '未知用户';
    final username = _me!['username']?.toString() ?? '';
    final role = _mapRole(_me!['role']?.toString() ?? '');
    final userId = _me!['id'];
    final firstChar = displayName.characters.first;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(firstChar, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white))),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text('登录用户名：$username · 用户ID：$userId', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(role, style: const TextStyle(fontSize: 12, color: AppColors.primary)),
                ),
              ],
            ),
          ),
          _buildOutlineButton('刷新', _loadMe),
        ],
      ),
    );
  }

  String _mapRole(String role) {
    switch (role) {
      case 'super_admin':
        return '超级管理员';
      case 'admin':
        return '管理员';
      default:
        return role.isEmpty ? '普通用户' : role;
    }
  }

  // ==================== 通用组件 ====================
  Widget _buildPageTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 28, color: AppColors.textPrimary),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary));
  }

  Widget _buildDivider() {
    return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider(color: AppColors.border));
  }

  Widget _buildSwitchOption(String title, String subtitle, bool value, ValueChanged<bool> onChanged, {bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
              ],
            ),
          ),
          Switch(value: value, onChanged: enabled ? onChanged : null, activeThumbColor: AppColors.primary),
        ],
      ),
    );
  }

  Widget _buildSliderOption(String title, String valueText, double value, double min, double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
              child: Text(valueText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged, activeColor: AppColors.primary),
      ],
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOutlineButton(String label, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
          child: Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
        ),
      ),
    );
  }

  Widget _buildDangerButton(String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.error)),
          child: Text(label, style: const TextStyle(fontSize: 14, color: AppColors.error)),
        ),
      ),
    );
  }
}

/// 页面内 REST 轻封装：补齐 ApiClient 未覆盖的 /api/me 与改密端点。
/// （ApiClient 属 C 轮基建文件，本轮只读不改，故在页面内私有封装。）
class _MeApi {
  /// GET /api/me（Bearer）→ user 对象
  static Future<Map<String, dynamic>> fetch(String token) async {
    final uri = Uri.parse('${ApiClient.baseUrl}/api/me');
    final response = await http
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      String message = 'HTTP ${response.statusCode}';
      try {
        final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        message = data['error']?.toString() ?? message;
      } catch (_) {}
      throw Exception(message);
    }
    final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (data['ok'] != true) throw Exception(data['error']?.toString() ?? '请求失败');
    return (data['user'] as Map<String, dynamic>?) ?? {};
  }

  /// PUT /api/users/{id}/password（Bearer，后端规则：admin 角色）
  static Future<void> changePassword(String token, int userId, String password) async {
    final uri = Uri.parse('${ApiClient.baseUrl}/api/users/$userId/password');
    final response = await http
        .put(
          uri,
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
          body: json.encode({'password': password}),
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'HTTP ${response.statusCode}';
      try {
        final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        message = data['error']?.toString() ?? message;
      } catch (_) {}
      throw Exception(message);
    }
  }
}

/// 辅助 WS 通道：set_rdk_config 的结果反馈需要读取 ack，
/// 主服务层不回传 ack 负载，这里建立短连接触达后端，用完即关。
class _UiSocketRequest {
  static const Duration _timeout = Duration(seconds: 6);

  /// 连接 → auth → 发送命令 → 等待首个 ack → 关闭，返回 ack 消息
  static Future<Map<String, dynamic>> send({
    required String hostPort,
    required String token,
    required Map<String, dynamic> message,
  }) async {
    final completer = Completer<Map<String, dynamic>>();
    WebSocketChannel? channel;
    StreamSubscription<dynamic>? sub;
    try {
      channel = WebSocketChannel.connect(Uri.parse('ws://$hostPort'));
      await channel.ready.timeout(_timeout);
      sub = channel.stream.listen(
        (data) {
          if (data is String && !completer.isCompleted) {
            try {
              final msg = json.decode(data) as Map<String, dynamic>;
              // 命令 ack 即完成（hello/auth_result/status 等消息忽略）
              if (msg['type'] == 'ack') completer.complete(msg);
            } catch (_) {/* 非 JSON 消息忽略 */}
          }
        },
        onError: (Object e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) completer.completeError(Exception('后端连接已关闭'));
        },
      );
      channel.sink.add(json.encode({'type': 'auth', 'action': 'login', 'token': token}));
      channel.sink.add(json.encode(message));
      return await completer.future.timeout(_timeout);
    } on TimeoutException {
      throw Exception('后端响应超时，请确认 PC 后端已启动');
    } finally {
      try {
        await sub?.cancel();
      } catch (_) {}
      try {
        await channel?.sink.close();
      } catch (_) {}
    }
  }
}
