import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/user_session.dart';
import '../../core/services/rov_backend_service.dart';
import 'utils/command_link.dart';
import 'widgets/stale_badge.dart';

/// 桌面端顶部导航栏
/// 包含Logo、导航菜单、通知和用户信息
///
/// 权限预告（管理员反馈#7/新用户反馈#2）：「管理员」「数据分析」仅对
/// super_admin/admin 开放；其他角色置灰 + 锁形图标 + tooltip 预告
/// "需要管理员权限"，不再让普通用户点进去撞 403 错误页。
/// 通知铃铛只接真实信号（StaleBadge 同源：遥测超时/后端断链才亮红点），
/// 不再是常亮红点的死按钮。
class AppHeader extends StatelessWidget {
  final int currentIndex;
  final Function(int) onNavigate;

  const AppHeader({
    super.key,
    required this.currentIndex,
    required this.onNavigate,
  });

  /// 角色中文名（与设置页 _mapRole 同口径，另补操作员）
  static String _roleLabel(String role) {
    switch (role) {
      case 'super_admin':
        return '超级管理员';
      case 'admin':
        return '管理员';
      case 'operator':
        return '操作员';
      default:
        return role.isEmpty ? '普通用户' : role;
    }
  }

  /// 当前登录角色是否可见管理员区域（管理员面板 / 数据分析）
  static bool _canSeeAdminArea() {
    final role = UserSession().currentUser?.role ?? '';
    return role == 'super_admin' || role == 'admin';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppConstants.headerHeight,
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderLight,
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Logo和标题
          _buildLogo(),
          const SizedBox(width: 48),
          // 导航菜单
          Expanded(child: _buildNavMenu()),
          // 右侧工具栏
          _buildToolbar(context),
        ],
      ),
    );
  }

  /// 构建Logo
  Widget _buildLogo() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.waves,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          AppConstants.appName,
          style: AppTextStyles.h3.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// 构建导航菜单（按角色预告：管理员区域对无权限角色置灰+锁形）
  Widget _buildNavMenu() {
    final navItems = [
      _NavItemData(Icons.person_search, '管理员', 0, adminOnly: true),
      _NavItemData(Icons.tune, '操作', 1),
      _NavItemData(Icons.dashboard, '主控', 2),
      _NavItemData(Icons.bar_chart, '数据分析', 3, adminOnly: true),
      _NavItemData(Icons.settings, '设置', 4),
    ];
    final canSeeAdminArea = _canSeeAdminArea();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: navItems.map((item) {
        final isActive = currentIndex == item.index;
        final locked = item.adminOnly && !canSeeAdminArea;
        return _buildNavItem(
          icon: item.icon,
          label: item.label,
          isActive: isActive,
          locked: locked,
          onTap: locked ? null : () => onNavigate(item.index),
        );
      }).toList(),
    );
  }

  /// 构建单个导航项（locked 时置灰 + 锁形 + tooltip，点击不响应）
  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required bool locked,
    required VoidCallback? onTap,
  }) {
    final itemColor = locked
        ? AppColors.textHint
        : (isActive ? AppColors.primary : AppColors.textSecondaryLight);
    final Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isActive ? AppColors.primary : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            locked ? Icons.lock_outline : icon,
            size: 20,
            color: itemColor,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: isActive && !locked
                ? AppTextStyles.navItemActive
                : AppTextStyles.navItem.copyWith(
                    color: itemColor,
                  ),
          ),
        ],
      ),
    );
    if (locked) {
      return Tooltip(
        message: '需要管理员权限',
        child: Opacity(opacity: 0.55, child: content),
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: content,
    );
  }

  /// 构建右侧工具栏
  Widget _buildToolbar(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 通知按钮（真实告警信号）
        _buildNotificationButton(context),
        const SizedBox(width: 16),
        // 分割线
        Container(
          width: 1,
          height: 32,
          color: AppColors.borderLight,
        ),
        const SizedBox(width: 16),
        // 用户信息
        _buildUserInfo(context),
      ],
    );
  }

  /// 构建通知按钮：红点只由真实链路状态驱动（StaleBadge 同源判据）——
  /// 后端断链/重连中，或遥测超过 5 秒未更新（遥测超时）才亮；
  /// 点击弹出真实状态说明，不再是空回调死按钮 + 常亮红点。
  Widget _buildNotificationButton(BuildContext context) {
    return ValueListenableBuilder<RovConnectionState>(
      valueListenable: RovBackendService().connectionNotifier,
      builder: (context, conn, _) {
        return ValueListenableBuilder<TelemetrySnapshot?>(
          valueListenable: RovBackendService().telemetryNotifier,
          builder: (context, telemetry, _) {
            final linkDown = conn.phase != RovConnectionPhase.connected;
            final telemetryStale = StaleBadge.isStale(telemetry?.lastUpdated);
            final hasAlarm = linkDown || telemetryStale;
            return Stack(
              children: [
                IconButton(
                  onPressed: () => _showLinkStatusMenu(context, conn, telemetry),
                  tooltip: '链路状态',
                  icon: Icon(
                    linkDown
                        ? Icons.notifications_off_outlined
                        : Icons.notifications_outlined,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
                if (hasAlarm)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// 链路状态弹层（全部真实数据：连接状态 + 遥测最后更新时刻）
  void _showLinkStatusMenu(
    BuildContext context,
    RovConnectionState conn,
    TelemetrySnapshot? telemetry,
  ) {
    final telemetryStale = StaleBadge.isStale(telemetry?.lastUpdated);
    final lastUpdated = telemetry?.lastUpdated;
    String two(int v) => v.toString().padLeft(2, '0');
    final updatedText = lastUpdated == null
        ? '尚未收到遥测'
        : '${two(lastUpdated.hour)}:${two(lastUpdated.minute)}:${two(lastUpdated.second)}';
    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width - 280,
        AppConstants.headerHeight,
        16,
        0,
      ),
      items: <PopupMenuEntry<void>>[
        PopupMenuItem<void>(
          enabled: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      conn.phase == RovConnectionPhase.connected
                          ? Icons.check_circle
                          : Icons.link_off,
                      size: 16,
                      color: conn.phase == RovConnectionPhase.connected
                          ? AppColors.success
                          : AppColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text('后端链路：${conn.message}')),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      telemetryStale ? Icons.warning_amber_rounded : Icons.sensors,
                      size: 16,
                      color: telemetryStale ? AppColors.warning : AppColors.success,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        telemetryStale ? '遥测信号丢失（≥5 秒未更新）' : '遥测正常，最后更新 $updatedText',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 构建用户信息
  Widget _buildUserInfo(BuildContext context) {
    final session = UserSession();
    final displayName = session.displayName;
    final displayRole = _roleLabel(session.displayRole);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              displayName.isNotEmpty ? displayName : '未登录',
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              displayRole.isNotEmpty ? displayRole : '访客',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () => _showUserMenu(context),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(
                displayName.isNotEmpty ? displayName[0] : '?',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 显示用户菜单
  void _showUserMenu(BuildContext context) {
    final session = UserSession();
    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width - 200,
        AppConstants.headerHeight,
        0,
        0,
      ),
      items: <PopupMenuEntry<void>>[
        PopupMenuItem<void>(
          child: ListTile(
            leading: const Icon(Icons.person),
            title: Text(session.displayName),
            subtitle: Text(_roleLabel(session.displayRole)),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<void>(
          onTap: () {
            // 登出闭环：先尽力向服务端发送 auth/logout 吊销会话行
            // （令牌被拷走后旧会话即刻失效；WS 可能已断，失败不阻断本地清理），
            // 再清本地会话并返回登录页。
            final token = session.authToken ?? '';
            if (token.isNotEmpty) {
              unawaited(CommandLink.revokeSession(
                serverAddress: RovBackendService().serverAddress,
                token: token,
              ));
            }
            session.logout();
            Navigator.pushReplacementNamed(context, '/');
          },
          child: const ListTile(
            leading: Icon(Icons.logout, color: AppColors.error),
            title: Text('退出登录', style: TextStyle(color: AppColors.error)),
          ),
        ),
      ],
    );
  }
}

/// 导航项数据类
class _NavItemData {
  final IconData icon;
  final String label;
  final int index;

  /// 是否仅管理员角色可见可点（管理员面板 / 数据分析）
  final bool adminOnly;

  _NavItemData(this.icon, this.label, this.index, {this.adminOnly = false});
}
