import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/user_session.dart';

/// 桌面端顶部导航栏
/// 包含Logo、导航菜单、通知和用户信息
class AppHeader extends StatelessWidget {
  final int currentIndex;
  final Function(int) onNavigate;

  const AppHeader({
    super.key,
    required this.currentIndex,
    required this.onNavigate,
  });

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

  /// 构建导航菜单
  Widget _buildNavMenu() {
    final navItems = [
      _NavItemData(Icons.person_search, '管理员', 0),
      _NavItemData(Icons.tune, '操作', 1),
      _NavItemData(Icons.dashboard, '主控', 2),
      _NavItemData(Icons.bar_chart, '数据分析', 3),
      _NavItemData(Icons.settings, '设置', 4),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: navItems.map((item) {
        final isActive = currentIndex == item.index;
        return _buildNavItem(
          icon: item.icon,
          label: item.label,
          isActive: isActive,
          onTap: () => onNavigate(item.index),
        );
      }).toList(),
    );
  }

  /// 构建单个导航项
  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
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
              icon,
              size: 20,
              color: isActive ? AppColors.primary : AppColors.textSecondaryLight,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: isActive
                  ? AppTextStyles.navItemActive
                  : AppTextStyles.navItem.copyWith(
                      color: AppColors.textSecondaryLight,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建右侧工具栏
  Widget _buildToolbar(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 通知按钮
        _buildNotificationButton(),
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

  /// 构建通知按钮
  Widget _buildNotificationButton() {
    return Stack(
      children: [
        IconButton(
          onPressed: () {},
          icon: const Icon(
            Icons.notifications_outlined,
            color: AppColors.textSecondaryLight,
          ),
        ),
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
  }

  /// 构建用户信息
  Widget _buildUserInfo(BuildContext context) {
    final session = UserSession();
    final displayName = session.displayName;
    final displayRole = session.displayRole;
    
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
            subtitle: Text(session.displayRole),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<void>(
          onTap: () {
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

  _NavItemData(this.icon, this.label, this.index);
}
