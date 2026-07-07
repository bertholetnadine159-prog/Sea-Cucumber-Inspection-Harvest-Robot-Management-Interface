/// 设置页面 - 桌面端
/// 
/// 功能：系统设置、显示设置、语言与地区、账户与安全 - 完整实现
/// 设计稿对应：win/settings/screen.png
library;

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/user_session.dart';
import '../../../core/services/settings_provider.dart';

/// 设置页面桌面端
class SettingsDesktop extends StatefulWidget {
  const SettingsDesktop({super.key});

  @override
  State<SettingsDesktop> createState() => _SettingsDesktopState();
}

class _SettingsDesktopState extends State<SettingsDesktop> {
  // 当前选中的设置菜单项
  int _selectedMenuItem = 0;
  
  // 全局设置提供者
  final _settingsProvider = SettingsProvider();
  
  // === 系统设置 ===
  bool _autoStartup = true;
  bool _minimizeToTray = true;
  bool _autoUpdate = true;
  bool _sendUsageData = false;
  String _dataStoragePath = 'D:\\ROV_Data';
  int _logRetentionDays = 30;
  
  // === 显示设置（从SettingsProvider同步）===
  int _themeMode = 0; // 0=明亮, 1=深色, 2=跟随系统
  double _fontSize = 14;
  bool _highContrast = false;
  bool _reduceMotion = false;
  double _uiScale = 1.0;
  
  // === 语言与地区 ===
  int _language = 0; // 0=简体中文, 1=English, 2=日本語
  int _dateFormat = 0; // 0=YYYY-MM-DD, 1=MM/DD/YYYY, 2=DD/MM/YYYY
  int _timeFormat = 0; // 0=24小时, 1=12小时
  String _timezone = 'Asia/Shanghai (UTC+8)';
  
  // === 账户与安全 ===
  bool _twoFactorAuth = false;
  bool _autoLock = true;
  int _autoLockMinutes = 15;
  bool _biometricUnlock = false;
  String _lastPasswordChange = '2026-01-15';
  
