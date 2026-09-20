/// 应用主入口文件
/// 
/// 配置MaterialApp、路由、主题
/// 实现自适应布局的Dashboard路由器
library;

import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_colors.dart';
import 'core/utils/responsive.dart';
import 'core/l10n/strings.dart';
import 'core/services/settings_provider.dart';
import 'core/services/rov_backend_service.dart';
import 'features/auth/login_screen.dart';
import 'features/shared/app_header.dart';
import 'features/shared/widgets/motion_kit.dart';
import 'features/shared/widgets/emergency_orb.dart';
import 'features/dashboard/desktop/main_control_desktop.dart';
import 'features/dashboard/desktop/admin_panel_desktop.dart';
import 'features/dashboard/desktop/data_analysis_desktop.dart';
import 'features/dashboard/desktop/operate_desktop.dart';
import 'features/dashboard/desktop/settings_desktop.dart';
import 'features/dashboard/mobile/main_control_mobile.dart';
// 契约§8/E 轮次说明：移动端仅保留 主控 + 设置 两个真实页面；
// admin_panel_mobile / data_analysis_mobile 演示页因内容未真实化（含硬编码
// 假统计/假指标，铁律②）已整文件删除；管理员与数据分析以桌面端真实实现为准。
import 'features/dashboard/mobile/settings_mobile.dart';

/// 应用主入口组件 - 包裹设置监听
class ROVApp extends StatefulWidget {
  const ROVApp({super.key});

  @override
  State<ROVApp> createState() => _ROVAppState();
}

class _ROVAppState extends State<ROVApp> {
  final _settingsProvider = SettingsProvider();

  @override
  void initState() {
    super.initState();
    _settingsProvider.initialize();
    _settingsProvider.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _settingsProvider.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    setState(() {}); // 刷新UI以应用新设置
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settingsProvider;
    
    return MaterialApp(
      title: '海参检测机器人管理系统',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme.copyWith(
        textTheme: _buildScaledTextTheme(AppTheme.lightTheme.textTheme, settings.fontSize),
      ),
      darkTheme: AppTheme.darkTheme.copyWith(
        textTheme: _buildScaledTextTheme(AppTheme.darkTheme.textTheme, settings.fontSize),
      ),
      themeMode: settings.currentThemeMode,
      builder: (context, child) {
        // 应用UI缩放
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(settings.uiScale),
          ),
          child: child ?? const SizedBox(),
        );
      },
      initialRoute: '/',
      onGenerateRoute: (routeSettings) => _generateRoute(routeSettings, settings),
    );
  }

  /// 构建缩放后的文字主题
  TextTheme _buildScaledTextTheme(TextTheme base, double fontSize) {
    final scale = fontSize / 14.0;
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(fontSize: (base.displayLarge?.fontSize ?? 57) * scale),
      displayMedium: base.displayMedium?.copyWith(fontSize: (base.displayMedium?.fontSize ?? 45) * scale),
      displaySmall: base.displaySmall?.copyWith(fontSize: (base.displaySmall?.fontSize ?? 36) * scale),
      headlineLarge: base.headlineLarge?.copyWith(fontSize: (base.headlineLarge?.fontSize ?? 32) * scale),
      headlineMedium: base.headlineMedium?.copyWith(fontSize: (base.headlineMedium?.fontSize ?? 28) * scale),
      headlineSmall: base.headlineSmall?.copyWith(fontSize: (base.headlineSmall?.fontSize ?? 24) * scale),
      titleLarge: base.titleLarge?.copyWith(fontSize: (base.titleLarge?.fontSize ?? 22) * scale),
      titleMedium: base.titleMedium?.copyWith(fontSize: (base.titleMedium?.fontSize ?? 16) * scale),
      titleSmall: base.titleSmall?.copyWith(fontSize: (base.titleSmall?.fontSize ?? 14) * scale),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: (base.bodyLarge?.fontSize ?? 16) * scale),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: (base.bodyMedium?.fontSize ?? 14) * scale),
      bodySmall: base.bodySmall?.copyWith(fontSize: (base.bodySmall?.fontSize ?? 12) * scale),
      labelLarge: base.labelLarge?.copyWith(fontSize: (base.labelLarge?.fontSize ?? 14) * scale),
      labelMedium: base.labelMedium?.copyWith(fontSize: (base.labelMedium?.fontSize ?? 12) * scale),
      labelSmall: base.labelSmall?.copyWith(fontSize: (base.labelSmall?.fontSize ?? 11) * scale),
    );
  }

  /// 路由生成器
  ///
  /// 转场统一走 Motion Kit 的 AppPageTransition（淡入 + 微位移，STYLE_SPEC §9），
  /// reduceMotion 时时长归零、组件内部短路为直接呈现。
  Route<dynamic>? _generateRoute(RouteSettings settings, SettingsProvider settingsProvider) {
    final reduceMotion = settingsProvider.reduceMotion;

    switch (settings.name) {
      case '/':
        return PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
          transitionsBuilder: AppPageTransition.routeTransitionsBuilder,
          transitionDuration:
              reduceMotion ? Duration.zero : MotionTokens.pageRoute,
        );
      case '/dashboard':
        return PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const DashboardRouter(),
          transitionsBuilder: AppPageTransition.routeTransitionsBuilder,
          transitionDuration:
              reduceMotion ? Duration.zero : MotionTokens.dashboardRoute,
        );
      default:
        return PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
          transitionsBuilder: AppPageTransition.routeTransitionsBuilder,
          transitionDuration:
              reduceMotion ? Duration.zero : MotionTokens.pageRoute,
        );
    }
  }
}

