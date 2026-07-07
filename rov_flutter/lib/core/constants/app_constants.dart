/// 应用常量定义
/// 包含尺寸、间距、动画时长等常量
class AppConstants {
  AppConstants._();

  // ============ 应用信息 ============
  /// 应用名称
  static const String appName = '海参检测机器人管理系统';

  /// 应用英文名称
  static const String appNameEn = 'ROV Management System';

  /// 版本号
  static const String version = 'v2.1.0';

  /// 版权信息
  static const String copyright = '';

  // ============ 间距常量 ============
  /// 超小间距
  static const double spacingXs = 4.0;

  /// 小间距
  static const double spacingSm = 8.0;

  /// 中间距
  static const double spacingMd = 16.0;

  /// 大间距
  static const double spacingLg = 24.0;

  /// 超大间距
  static const double spacingXl = 32.0;

  /// 页面水平内边距
  static const double pagePaddingH = 24.0;

  /// 页面垂直内边距
  static const double pagePaddingV = 24.0;

  /// 卡片内边距
  static const double cardPadding = 20.0;

  // ============ 圆角常量 ============
  /// 小圆角
  static const double radiusSm = 4.0;

  /// 中圆角
  static const double radiusMd = 8.0;

  /// 大圆角
  static const double radiusLg = 12.0;

  /// 超大圆角
  static const double radiusXl = 16.0;

  /// 圆形圆角
  static const double radiusRound = 24.0;

  /// 完全圆形
  static const double radiusCircle = 999.0;

  // ============ 图标尺寸 ============
  /// 小图标
  static const double iconSm = 16.0;

  /// 中图标
  static const double iconMd = 24.0;

  /// 大图标
  static const double iconLg = 32.0;

  /// 超大图标
  static const double iconXl = 48.0;

  // ============ 头像尺寸 ============
  /// 小头像
  static const double avatarSm = 32.0;

  /// 中头像
  static const double avatarMd = 40.0;

  /// 大头像
  static const double avatarLg = 64.0;

  // ============ 按钮尺寸 ============
  /// 按钮高度 - 小
  static const double buttonHeightSm = 32.0;

  /// 按钮高度 - 中
  static const double buttonHeightMd = 44.0;

  /// 按钮高度 - 大
  static const double buttonHeightLg = 56.0;

  // ============ 输入框尺寸 ============
  /// 输入框高度
  static const double inputHeight = 48.0;

  // ============ 动画时长 ============
  /// 快速动画
  static const Duration animationFast = Duration(milliseconds: 150);

  /// 正常动画
  static const Duration animationNormal = Duration(milliseconds: 300);

  /// 慢速动画
  static const Duration animationSlow = Duration(milliseconds: 500);

  // ============ 布局常量 ============
  /// 顶部导航栏高度
  static const double headerHeight = 64.0;

  /// 底部导航栏高度
  static const double bottomNavHeight = 64.0;

  /// 侧边栏宽度
  static const double sidebarWidth = 256.0;

  /// 内容最大宽度
  static const double maxContentWidth = 1600.0;

  /// 卡片最小宽度
  static const double cardMinWidth = 280.0;

  // ============ 网络图片 ============
  /// 水下背景图
  static const String underwaterBgUrl =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuDXYooQ0DN8BgeYPnsz3EhhZ1IvlebwlxqF6c_LVMvTO3gumcL2ZtdtpNC3JqLWzR9OwlLzQaMsi__uHi3Rm6kWAVmzuQAJLO7g5UBjFiMuD8ifGtWkf26JDnX5-4iC79gOssNumvDM7F987LRWnA5Fw7C0b4FCjWMLVj3C41ECXpONRSs_0JODsHlq25_WtTEz6L5DihYD6-obuhxsK8kquVWmAiK6IYgTUNpMVoZKCSYpbd2sFaeOZxZ6BrVAlcvIId5-nh57_5wF';

  static const String cameraFeedUrl = 'http://127.0.0.1:5000/video_feed';

  /// 默认头像
  static const String defaultAvatarUrl =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuCk4f3qD4EbFc-TxFCO4HLoqnx8l-vsR6YmDXNNoqhlamNdUACOKjWYn9486HD03jYXViV18dDWyT6DsRuqc8ontESDLSQdrpyWujbLMBqb7h2spyXpOajjK42HRT7Coa3B5gGs0epBGtI-4sw2OCq4BibqGxRzRBZbNPg1qlfXie5q1psWKGRlesa_oq28-GR4e_i7V7XLH6FNTvEkwamIyTO6-EqoWVUTLd9DZAt2h57nLeKufg4tw95xwO6tA7vNc6GL1MXhn-k6';
}

/// 导航菜单项定义
enum NavItem {
  admin('管理员', 'person_search'),
  operate('控制操作', 'tune'),
  main('主控', 'dashboard'),
  dataAnalysis('数据分析', 'bar_chart'),
  settings('设置', 'settings');

  final String label;
  final String icon;

  const NavItem(this.label, this.icon);
}