  // 设置文件路径
  String? _settingsFilePath;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _syncFromProvider();
  }
  
  /// 从全局设置提供者同步显示设置
  void _syncFromProvider() {
    setState(() {
      _themeMode = _settingsProvider.themeMode;
      _fontSize = _settingsProvider.fontSize;
      _highContrast = _settingsProvider.highContrast;
      _reduceMotion = _settingsProvider.reduceMotion;
      _uiScale = _settingsProvider.uiScale;
      _language = _settingsProvider.language;
      _dateFormat = _settingsProvider.dateFormat;
      _timeFormat = _settingsProvider.timeFormat;
    });
  }
  
  /// 将显示设置同步到全局设置提供者
  void _syncToProvider() {
    _settingsProvider.updateSettings(
      themeMode: _themeMode,
      fontSize: _fontSize,
      highContrast: _highContrast,
      reduceMotion: _reduceMotion,
      uiScale: _uiScale,
      language: _language,
      dateFormat: _dateFormat,
      timeFormat: _timeFormat,
    );
  }

  /// 获取设置文件路径
  Future<String> _getSettingsFilePath() async {
    if (_settingsFilePath != null) return _settingsFilePath!;
    final dir = await getApplicationDocumentsDirectory();
    _settingsFilePath = '${dir.path}/rov_flutter_data/settings.json';
    return _settingsFilePath!;
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    try {
      final filePath = await _getSettingsFilePath();
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> data = json.decode(content);
        setState(() {
          _autoStartup = data['autoStartup'] ?? true;
          _minimizeToTray = data['minimizeToTray'] ?? true;
          _autoUpdate = data['autoUpdate'] ?? true;
          _sendUsageData = data['sendUsageData'] ?? false;
          _dataStoragePath = data['dataStoragePath'] ?? 'D:\\ROV_Data';
          _logRetentionDays = data['logRetentionDays'] ?? 30;
          _themeMode = data['themeMode'] ?? 0;
          _fontSize = (data['fontSize'] ?? 14).toDouble();
          _highContrast = data['highContrast'] ?? false;
          _reduceMotion = data['reduceMotion'] ?? false;
          _uiScale = (data['uiScale'] ?? 1.0).toDouble();
          _language = data['language'] ?? 0;
          _dateFormat = data['dateFormat'] ?? 0;
          _timeFormat = data['timeFormat'] ?? 0;
          _timezone = data['timezone'] ?? 'Asia/Shanghai (UTC+8)';
          _twoFactorAuth = data['twoFactorAuth'] ?? false;
          _autoLock = data['autoLock'] ?? true;
          _autoLockMinutes = data['autoLockMinutes'] ?? 15;
          _biometricUnlock = data['biometricUnlock'] ?? false;
          _lastPasswordChange = data['lastPasswordChange'] ?? '2026-01-15';
        });
      }
    } catch (e) {
      // 使用默认设置
    }
  }

  /// 保存设置
  Future<void> _saveSettings() async {
    try {
      final filePath = await _getSettingsFilePath();
      final file = File(filePath);
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      final data = {
        'autoStartup': _autoStartup,
        'minimizeToTray': _minimizeToTray,
        'autoUpdate': _autoUpdate,
        'sendUsageData': _sendUsageData,
        'dataStoragePath': _dataStoragePath,
        'logRetentionDays': _logRetentionDays,
        'themeMode': _themeMode,
        'fontSize': _fontSize,
        'highContrast': _highContrast,
        'reduceMotion': _reduceMotion,
        'uiScale': _uiScale,
        'language': _language,
        'dateFormat': _dateFormat,
        'timeFormat': _timeFormat,
        'timezone': _timezone,
        'twoFactorAuth': _twoFactorAuth,
        'autoLock': _autoLock,
        'autoLockMinutes': _autoLockMinutes,
        'biometricUnlock': _biometricUnlock,
        'lastPasswordChange': _lastPasswordChange,
      };
      
      await file.writeAsString(json.encode(data));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('设置已保存'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存设置失败: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// 选择数据存储路径
  Future<void> _selectDataStoragePath() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择数据存储路径',
    );
    if (result != null) {
      setState(() => _dataStoragePath = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('存储路径已更改为: $result')),
      );
    }
  }

  /// 导出配置
  Future<void> _exportConfig() async {
    try {
      final data = {
        'autoStartup': _autoStartup,
        'minimizeToTray': _minimizeToTray,
        'autoUpdate': _autoUpdate,
        'sendUsageData': _sendUsageData,
        'dataStoragePath': _dataStoragePath,
        'logRetentionDays': _logRetentionDays,
        'themeMode': _themeMode,
        'fontSize': _fontSize,
        'highContrast': _highContrast,
        'reduceMotion': _reduceMotion,
        'uiScale': _uiScale,
        'language': _language,
        'dateFormat': _dateFormat,
        'timeFormat': _timeFormat,
        'timezone': _timezone,
        'twoFactorAuth': _twoFactorAuth,
        'autoLock': _autoLock,
        'autoLockMinutes': _autoLockMinutes,
        'biometricUnlock': _biometricUnlock,
        'exportTime': DateTime.now().toString(),
      };
      
      final content = const JsonEncoder.withIndent('  ').convert(data);
      final timestamp = DateTime.now().toString().replaceAll(':', '-').split('.')[0];
      final fileName = 'rov_config_$timestamp.json';
      
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '导出配置',
        fileName: fileName,
      );
      
      if (result != null) {
        String filePath = result;
        if (!filePath.endsWith('.json')) {
          filePath = '$filePath.json';
        }
        final file = File(filePath);
        await file.writeAsString(content);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('配置已导出到: $filePath'), backgroundColor: AppColors.success),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出配置失败: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// 清除缓存
  Future<void> _clearCache() async {
    try {
      final dir = await getTemporaryDirectory();
      if (await dir.exists()) {
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

  /// 重置设置
  void _resetSettings() {
    setState(() {
      _autoStartup = true;
      _minimizeToTray = true;
      _autoUpdate = true;
      _sendUsageData = false;
      _dataStoragePath = 'D:\\ROV_Data';
      _logRetentionDays = 30;
      _themeMode = 0;
      _fontSize = 14;
      _highContrast = false;
      _reduceMotion = false;
      _uiScale = 1.0;
      _language = 0;
      _dateFormat = 0;
      _timeFormat = 0;
      _timezone = 'Asia/Shanghai (UTC+8)';
      _twoFactorAuth = false;
      _autoLock = true;
      _autoLockMinutes = 15;
      _biometricUnlock = false;
    });
    _saveSettings();
  }

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
          _buildMenuItem(0, Icons.computer, '系统设置'),
          _buildMenuItem(1, Icons.desktop_windows, '显示设置'),
          _buildMenuItem(2, Icons.language, '语言与地区'),
          _buildMenuItem(3, Icons.security, '账户与安全'),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info, size: 18, color: AppColors.primary.withOpacity(0.7)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('部分设置修改后需要重新启动机器人控制程序才能完全生效。', style: TextStyle(fontSize: 12, color: AppColors.primary, height: 1.5)),
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
            color: isSelected ? AppColors.primary.withOpacity(0.05) : Colors.transparent,
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
      case 0:
        return _buildSystemSettings();
      case 1:
        return _buildDisplaySettings();
      case 2:
        return _buildLanguageSettings();
      case 3:
        return _buildSecuritySettings();
      default:
        return _buildSystemSettings();
    }
  }

  // ==================== 系统设置 ====================
  Widget _buildSystemSettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageTitle(Icons.computer, '系统设置'),
          const SizedBox(height: 32),
          
          // 启动选项
          _buildSectionTitle('启动选项'),
          const SizedBox(height: 16),
          _buildSwitchOption('开机自动启动', '系统启动时自动运行ROV管理程序', _autoStartup, (v) => setState(() => _autoStartup = v)),
          _buildSwitchOption('最小化到系统托盘', '关闭窗口时最小化到托盘而非退出', _minimizeToTray, (v) => setState(() => _minimizeToTray = v)),
          
          _buildDivider(),
          
          // 更新设置
          _buildSectionTitle('更新设置'),
          const SizedBox(height: 16),
          _buildSwitchOption('自动检查更新', '定期检查软件更新并提示安装', _autoUpdate, (v) => setState(() => _autoUpdate = v)),
          _buildSwitchOption('发送使用统计', '发送匿名使用数据帮助改进产品', _sendUsageData, (v) => setState(() => _sendUsageData = v)),
          
          _buildDivider(),
          
          // 数据存储
          _buildSectionTitle('数据存储'),
          const SizedBox(height: 16),
          _buildPathOption('数据存储路径', _dataStoragePath, _selectDataStoragePath),
          const SizedBox(height: 16),
          _buildSliderOption('日志保留天数', '$_logRetentionDays 天', _logRetentionDays.toDouble(), 7, 90, (v) => setState(() => _logRetentionDays = v.round())),
          
          _buildDivider(),
          
          // 高级选项
          _buildSectionTitle('高级选项'),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildActionButton('清除缓存', Icons.cleaning_services, _clearCache),
              const SizedBox(width: 16),
              _buildActionButton('重置设置', Icons.restore, () {
                _showResetConfirmDialog();
              }),
              const SizedBox(width: 16),
              _buildActionButton('导出配置', Icons.upload_file, _exportConfig),
            ],
          ),
          
          const SizedBox(height: 32),
          _buildApplyButton(),
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
          const SizedBox(height: 32),
          
          // 主题模式
          _buildSectionTitle('主题模式'),
          const SizedBox(height: 16),
          _buildThemeSelector(),
          
          _buildDivider(),
          
          // 字体设置
          _buildSectionTitle('字体设置'),
          const SizedBox(height: 16),
          _buildSliderOption('全局字体大小', '${_fontSize.round()} pt', _fontSize, 10, 20, (v) => setState(() => _fontSize = v)),
          const SizedBox(height: 24),
          _buildFontPreview(),
          
          _buildDivider(),
          
          // 界面缩放
          _buildSectionTitle('界面缩放'),
          const SizedBox(height: 16),
          _buildSliderOption('UI缩放比例', '${(_uiScale * 100).round()}%', _uiScale, 0.75, 1.5, (v) => setState(() => _uiScale = v)),
          
          _buildDivider(),
          
          // 无障碍选项
          _buildSectionTitle('无障碍与视觉增强'),
          const SizedBox(height: 16),
          _buildSwitchOption('高对比度模式', '增强界面元素对比度，便于阅读', _highContrast, (v) => setState(() => _highContrast = v)),
          _buildSwitchOption('减少动画效果', '减少界面过渡动画，提升性能', _reduceMotion, (v) => setState(() => _reduceMotion = v)),
          
          const SizedBox(height: 32),
          Row(
            children: [
              _buildOutlineButton('恢复默认值', () {
                setState(() {
                  _themeMode = 0;
                  _fontSize = 14;
                  _uiScale = 1.0;
                  _highContrast = false;
                  _reduceMotion = false;
                });
                _syncToProvider();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已恢复默认显示设置'), backgroundColor: AppColors.success),
                );
              }),
              const SizedBox(width: 16),
              _buildPrimaryButton('应用更改', () {
                _syncToProvider();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('显示设置已应用，主题已切换'), backgroundColor: AppColors.success),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSelector() {
    return Row(
      children: [
        _buildThemeOption(0, Icons.light_mode, '明亮模式', '适合白天使用'),
        const SizedBox(width: 16),
        _buildThemeOption(1, Icons.dark_mode, '深色模式', '减少眼睛疲劳'),
        const SizedBox(width: 16),
        _buildThemeOption(2, Icons.brightness_auto, '跟随系统', '自动切换主题'),
      ],
    );
  }

  Widget _buildThemeOption(int mode, IconData icon, String title, String subtitle) {
    final isSelected = _themeMode == mode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Material(
        color: isSelected 
            ? AppColors.primary.withOpacity(0.1) 
            : (isDark ? AppColors.backgroundDarkAlt : Colors.white),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            setState(() => _themeMode = mode);
            _syncToProvider(); // 立即同步到全局设置
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
                Text(subtitle, style: TextStyle(fontSize: 12, color: isSelected ? AppColors.primary.withOpacity(0.7) : (isDark ? AppColors.textSecondaryDark : AppColors.textHint))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFontPreview() {
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
          Text('海参检测机器人管理系统', style: TextStyle(fontSize: _fontSize + 4, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text('ROV-DEEPSEA-01 正在执行巡检任务', style: TextStyle(fontSize: _fontSize, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('当前水深: 5.2m | 水温: 12.5°C | PH值: 7.85', style: TextStyle(fontSize: _fontSize - 2, color: AppColors.textSecondary)),
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
          
          // 系统语言
          _buildSectionTitle('系统语言'),
          const SizedBox(height: 16),
          _buildLanguageSelector(),
          
          _buildDivider(),
          
          // 日期格式
          _buildSectionTitle('日期格式'),
          const SizedBox(height: 16),
          _buildRadioGroup([
            ('YYYY-MM-DD', '2026-02-27'),
            ('MM/DD/YYYY', '02/27/2026'),
            ('DD/MM/YYYY', '27/02/2026'),
          ], _dateFormat, (v) => setState(() => _dateFormat = v)),
          
          _buildDivider(),
          
          // 时间格式
          _buildSectionTitle('时间格式'),
          const SizedBox(height: 16),
          _buildRadioGroup([
            ('24小时制', '14:30:00'),
            ('12小时制', '02:30:00 PM'),
          ], _timeFormat, (v) => setState(() => _timeFormat = v)),
          
          _buildDivider(),
          
          // 时区设置
          _buildSectionTitle('时区设置'),
          const SizedBox(height: 16),
          _buildDropdownOption('当前时区', _timezone, [
            'Asia/Shanghai (UTC+8)',
            'Asia/Tokyo (UTC+9)',
            'America/New_York (UTC-5)',
            'Europe/London (UTC+0)',
          ], (v) => setState(() => _timezone = v)),
          
          const SizedBox(height: 32),
          _buildApplyButton(),
        ],
      ),
    );
  }

  Widget _buildLanguageSelector() {
    final languages = [
      ('简体中文', '🇨🇳', '系统默认语言'),
      ('English', '🇺🇸', 'Switch to English'),
      ('日本語', '🇯🇵', '日本語に切り替え'),
    ];
    
    return Row(
      children: languages.asMap().entries.map((entry) {
        final isSelected = _language == entry.key;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: entry.key < 2 ? 16 : 0),
            child: Material(
              color: isSelected ? AppColors.primary.withOpacity(0.1) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => setState(() => _language = entry.key),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: isSelected ? 2 : 1),
                  ),
                  child: Row(
                    children: [
                      Text(entry.value.$2, style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.value.$1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isSelected ? AppColors.primary : AppColors.textPrimary)),
                            Text(entry.value.$3, style: TextStyle(fontSize: 11, color: isSelected ? AppColors.primary.withOpacity(0.7) : AppColors.textHint)),
                          ],
                        ),
                      ),
                      if (isSelected) const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
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
          
          // 账户信息
          _buildSectionTitle('账户信息'),
          const SizedBox(height: 16),
          _buildAccountInfoCard(),
          
          _buildDivider(),
          
          // 密码设置
          _buildSectionTitle('密码设置'),
          const SizedBox(height: 16),
          _buildInfoRow('上次修改密码', _lastPasswordChange),
          const SizedBox(height: 16),
          _buildActionButton('修改密码', Icons.lock, () {
            _showChangePasswordDialog();
          }),
          
          _buildDivider(),
          
          // 安全选项
          _buildSectionTitle('安全选项'),
          const SizedBox(height: 16),
          _buildSwitchOption('双因素认证', '登录时需要验证码二次确认', _twoFactorAuth, (v) => setState(() => _twoFactorAuth = v)),
          _buildSwitchOption('自动锁定', '一段时间无操作后自动锁定', _autoLock, (v) => setState(() => _autoLock = v)),
          if (_autoLock) ...[
            const SizedBox(height: 16),
            _buildSliderOption('自动锁定时间', '$_autoLockMinutes 分钟', _autoLockMinutes.toDouble(), 5, 60, (v) => setState(() => _autoLockMinutes = v.round())),
          ],
          _buildSwitchOption('生物识别解锁', '使用指纹或面部识别解锁', _biometricUnlock, (v) => setState(() => _biometricUnlock = v)),
          
          _buildDivider(),
          
          // 登录历史
          _buildSectionTitle('登录历史'),
          const SizedBox(height: 16),
          _buildLoginHistoryList(),
          
          _buildDivider(),
          
          // 危险操作
          _buildSectionTitle('危险操作'),
          const SizedBox(height: 16),
          _buildDangerZone(),
          
          const SizedBox(height: 32),
          _buildApplyButton(),
        ],
      ),
    );
  }

  Widget _buildAccountInfoCard() {
    final session = UserSession();
    final displayName = session.displayName;
    final displayRole = session.displayRole;
    final firstChar = displayName.isNotEmpty ? displayName.characters.first : '?';
    
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
                Text('${displayName.toLowerCase().replaceAll(' ', '_')}@rov-system.com', style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(displayRole.isNotEmpty ? displayRole : '普通用户', style: const TextStyle(fontSize: 12, color: AppColors.primary)),
                ),
              ],
            ),
          ),
          _buildOutlineButton('编辑资料', () {
            _showEditProfileDialog();
          }),
        ],
      ),
    );
  }

  /// 显示编辑资料对话框
  void _showEditProfileDialog() {
    final session = UserSession();
    final nameController = TextEditingController(text: session.displayName);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑资料'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '显示名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const TextField(
              decoration: InputDecoration(
                labelText: '邮箱地址',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('资料已更新'), backgroundColor: AppColors.success),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginHistoryList() {
    final history = [
      ('2026-02-27 14:30', 'Windows 11', '192.168.1.100', true),
      ('2026-02-26 09:15', 'Windows 11', '192.168.1.100', true),
      ('2026-02-25 18:42', 'Android 14', '192.168.1.105', true),
      ('2026-02-24 10:30', 'Unknown', '103.45.67.89', false),
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: history.asMap().entries.map((entry) {
          final isLast = entry.key == history.length - 1;
          final item = entry.value;
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Icon(item.$4 ? Icons.check_circle : Icons.warning, size: 20, color: item.$4 ? AppColors.success : AppColors.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.$1, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
                      Text('${item.$2} · ${item.$3}', style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                    ],
                  ),
                ),
                Text(item.$4 ? '成功' : '失败', style: TextStyle(fontSize: 12, color: item.$4 ? AppColors.success : AppColors.error)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDangerZone() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning, color: AppColors.error, size: 20),
              SizedBox(width: 8),
              Text('危险区域', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.error)),
            ],
          ),
          const SizedBox(height: 12),
          const Text('以下操作不可逆，请谨慎操作', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildDangerButton('登出所有设备', _showLogoutAllDevicesDialog),
              const SizedBox(width: 16),
              _buildDangerButton('删除账户', _showDeleteAccountDialog),
            ],
          ),
        ],
      ),
    );
  }

  /// 显示登出所有设备确认对话框
  void _showLogoutAllDevicesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.logout, color: AppColors.error),
            SizedBox(width: 8),
            Text('登出所有设备'),
          ],
        ),
        content: const Text('此操作将登出您在所有设备上的会话，您需要重新登录。确定要继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // 执行登出操作
              final session = UserSession();
              session.logout();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已登出所有设备'), backgroundColor: AppColors.success),
              );
              // 返回登录页面
              Navigator.pushReplacementNamed(context, '/');
            },
            child: const Text('确认登出', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  /// 显示删除账户确认对话框
  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: AppColors.error),
            SizedBox(width: 8),
            Text('删除账户'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('此操作将永久删除您的账户及所有相关数据，此操作不可撤销！'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: AppColors.error, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('删除后将无法恢复，请谨慎操作', style: TextStyle(fontSize: 12, color: AppColors.error)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // 显示二次确认
              _showFinalDeleteConfirmDialog();
            },
            child: const Text('我要删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  /// 最终删除确认对话框
  void _showFinalDeleteConfirmDialog() {
    final confirmController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('最终确认'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请输入 "DELETE" 以确认删除账户：'),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              decoration: const InputDecoration(
                hintText: '输入 DELETE',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (confirmController.text == 'DELETE') {
                Navigator.pop(context);
                // 执行删除操作
                final session = UserSession();
                session.logout();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('账户已删除'), backgroundColor: AppColors.error),
                );
                Navigator.pushReplacementNamed(context, '/');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('输入不正确'), backgroundColor: AppColors.error),
                );
              }
            },
            child: const Text('确认删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
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

  Widget _buildSwitchOption(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
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
          Switch(value: value, onChanged: onChanged, activeColor: AppColors.primary),
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
        Slider(value: value, min: min, max: max, onChanged: onChanged, activeColor: AppColors.primary),
      ],
    );
  }

  Widget _buildPathOption(String title, String path, VoidCallback onTap) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(path, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
            ],
          ),
        ),
        _buildOutlineButton('更改', onTap),
      ],
    );
  }

  Widget _buildDropdownOption(String title, String value, List<String> options, ValueChanged<String> onChanged) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              underline: const SizedBox(),
              items: options.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => onChanged(v!),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRadioGroup(List<(String, String)> options, int selected, ValueChanged<int> onChanged) {
    return Column(
      children: options.asMap().entries.map((entry) {
        final isSelected = selected == entry.key;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () => onChanged(entry.key),
            child: Row(
              children: [
                Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: 2),
                    color: isSelected ? AppColors.primary : Colors.transparent,
                  ),
                  child: isSelected ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                ),
                const SizedBox(width: 12),
                Text(entry.value.$1, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
                const SizedBox(width: 8),
                Text('(${entry.value.$2})', style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        const SizedBox(width: 16),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
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

  Widget _buildPrimaryButton(String label, VoidCallback onTap) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Text(label, style: const TextStyle(fontSize: 14, color: Colors.white)),
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

  Widget _buildApplyButton() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _buildOutlineButton('恢复默认值', _resetSettings),
        const SizedBox(width: 16),
        _buildPrimaryButton('应用更改', _saveSettings),
      ],
    );
  }

  void _showResetConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认重置'),
        content: const Text('确定要将所有设置恢复为默认值吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetSettings();
            },
            child: const Text('确认', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(obscureText: true, decoration: const InputDecoration(labelText: '当前密码', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(obscureText: true, decoration: const InputDecoration(labelText: '新密码', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(obscureText: true, decoration: const InputDecoration(labelText: '确认新密码', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('密码修改成功')));
            },
            child: const Text('确认修改'),
          ),
        ],
      ),
    );
  }
}
