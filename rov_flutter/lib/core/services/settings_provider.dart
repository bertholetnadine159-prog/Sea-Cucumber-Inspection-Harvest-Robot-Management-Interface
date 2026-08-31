/// 全局设置服务
/// 
/// 管理应用的显示设置，包括主题模式、字体大小、UI缩放等
/// 设置变化时会通知所有监听者
library;

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';

/// 设置提供者 - 单例模式
class SettingsProvider extends ChangeNotifier {
  static final SettingsProvider _instance = SettingsProvider._internal();
  factory SettingsProvider() => _instance;
  SettingsProvider._internal();

  // === 显示设置 ===
  int _themeMode = 0; // 0=明亮, 1=深色, 2=跟随系统
  double _fontSize = 14.0;
  bool _highContrast = false;
  bool _reduceMotion = false;
  double _uiScale = 1.0;

  // === 语言与地区 ===
  int _language = 0; // 0=简体中文, 1=English, 2=日本語
  int _dateFormat = 0; // 0=YYYY-MM-DD, 1=MM/DD/YYYY, 2=DD/MM/YYYY
  int _timeFormat = 0; // 0=24小时, 1=12小时

  bool _initialized = false;
  String? _settingsFilePath;

  // Getters
  int get themeMode => _themeMode;
  double get fontSize => _fontSize;
  bool get highContrast => _highContrast;
  bool get reduceMotion => _reduceMotion;
  double get uiScale => _uiScale;
  int get language => _language;
  int get dateFormat => _dateFormat;
  int get timeFormat => _timeFormat;
  bool get initialized => _initialized;

  /// 获取当前主题模式
  ThemeMode get currentThemeMode {
    switch (_themeMode) {
      case 0:
        return ThemeMode.light;
      case 1:
        return ThemeMode.dark;
      case 2:
      default:
        return ThemeMode.system;
    }
  }

  /// 判断当前是否为深色模式
  bool isDarkMode(BuildContext context) {
    if (_themeMode == 0) return false;
    if (_themeMode == 1) return true;
    // 跟随系统
    final brightness = SchedulerBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark;
  }

  /// 获取动画时长（减少动画时返回0）
  Duration getAnimationDuration(Duration normalDuration) {
    return _reduceMotion ? Duration.zero : normalDuration;
  }

  /// 获取缩放后的字体大小
  double getScaledFontSize(double baseFontSize) {
    final scale = _fontSize / 14.0;
    return baseFontSize * scale;
  }

  /// 初始化设置
  Future<void> initialize() async {
    if (_initialized) return;
    await _loadSettings();
    _initialized = true;
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
        _themeMode = data['themeMode'] ?? 0;
        _fontSize = (data['fontSize'] ?? 14).toDouble();
        _highContrast = data['highContrast'] ?? false;
        _reduceMotion = data['reduceMotion'] ?? false;
        _uiScale = (data['uiScale'] ?? 1.0).toDouble();
        _language = data['language'] ?? 0;
        _dateFormat = data['dateFormat'] ?? 0;
        _timeFormat = data['timeFormat'] ?? 0;
        notifyListeners();
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
        'themeMode': _themeMode,
        'fontSize': _fontSize,
        'highContrast': _highContrast,
        'reduceMotion': _reduceMotion,
        'uiScale': _uiScale,
        'language': _language,
        'dateFormat': _dateFormat,
        'timeFormat': _timeFormat,
      };

      await file.writeAsString(json.encode(data));
    } catch (e) {
      // 保存失败
    }
  }

  // === 设置更新方法 ===

  /// 设置主题模式
  void setThemeMode(int mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      _saveSettings();
      notifyListeners();
    }
  }

  /// 设置字体大小
  void setFontSize(double size) {
    if (_fontSize != size) {
      _fontSize = size;
      _saveSettings();
      notifyListeners();
    }
  }

  /// 设置高对比度模式
  void setHighContrast(bool enabled) {
    if (_highContrast != enabled) {
      _highContrast = enabled;
      _saveSettings();
      notifyListeners();
    }
  }

  /// 设置减少动画
  void setReduceMotion(bool enabled) {
    if (_reduceMotion != enabled) {
      _reduceMotion = enabled;
      _saveSettings();
      notifyListeners();
    }
  }

  /// 设置UI缩放
  void setUiScale(double scale) {
    if (_uiScale != scale) {
      _uiScale = scale;
      _saveSettings();
      notifyListeners();
    }
  }

  /// 设置语言
  void setLanguage(int lang) {
    if (_language != lang) {
      _language = lang;
      _saveSettings();
      notifyListeners();
    }
  }

  /// 设置日期格式
  void setDateFormat(int format) {
    if (_dateFormat != format) {
      _dateFormat = format;
      _saveSettings();
      notifyListeners();
    }
  }

  /// 设置时间格式
  void setTimeFormat(int format) {
    if (_timeFormat != format) {
      _timeFormat = format;
      _saveSettings();
      notifyListeners();
    }
  }

  /// 重置为默认设置
  void resetToDefaults() {
    _themeMode = 0;
    _fontSize = 14.0;
    _highContrast = false;
    _reduceMotion = false;
    _uiScale = 1.0;
    _language = 0;
    _dateFormat = 0;
    _timeFormat = 0;
    _saveSettings();
    notifyListeners();
  }

  /// 批量更新设置
  void updateSettings({
    int? themeMode,
    double? fontSize,
    bool? highContrast,
    bool? reduceMotion,
    double? uiScale,
    int? language,
    int? dateFormat,
    int? timeFormat,
  }) {
    bool changed = false;

    if (themeMode != null && _themeMode != themeMode) {
      _themeMode = themeMode;
      changed = true;
    }
    if (fontSize != null && _fontSize != fontSize) {
      _fontSize = fontSize;
      changed = true;
    }
    if (highContrast != null && _highContrast != highContrast) {
      _highContrast = highContrast;
      changed = true;
    }
    if (reduceMotion != null && _reduceMotion != reduceMotion) {
      _reduceMotion = reduceMotion;
      changed = true;
    }
    if (uiScale != null && _uiScale != uiScale) {
      _uiScale = uiScale;
      changed = true;
    }
    if (language != null && _language != language) {
      _language = language;
      changed = true;
    }
    if (dateFormat != null && _dateFormat != dateFormat) {
      _dateFormat = dateFormat;
      changed = true;
    }
    if (timeFormat != null && _timeFormat != timeFormat) {
      _timeFormat = timeFormat;
      changed = true;
    }

    if (changed) {
      _saveSettings();
      notifyListeners();
    }
  }
}