/// Dashboard路由器 - 根据平台自动选择界面
class DashboardRouter extends StatefulWidget {
  const DashboardRouter({super.key});

  @override
  State<DashboardRouter> createState() => _DashboardRouterState();
}

class _DashboardRouterState extends State<DashboardRouter> {
  int _currentIndex = 2; // 默认显示主控页面

  void _navigateTo(int index) {
    if (index == _currentIndex) return;
    // 页签转场由 AnimatedSwitcher + AppPageTransition 驱动：
    // 新页淡入+上浮、旧页淡出交叉进行（300ms，easeOutCubic），
    // reduceMotion 时时长归零、转场组件内部短路为直接呈现。
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      mobile: _buildMobileLayout(),
      desktop: _buildDesktopLayout(),
    );
  }

/// 构建桌面端布局
///
/// 悬浮急停球 overlay（EmergencyOrb）挂在整个 shell 之上：默认停靠屏幕
/// 右缘垂直居中，不遮挡页内既有急停按钮；登录页路由不挂载本 overlay。
Widget _buildDesktopLayout() {
  return Stack(
    children: [
      Scaffold(
        body: Column(
          children: [
            // 通用顶部导航栏
            AppHeader(
              currentIndex: _currentIndex,
              onNavigate: _navigateTo,
            ),
            // 契约§8：backend_mode == sim 时全页黄色角标（位于 AppHeader 下方）
            _buildSimModeBanner(),
            // 页面内容（页签切换：淡入+微位移，AppPageTransition）
            Expanded(
              child: AnimatedSwitcher(
                duration: Motion.durationOrZero(MotionTokens.normal),
                transitionBuilder: (child, animation) => AppPageTransition(
                  animation: animation,
                  // 页签内容比整页路由更克制：上浮 2%
                  offset: const Offset(0, 0.02),
                  child: child,
                ),
                // 过渡期新旧两页同屏：均撑满内容区，避免交叉时尺寸跳动
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
                    ...previousChildren,
                    ?currentChild,
                  ],
                ),
                child: KeyedSubtree(
                  key: ValueKey<int>(_currentIndex),
                  child: _buildDesktopContent(),
                ),
              ),
            ),
            // 底部状态栏
            _buildDesktopFooter(),
          ],
        ),
      ),
      const EmergencyOrb(),
    ],
  );
}

