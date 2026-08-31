import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// 应用文本样式定义
/// 基于HTML设计稿提取的字体规范
class AppTextStyles {
  AppTextStyles._();

  // ============ 中文字体 (宋体系列) ============
  /// 获取中文文本样式基础
  static TextStyle _chineseBase({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.notoSerifSc(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? AppColors.textPrimaryLight,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  // ============ 英文字体 (Times New Roman / Inter) ============
  /// 获取英文衬线体文本样式
  static TextStyle _englishSerif({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.ptSerif(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? AppColors.textPrimaryLight,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  /// 获取英文无衬线体文本样式
  static TextStyle _englishSans({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? AppColors.textPrimaryLight,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  // ============ 标题样式 ============
  /// 大标题 - 页面主标题
  static TextStyle get h1 => _chineseBase(
        fontSize: 30,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
      );

  /// 中标题 - 区块标题
  static TextStyle get h2 => _chineseBase(
        fontSize: 24,
        fontWeight: FontWeight.bold,
      );

  /// 小标题 - 卡片标题
  static TextStyle get h3 => _chineseBase(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      );

  /// 副标题
  static TextStyle get subtitle => _chineseBase(
        fontSize: 16,
        fontWeight: FontWeight.w500,
      );

  // ============ 正文样式 ============
  /// 正文大
  static TextStyle get bodyLarge => _chineseBase(
        fontSize: 16,
        height: 1.6,
      );

  /// 正文中
  static TextStyle get bodyMedium => _chineseBase(
        fontSize: 14,
        height: 1.5,
      );

  /// 正文小
  static TextStyle get bodySmall => _chineseBase(
        fontSize: 12,
        height: 1.5,
      );

  // ============ 辅助文字样式 ============
  /// 标签文字
  static TextStyle get label => _chineseBase(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondaryLight,
      );

  /// 提示文字
  static TextStyle get caption => _chineseBase(
        fontSize: 10,
        color: AppColors.textTertiaryLight,
      );

  /// 按钮文字
  static TextStyle get button => _chineseBase(
        fontSize: 16,
        fontWeight: FontWeight.bold,
      );

  // ============ 数据展示样式 ============
  /// 大数据展示 - 统计卡片数字
  static TextStyle get dataLarge => _englishSans(
        fontSize: 36,
        fontWeight: FontWeight.bold,
      );

  /// 中数据展示
  static TextStyle get dataMedium => _englishSans(
        fontSize: 24,
        fontWeight: FontWeight.bold,
      );

  /// 小数据展示
  static TextStyle get dataSmall => _englishSans(
        fontSize: 20,
        fontWeight: FontWeight.bold,
      );

  /// 单位文字
  static TextStyle get dataUnit => _englishSans(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: AppColors.textTertiaryLight,
      );

  // ============ 特殊样式 ============
  /// 英文副标题 - 用于双语标题
  static TextStyle get englishSubtitle => _englishSerif(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 2,
        color: AppColors.textSecondaryLight,
      );

  /// 时间戳样式
  static TextStyle get timestamp => _englishSans(
        fontSize: 12,
        color: AppColors.textTertiaryLight,
      );

  /// 坐标显示样式
  static TextStyle get coordinate => _englishSans(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
      );

  /// 导航菜单样式
  static TextStyle get navItem => _chineseBase(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      );

  /// 导航菜单激活样式
  static TextStyle get navItemActive => _chineseBase(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.primary,
      );

  // ============ 深色模式变体 ============
  /// 为深色模式提供颜色变体
  static TextStyle withDarkColor(TextStyle style) {
    return style.copyWith(color: AppColors.textPrimaryDark);
  }

  /// 自定义颜色变体
  static TextStyle withColor(TextStyle style, Color color) {
    return style.copyWith(color: color);
  }
}
