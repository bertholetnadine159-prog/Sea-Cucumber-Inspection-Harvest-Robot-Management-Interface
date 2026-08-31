/// 设置页面 - 移动端
/// 
/// 功能：显示设置、主题模式、语言选择、字体大小、UI缩放、减少动画
/// 设计稿对应：app/settings/screen.png
library;

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/settings_provider.dart';

/// 移动端设置页面
class SettingsMobile extends StatefulWidget {
  const SettingsMobile({super.key});

  @override
  State<SettingsMobile> createState() => _SettingsMobileState();
}

class _SettingsMobileState extends State<SettingsMobile> {
  // 全局设置服务
  final _settingsProvider = SettingsProvider();
  
  // 主题模式: 0=明亮, 1=深色, 2=跟随系统
  int _themeMode = 0;
  
  // 语言: 0=简体中文, 1=English
  int _language = 0;
  
  // 字体大小
  double _fontSize = 14;
  
  // UI缩放
  double _uiScale = 1.0;
  
  // 高对比度
  bool _highContrast = false;
  
  // 减少动画
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _settingsProvider.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _settingsProvider.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _loadSettings() {
    setState(() {
      _themeMode = _settingsProvider.themeMode;
      _fontSize = _settingsProvider.fontSize;
      _uiScale = _settingsProvider.uiScale;
      _highContrast = _settingsProvider.highContrast;
      _reduceMotion = _settingsProvider.reduceMotion;
    });
  }

  void _onSettingsChanged() {
    if (mounted) _loadSettings();
  }

  void _saveSettings() {
    _settingsProvider.updateSettings(
      themeMode: _themeMode,
      fontSize: _fontSize,
      uiScale: _uiScale,
      highContrast: _highContrast,
      reduceMotion: _reduceMotion,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : null,
      body: CustomScrollView(
        slivers: [
          // 渐变头部
          SliverToBoxAdapter(child: _buildHeader(context)),
          // 内容区域
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 页面标题
                  Text('显示设置', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? AppColors.textPrimaryDark : null)),
                  const SizedBox(height: 4),
                  Text('自定义界面外观与阅读体验', style: TextStyle(fontSize: 13, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary)),
                  const SizedBox(height: 24),
                  
                  // 主题模式
                  _buildThemeModeSection(isDark),
                  const SizedBox(height: 24),
                  
                  // 系统语言
                  _buildLanguageSection(),
                  const SizedBox(height: 24),
                  
                  // 全局字体大小
                  _buildFontSizeSection(),
                  const SizedBox(height: 24),
                  
                  // UI缩放
                  _buildUIScaleSection(),
                  const SizedBox(height: 24),
                  
                  // 高级设置
                  _buildAdvancedSettings(),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建渐变头部
  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 16,
      ),
      decoration: const BoxDecoration(
        gradient: AppColors.headerGradient,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '海参检测系统',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: const Icon(Icons.person, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }

  /// 构建主题模式区域
  Widget _buildThemeModeSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('主题模式', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? AppColors.textPrimaryDark : null)),
          const SizedBox(height: 8),
          Text('根据您的工作环境调整视觉风格。', style: TextStyle(fontSize: 13, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _buildThemeCard(0, Icons.light_mode, const Color(0xFFFB923C), const Color(0xFFF8FAFC), '明亮', isDark)),
              const SizedBox(width: 12),
              Expanded(child: _buildThemeCard(1, Icons.dark_mode, const Color(0xFF818CF8), const Color(0xFF0F172A), '深色', isDark)),
              const SizedBox(width: 12),
              Expanded(child: _buildThemeCard(2, Icons.settings_brightness, const Color(0xFF60A5FA), const Color(0xFFE2E8F0), '系统', isDark)),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建主题卡片
  Widget _buildThemeCard(int index, IconData icon, Color iconColor, Color bgColor, String label, bool isDark) {
    final isSelected = _themeMode == index;
    return GestureDetector(
      onTap: () {
        setState(() => _themeMode = index);
        _saveSettings();
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? AppColors.primary : (isDark ? AppColors.borderDark : AppColors.border), width: isSelected ? 2 : 1),
        ),
        child: Column(
          children: [
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              ),
              child: Stack(
                children: [
                  Center(child: Icon(icon, size: 28, color: iconColor)),
                  if (isSelected)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                        child: const Icon(Icons.check, size: 10, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                border: Border(top: BorderSide(color: (isDark ? AppColors.borderDark : AppColors.border).withOpacity(0.5))),
              ),
              child: Center(
                child: Text(label, style: TextStyle(fontSize: 12, color: isSelected ? AppColors.primary : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondary))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建语言选择区域
  Widget _buildLanguageSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('系统语言', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('选择管理系统显示的语言。', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Expanded(child: _buildLanguageButton(0, '简体中文')),
                Expanded(child: _buildLanguageButton(1, 'English')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建语言按钮
  Widget _buildLanguageButton(int index, String label) {
    final isSelected = _language == index;
    return GestureDetector(
      onTap: () => setState(() => _language = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: isSelected ? const LinearGradient(colors: [Color(0xFF87CEEB), Color(0xFF60A5FA)]) : null,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  /// 构建字体大小区域
  Widget _buildFontSizeSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('全局字体大小', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${_fontSize.toInt()} pt', style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('调节界面文字显示的基准尺寸。', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: const Color(0xFFE2E8F0),
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withOpacity(0.1),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: _fontSize,
              min: 10,
              max: 18,
              divisions: 8,
              onChanged: (value) => setState(() => _fontSize = value),
              onChangeEnd: (_) => _saveSettings(),
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('最小', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
              Text('标准', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
              Text('最大', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建UI缩放区域
  Widget _buildUIScaleSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('UI缩放', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${(_uiScale * 100).toInt()}%', style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('调整整体界面缩放比例。', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: const Color(0xFFE2E8F0),
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withOpacity(0.1),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: _uiScale,
              min: 0.8,
              max: 1.5,
              divisions: 7,
              onChanged: (value) => setState(() => _uiScale = value),
              onChangeEnd: (_) => _saveSettings(),
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('80%', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
              Text('100%', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
              Text('150%', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建高级设置区域
  Widget _buildAdvancedSettings() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('高级设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('辅助功能与性能优化。', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          // 高对比度
          _buildSwitchItem(
            '高对比度',
            '增强界面元素的对比度',
            _highContrast,
            (value) {
              setState(() => _highContrast = value);
              _saveSettings();
            },
          ),
          const Divider(height: 24),
          // 减少动画
          _buildSwitchItem(
            '减少动画',
            '减少界面动画效果',
            _reduceMotion,
            (value) {
              setState(() => _reduceMotion = value);
              _saveSettings();
            },
          ),
        ],
      ),
    );
  }

  /// 构建开关项
  Widget _buildSwitchItem(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.primary,
        ),
      ],
    );
  }
}