/// 全局"仿真数据"角标（契约§8）
///
/// backend_mode 取自服务层 status 消息（telemetryNotifier.status.backend_mode）：
/// - sim → 显示黄色细条"⚠ 仿真数据——非真实硬件回传"；
/// - rdk / 未知（未登录、未连接）→ 不显示。未登录时本就无任何数据推送，
///   不显示角标不会造成"假真实"误导。
Widget _buildSimModeBanner() {
  return ValueListenableBuilder<TelemetrySnapshot?>(
    valueListenable: RovBackendService().telemetryNotifier,
    builder: (context, snapshot, _) {
      final mode = snapshot?.status['backend_mode']?.toString();
      if (mode != 'sim') return const SizedBox.shrink();
      return Container(
        width: double.infinity,
        color: AppColors.warning.withValues(alpha: 0.18),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
        child: Text(
          '⚠ ${AppStrings.simulatedDataBadge}——非真实硬件回传',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.warning,
          ),
        ),
      );
    },
  );
}

  /// 构建桌面端内容
  Widget _buildDesktopContent() {
    switch (_currentIndex) {
      case 0:
        return const AdminPanelDesktop();
      case 1:
        return const OperateDesktop();
      case 2:
        return const MainControlDesktop();
      case 3:
        return const DataAnalysisDesktop();
      case 4:
        return const SettingsDesktop();
      default:
        return const MainControlDesktop();
    }
  }

  /// 构建桌面端底部状态栏
  Widget _buildDesktopFooter() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        border: Border(
          top: BorderSide(color: isDark ? AppColors.borderDark : AppColors.border),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textHint,
            ),
          ),
          // 右侧状态组：真实连接状态（connectionNotifier）+ 平滑过渡
          _buildFooterStatus(isDark: isDark),
        ],
      ),
    );
  }

  /// 底部状态栏右侧：连接状态圆点与文案，随 connectionNotifier 真实状态平滑过渡
  ///
  /// - 圆点：AnimatedContainer 150ms 变色（绿=已连接 / 黄=重连中 / 红=离线）；
  /// - 文案：AnimatedSwitcher 交叉淡入淡出，内容为服务层维护的 conn.message；
  /// - reduceMotion 时时长归零，直接呈现目标状态。
  Widget _buildFooterStatus({required bool isDark}) {
    final textStyle = TextStyle(
      fontSize: 12,
      color: isDark ? AppColors.textSecondaryDark : AppColors.textHint,
    );
    return Flexible(
      child: ValueListenableBuilder<RovConnectionState>(
        valueListenable: RovBackendService().connectionNotifier,
        builder: (context, conn, _) {
          final dotColor = switch (conn.phase) {
            RovConnectionPhase.connected => AppColors.success,
            RovConnectionPhase.reconnecting => AppColors.warning,
            RovConnectionPhase.offline => AppColors.danger,
          };
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: Motion.durationOrZero(MotionTokens.fast),
                curve: MotionTokens.standard,
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: Motion.durationOrZero(MotionTokens.fast),
                switchInCurve: MotionTokens.standard,
                switchOutCurve: MotionTokens.exit,
                // 左对齐叠放：新旧文案交叉淡入淡出时不水平跳动
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    ...previousChildren,
                    ?currentChild,
                  ],
                ),
                child: Text(
                  '${conn.message} (v3.0.0)',
                  key: ValueKey<String>(conn.message),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 构建移动端布局
  ///
  /// E 轮次：移动端仅保留 主控 + 设置 两个真实页面；管理员/数据分析
  /// 两个演示页已从导航隐藏（桌面端仍为完整实现）。
  ///
  /// 同桌面端：shell 顶层挂悬浮急停球 overlay，登录页路由不挂载。
  Widget _buildMobileLayout() {
    return Stack(
      children: [
        Scaffold(
          body: Column(
            children: [
              Expanded(
                child: IndexedStack(
                  index: _mobileIndexMap(_currentIndex),
                  children: const [
                    MainControlMobile(),
                    SettingsMobile(),
                  ],
                ),
              ),
              // 契约§8：仿真模式角标（移动端位于底部导航栏上方）
              _buildSimModeBanner(),
            ],
          ),
          bottomNavigationBar: _buildBottomNav(),
        ),
        const EmergencyOrb(),
      ],
    );
  }

  /// 移动端索引映射（移动端只有 2 个页面：主控、设置）
  int _mobileIndexMap(int desktopIndex) {
    // 桌面端: 0-管理员, 1-控制操作, 2-主控, 3-数据分析, 4-设置
    // 移动端: 0-主控, 1-设置
    switch (desktopIndex) {
      case 4:
        return 1; // 设置
      case 0:
      case 1:
      case 2:
      case 3:
      default:
        return 0; // 其余（含主控）归并到主控页
    }
  }

  /// 构建底部导航栏
  Widget _buildBottomNav() {
    final mobileIndex = _mobileIndexMap(_currentIndex);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.sports_esports_outlined, Icons.sports_esports, '主控', mobileIndex == 0),
              _buildNavItem(1, Icons.settings_outlined, Icons.settings, '设置', mobileIndex == 1),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建底部导航项
  Widget _buildNavItem(int index, IconData icon, IconData activeIcon, String label, bool isSelected) {
    return GestureDetector(
      onTap: () {
        // 移动端索引转换：0→主控(桌面索引2)，1→设置(桌面索引4)
        final desktopIndexes = [2, 4];
        setState(() => _currentIndex = desktopIndexes[index]);
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              size: 24,
              color: isSelected ? AppColors.primary : AppColors.textHint,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? AppColors.primary : AppColors.textHint,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
