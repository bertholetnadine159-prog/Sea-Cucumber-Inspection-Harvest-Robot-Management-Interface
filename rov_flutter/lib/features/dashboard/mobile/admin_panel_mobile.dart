/// 管理面板 - 移动端
/// 
/// 功能：统计概览、系统操作日志、用户角色、系统配置
/// 设计稿对应：app/admin_panel/screen.png
library;

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../shared/bottom_nav_bar.dart';

/// 移动端管理面板
class AdminPanelMobile extends StatelessWidget {
  const AdminPanelMobile({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : null,
      body: CustomScrollView(
        slivers: [
          // 渐变搜索头部
          SliverToBoxAdapter(child: _buildHeader(context)),
          // 内容区域
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 统计卡片
                  _buildStatsCards(),
                  const SizedBox(height: 24),
                  
                  // 系统操作日志
                  _buildLogSection(),
                  const SizedBox(height: 24),
                  
                  // 用户与角色
                  _buildUserRolesSection(),
                  const SizedBox(height: 24),
                  
                  // 系统配置快选
                  _buildConfigSection(),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建渐变搜索头部
  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 20,
      ),
      decoration: const BoxDecoration(
        gradient: AppColors.headerGradient,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '海参检测系统',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white.withOpacity(0.2),
                child: const Icon(Icons.person, color: Colors.white, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 搜索框
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(Icons.search, color: Colors.white.withOpacity(0.7), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '搜索机器人或日志...',
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today, size: 14, color: AppColors.textSecondary),
                      SizedBox(width: 4),
                      Text('今日', style: TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建统计卡片
  Widget _buildStatsCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildStatCard(Icons.memory, const Color(0xFF3B82F6), '今日巡检次数', '128', '次', '+12%', true)),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard(Icons.warning, const Color(0xFFEF4444), '实时报警统计', '02', '个', '+2', false)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildStatCard(Icons.verified, const Color(0xFF10B981), '机器人活跃率', '98.5', '%', '+0.5%', true)),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard(Icons.cloud, const Color(0xFF8B5CF6), '云端存储空间', '412', 'GB', null, true)),
          ],
        ),
      ],
    );
  }

  /// 构建单个统计卡片
  Widget _buildStatCard(IconData icon, Color color, String title, String value, String unit, String? trend, bool isPositive) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              if (trend != null)
                Text(
                  trend,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isPositive ? AppColors.success : AppColors.error,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              Text(unit, style: const TextStyle(fontSize: 14, color: AppColors.textHint)),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建日志区域
  Widget _buildLogSection() {
    final logs = [
      ('张伟', '控制操作', '调整下潜深度至 5.2m', '2024-05-20 14:32:10', '成功'),
      ('李娜', '主控界面', '切换至红外监控模式', '2024-05-20 14:15:22', '成功'),
      ('系统自检', '核心服务', '电池电量低于 20%', '2024-05-20 13:58:45', '警告'),
      ('系统后台', '云存储', '连接数据库超时', '2024-05-20 13:22:05', '错误'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('系统操作日志', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            TextButton(
              onPressed: () {},
              child: const Text('查看全部 >', style: TextStyle(color: AppColors.primary, fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...logs.map((log) => _buildLogItem(log.$1, log.$2, log.$3, log.$4, log.$5)),
      ],
    );
  }

  /// 构建日志项
  Widget _buildLogItem(String operator, String module, String action, String time, String status) {
    Color statusColor;
    switch (status) {
      case '成功':
        statusColor = AppColors.success;
        break;
      case '警告':
        statusColor = AppColors.warning;
        break;
      default:
        statusColor = AppColors.error;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.backgroundLight,
            child: const Icon(Icons.person, size: 20, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(operator, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(module, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(action, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text(time, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              ],
            ),
          ),
          Text(status, style: TextStyle(fontWeight: FontWeight.bold, color: statusColor)),
        ],
      ),
    );
  }

  /// 构建用户与角色区域
  Widget _buildUserRolesSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.people, color: AppColors.primary, size: 20),
                  SizedBox(width: 8),
                  Text('用户与角色', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const Icon(Icons.add, color: AppColors.textSecondary),
            ],
          ),
          const SizedBox(height: 16),
          // 头像组
          Row(
            children: [
              ...List.generate(3, (i) => Container(
                margin: EdgeInsets.only(right: i < 2 ? 0 : 0),
                transform: Matrix4.translationValues(i * -8.0, 0, 0),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.backgroundLight,
                  child: const Icon(Icons.person, size: 18, color: AppColors.textSecondary),
                ),
              )),
              Container(
                transform: Matrix4.translationValues(-24, 0, 0),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('+5', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 管理按钮
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text('管理所有权限', style: TextStyle(color: AppColors.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建系统配置区域
  Widget _buildConfigSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text('系统配置快选', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 20),
          _buildConfigItem(Icons.cloud_upload, '数据自动备份', '每 24 小时增量备份', true),
          const SizedBox(height: 16),
          _buildConfigItem(Icons.psychology, 'AI 异常自动识别', '实时分析视频流', true),
          const SizedBox(height: 24),
          // 自检按钮
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF87CEEB), Color(0xFF60A5FA)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text('运行全量自检', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建配置项
  Widget _buildConfigItem(IconData icon, String title, String subtitle, bool checked) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
            ],
          ),
        ),
        if (checked)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 14, color: Colors.white),
          ),
      ],
    );
  }
}
