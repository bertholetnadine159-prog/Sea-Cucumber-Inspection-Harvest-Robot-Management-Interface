import 'package:flutter/material.dart';

/// 响应式布局工具类
/// 根据屏幕宽度判断设备类型并提供自适应布局方法
class Responsive {
  Responsive._();

  // ============ 断点定义 ============
  /// 手机端最大宽度
  static const double mobileMaxWidth = 767;

  /// 平板端最大宽度
  static const double tabletMaxWidth = 1023;

  /// 桌面端最小宽度
  static const double desktopMinWidth = 1024;

  /// 宽屏桌面最小宽度
  static const double wideDesktopMinWidth = 1440;

  // ============ 设备类型判断 ============
  /// 是否为手机端
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width <= mobileMaxWidth;
  }

  /// 是否为平板端
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width > mobileMaxWidth && width <= tabletMaxWidth;
  }

  /// 是否为桌面端
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= desktopMinWidth;
  }

  /// 是否为宽屏桌面
  static bool isWideDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= wideDesktopMinWidth;
  }

  /// 是否为移动设备（手机或平板）
  static bool isMobileOrTablet(BuildContext context) {
    return MediaQuery.of(context).size.width < desktopMinWidth;
  }

  // ============ 屏幕尺寸获取 ============
  /// 获取屏幕宽度
  static double screenWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  /// 获取屏幕高度
  static double screenHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }

  /// 获取内容区域宽度（考虑安全区域）
  static double contentWidth(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    return MediaQuery.of(context).size.width - padding.left - padding.right;
  }

  /// 获取内容区域高度（考虑安全区域）
  static double contentHeight(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    return MediaQuery.of(context).size.height - padding.top - padding.bottom;
  }

  // ============ 响应式数值 ============
  /// 根据设备类型返回不同值
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    required T desktop,
  }) {
    if (isDesktop(context)) {
      return desktop;
    } else if (isTablet(context)) {
      return tablet ?? mobile;
    }
    return mobile;
  }

  /// 根据屏幕宽度比例计算值
  static double widthPercent(BuildContext context, double percent) {
    return screenWidth(context) * percent / 100;
  }

  /// 根据屏幕高度比例计算值
  static double heightPercent(BuildContext context, double percent) {
    return screenHeight(context) * percent / 100;
  }

  // ============ 网格列数 ============
  /// 获取推荐的网格列数
  static int gridColumns(BuildContext context) {
    return value(context, mobile: 2, tablet: 3, desktop: 4);
  }

  /// 获取推荐的内容最大宽度
  static double maxContentWidth(BuildContext context) {
    return value(context, mobile: double.infinity, tablet: 768, desktop: 1200);
  }
}

/// 响应式布局构建器
/// 根据设备类型自动选择对应的Widget
class ResponsiveBuilder extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;

  const ResponsiveBuilder({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    if (Responsive.isDesktop(context)) {
      return desktop;
    } else if (Responsive.isTablet(context) && tablet != null) {
      return tablet!;
    }
    return mobile;
  }
}

/// 响应式可见性组件
/// 根据设备类型控制组件显示/隐藏
class ResponsiveVisibility extends StatelessWidget {
  final Widget child;
  final bool visibleOnMobile;
  final bool visibleOnTablet;
  final bool visibleOnDesktop;

  const ResponsiveVisibility({
    super.key,
    required this.child,
    this.visibleOnMobile = true,
    this.visibleOnTablet = true,
    this.visibleOnDesktop = true,
  });

  @override
  Widget build(BuildContext context) {
    if (Responsive.isDesktop(context) && !visibleOnDesktop) {
      return const SizedBox.shrink();
    }
    if (Responsive.isTablet(context) && !visibleOnTablet) {
      return const SizedBox.shrink();
    }
    if (Responsive.isMobile(context) && !visibleOnMobile) {
      return const SizedBox.shrink();
    }
    return child;
  }
}
