import 'package:flutter/material.dart';

/// 应用颜色常量定义
/// 基于HTML设计稿提取的色彩规范
class AppColors {
  AppColors._();

  // ============ 主色调 ============
  /// 主色 - 蓝色
  static const Color primary = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF2563EB);
  static const Color primaryLight = Color(0xFF60A5FA);

  // ============ 渐变色 ============
  /// 头部渐变起始色 - 天蓝色
  static const Color gradientStart = Color(0xFF87CEEB);

  /// 头部渐变结束色 - 紫色
  static const Color gradientEnd = Color(0xFF9370DB);

  /// 头部渐变
  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientEnd],
  );

  // ============ 语义色 ============
  /// 成功/正常状态
  static const Color success = Color(0xFF10B981);
  static const Color successLight = Color(0xFFD1FAE5);

  /// 警告状态
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);

  /// 错误/危险状态
  static const Color danger = Color(0xFFEF4444);
  static const Color dangerLight = Color(0xFFFEE2E2);

  /// 紧急停止
  static const Color emergency = Color(0xFFFF0000);

  // ============ 中性色 ============
  /// 背景色 - 浅色模式
  static const Color backgroundLight = Color(0xFFF8FAFC);
  static const Color backgroundLightAlt = Color(0xFFF3F4F6);

  /// 背景色 - 深色模式
  static const Color backgroundDark = Color(0xFF0F172A);
  static const Color backgroundDarkAlt = Color(0xFF111827);

  /// 卡片/表面色 - 浅色模式
  static const Color surfaceLight = Color(0xFFFFFFFF);

  /// 卡片/表面色 - 深色模式
  static const Color surfaceDark = Color(0xFF1E293B);

  /// 边框色
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color borderDark = Color(0xFF334155);

  // ============ 文字色 ============
  /// 主文字色 - 浅色模式
  static const Color textPrimaryLight = Color(0xFF1F2937);
  static const Color textSecondaryLight = Color(0xFF6B7280);
  static const Color textTertiaryLight = Color(0xFF9CA3AF);

  /// 主文字色 - 深色模式
  static const Color textPrimaryDark = Color(0xFFF3F4F6);
  static const Color textSecondaryDark = Color(0xFF9CA3AF);
  static const Color textTertiaryDark = Color(0xFF6B7280);

  // ============ 图表色 ============
  /// PH值图表色 - 蓝色
  static const Color chartBlue = Color(0xFF3B82F6);

  /// 温度图表色 - 红色
  static const Color chartRed = Color(0xFFF87171);

  /// 盐度图表色 - 紫色
  static const Color chartPurple = Color(0xFFA855F7);

  /// 气压图表色 - 绿色
  static const Color chartGreen = Color(0xFF10B981);

  // ============ 阴影色 ============
  /// 卡片阴影色
  static const Color shadowLight = Color(0xFFE8E8E8);
  static const Color shadowDark = Color(0x40000000);

  // ============ 特殊色 ============
  /// 毛玻璃背景
  static const Color glassWhite = Color(0xF2FFFFFF);
  static const Color glassDark = Color(0x80000000);

  /// 遮罩层
  static const Color overlay = Color(0x33000000);
  static const Color overlayDark = Color(0x99000000);

  // ============ 便捷别名 (默认浅色模式) ============
  /// 主文字色
  static const Color textPrimary = textPrimaryLight;
  /// 次要文字色
  static const Color textSecondary = textSecondaryLight;
  /// 提示文字色/禁用色
  static const Color textHint = textTertiaryLight;
  /// 边框色
  static const Color border = borderLight;
  /// 错误色
  static const Color error = danger;
}
