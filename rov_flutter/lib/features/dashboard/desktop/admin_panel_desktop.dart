/// 管理员面板 - 桌面端
/// 
/// 功能：今日核心概览、系统操作日志、用户角色管理、系统配置
/// 设计稿对应：win/admin_panel/screen.png
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/data_service.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/user_session.dart';

/// 管理员面板桌面端主界面
class AdminPanelDesktop extends StatefulWidget {
  const AdminPanelDesktop({super.key});

  @override
  State<AdminPanelDesktop> createState() => _AdminPanelDesktopState();
}

class _AdminPanelDesktopState extends State<AdminPanelDesktop> {
  // 系统配置选项状态
  bool _autoBackup = true;
  bool _aiAutoDetect = true;
  bool _alarmLimit = false;
  
  // 搜索关键词
  final TextEditingController _searchController = TextEditingController();

  // 日志数据
  List<LogEntry> _logs = [];
  List<LogEntry> _filteredLogs = [];
  bool _logsLoading = true;

  // 用户数据
  List<UserRole> _users = [];
  bool _usersLoading = true;

  // 分页
  int _currentPage = 0;
  final int _pageSize = 10;

  // 统计数据
  int _todayInspections = 128;
  int _alarmCount = 2;
  double _robotActiveRate = 98.5;
  int _cloudStorage = 412;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_filterLogs);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 加载数据
  Future<void> _loadData() async {
    // 加载日志：数据库控制日志优先，本地演示日志兜底
    final backendLogs = await _loadLogsFromBackend();
    final logs = backendLogs.isNotEmpty ? backendLogs : await DataService.loadLogs();
    // 加载用户：数据库为权威来源，后端不可用时才回退本地显示
    final backendUsers = await _loadUsersFromBackend();
    final users = backendUsers.isNotEmpty ? backendUsers : await DataService.loadUsers();

    setState(() {
      _logs = logs.isNotEmpty ? logs : _getDefaultLogs();
      _filteredLogs = _logs;
      _logsLoading = false;
      _users = users.isNotEmpty ? users : _getDefaultUsers();
      _usersLoading = false;
    });
  }

  /// 刷新用户列表
  Future<void> _refreshUsers() async {
    setState(() => _usersLoading = true);
    final backendUsers = await _loadUsersFromBackend();
    final users = backendUsers.isNotEmpty ? backendUsers : await DataService.loadUsers();
    setState(() {
      _users = users.isNotEmpty ? users : _getDefaultUsers();
      _usersLoading = false;
    });
  }

  /// 从 PC 后端数据库读取管理员列表
  Future<List<UserRole>> _loadUsersFromBackend() async {
    final token = UserSession().authToken;
    if (token == null || token.isEmpty) return [];
    try {
      final list = await ApiClient.listUsers(token);
      return list.map((item) {
        final realName = item['real_name']?.toString() ?? '';
        final username = item['username']?.toString() ?? '';
        final role = item['role']?.toString() ?? 'admin';
        return UserRole(
          id: (item['id'] as num?)?.toInt() ?? 0,
          name: realName.isNotEmpty ? realName : username,
          role: role == 'super_admin' ? '超级管理员' : (role == 'admin' ? '管理员' : role),
          permissions: const [],
          avatarPath: '',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// 从 PC 后端数据库读取控制日志
  Future<List<LogEntry>> _loadLogsFromBackend() async {
    final token = UserSession().authToken;
    if (token == null || token.isEmpty) return [];
    try {
      final rows = await ApiClient.listLogs(token, limit: 300);
      final logs = <LogEntry>[];
      for (final row in rows) {
        final ts = (row['ts'] as num?)?.toDouble() ?? 0;
        if (ts <= 0) continue;
        final dateTime = DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());
        String two(int value) => value.toString().padLeft(2, '0');
        logs.add(LogEntry(
          date: '${dateTime.year}-${two(dateTime.month)}-${two(dateTime.day)}',
          time: '${two(dateTime.hour)}:${two(dateTime.minute)}:${two(dateTime.second)}',
          operator: row['username']?.toString() ?? '系统',
          module: '设备控制',
          action: row['command']?.toString() ?? '',
          status: (row['ok'] as num?) == 1 ? LogStatus.success : LogStatus.error,
        ));
      }
      return logs;
    } catch (_) {
      return [];
    }
  }

  /// 获取默认日志数据
  List<LogEntry> _getDefaultLogs() {
    return [
      LogEntry(date: '2026-02-27', time: '14:32:15', operator: '系统', module: '设备管理', action: 'ROV-01 设备上线，初始化完成', status: LogStatus.success),
      LogEntry(date: '2026-02-27', time: '14:28:03', operator: '张海洋', module: '巡检任务', action: '启动区域A自动巡检任务', status: LogStatus.success),
      LogEntry(date: '2026-02-27', time: '13:45:10', operator: '系统', module: '报警系统', action: '检测到水温异常波动，已发送预警通知', status: LogStatus.warning),
      LogEntry(date: '2026-02-27', time: '11:20:15', operator: '系统', module: '设备管理', action: 'ROV-02 设备离线，信号中断', status: LogStatus.error),
      LogEntry(date: '2026-02-27', time: '10:55:42', operator: '系统', module: '数据备份', action: '每日自动备份完成，备份文件大小 2.3GB', status: LogStatus.success),
    ];
  }

  /// 获取默认用户数据
  List<UserRole> _getDefaultUsers() {
    return [
      UserRole(name: '张伟', role: '超级管理员', permissions: ['系统全权限', '日志导出'], avatarPath: 'assets/users/张伟/avatar.png'),
      UserRole(name: '王超', role: '系统维护员', permissions: ['参数校准', '故障上报'], avatarPath: 'assets/users/王超/avatar.png'),
    ];
  }

  /// 搜索过滤日志
  void _filterLogs() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredLogs = _logs;
      } else {
        _filteredLogs = _logs.where((log) =>
            log.operator.toLowerCase().contains(query) ||
            log.action.toLowerCase().contains(query) ||
            log.module.toLowerCase().contains(query)).toList();
      }
      _currentPage = 0;
    });
  }

  /// 导出日志 - 弹出保存对话框让用户选择路径
  Future<void> _exportLogs() async {
    final content = await DataService.exportLogs(_filteredLogs);
    final timestamp = DateTime.now().toString().replaceAll(':', '-').split('.')[0];
    final fileName = 'system_logs_$timestamp.csv';
    
    try {
      final filePath = await DataService.saveWithFilePicker(content, fileName);
      if (filePath == null) {
        // 用户取消了选择
        return;
      }
      if (mounted) {
        _showDownloadDialog(filePath, fileName);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// 显示下载完成对话框
  void _showDownloadDialog(String filePath, String fileName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.success),
            SizedBox(width: 8),
            Text('导出成功'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('文件已保存到：'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                filePath,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: filePath));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('路径已复制到剪贴板')),
              );
            },
            child: const Text('复制路径'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 显示添加用户对话框（写入 PC 后端 SQLite 数据库）
  void _showAddUserDialog() {
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    final roleController = TextEditingController(text: '管理员');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.person_add, color: AppColors.primary),
            SizedBox(width: 8),
            Text('添加用户'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '登录用户名 *',
                  hintText: '请输入用户名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码 *',
                  hintText: '请输入初始密码',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: roleController,
                decoration: const InputDecoration(
                  labelText: '角色 *',
                  hintText: '管理员 / 超级管理员',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final username = nameController.text.trim();
              final password = passwordController.text;
              final role = roleController.text.trim();
              if (username.isEmpty || password.isEmpty || role.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('用户名、密码和角色为必填项'), backgroundColor: AppColors.error),
                );
                return;
              }
              final token = UserSession().authToken;
              if (token == null || token.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('登录会话已失效，请重新登录'), backgroundColor: AppColors.error),
                );
                return;
              }

              try {
                await ApiClient.createUser(
                  token,
                  username: username,
                  password: password,
                  role: role.contains('超级') ? 'super_admin' : 'admin',
                  realName: username,
                );
              } on ApiException catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
                  );
                }
                return;
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('添加失败：$e'), backgroundColor: AppColors.error),
                  );
                }
                return;
              }

              Navigator.pop(dialogContext);
              await _refreshUsers();

              // 添加操作日志
              final now = DateTime.now();
              final log = LogEntry(
                date: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
                time: '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
                operator: '管理员',
                module: '用户管理',
                action: '添加用户: $username',
                status: LogStatus.success,
              );
              final updatedLogs = await DataService.addLog(log, _logs);
              setState(() {
                _logs = updatedLogs;
                _filteredLogs = updatedLogs;
              });

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('用户 $username 添加成功')),
                );
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  /// 显示添加机器人对话框
  void _showAddRobotDialog() {
    final idController = TextEditingController();
    final nameController = TextEditingController();
    final ipController = TextEditingController();
    final portController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.add_box, color: AppColors.primary),
            SizedBox(width: 8),
            Text('添加机器人'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idController,
                decoration: const InputDecoration(
                  labelText: '机器人ID *',
                  hintText: '如：ROV-04',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '机器人名称',
                  hintText: '如：海参检测机器人4号',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ipController,
                decoration: const InputDecoration(
                  labelText: 'IP地址 *',
                  hintText: '如：192.168.1.100',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: portController,
                decoration: const InputDecoration(
                  labelText: '端口 *',
                  hintText: '如：8080',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (idController.text.trim().isEmpty || 
                  ipController.text.trim().isEmpty || 
                  portController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请填写所有必填项'), backgroundColor: AppColors.error),
                );
                return;
              }
              
              // 添加操作日志
              final now = DateTime.now();
              final log = LogEntry(
                date: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
                time: '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
                operator: '管理员',
                module: '设备管理',
                action: '添加机器人: ${idController.text.trim()} (${ipController.text.trim()}:${portController.text.trim()})',
                status: LogStatus.success,
              );
              final updatedLogs = await DataService.addLog(log, _logs);
              setState(() {
                _logs = updatedLogs;
                _filteredLogs = updatedLogs;
              });
              
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('机器人 ${idController.text.trim()} 添加成功')),
              );
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  /// 运行全量自检
  Future<void> _runFullDiagnostics() async {
    // 显示进度对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在运行全量自检...'),
          ],
        ),
      ),
    );

    // 模拟自检过程
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      Navigator.pop(context); // 关闭进度对话框
      
      // 添加操作日志
      final now = DateTime.now();
      final log = LogEntry(
        date: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        time: '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
        operator: '系统',
        module: '系统诊断',
        action: '全量自检完成，系统运行正常',
        status: LogStatus.success,
      );
      final updatedLogs = await DataService.addLog(log, _logs);
      setState(() {
        _logs = updatedLogs;
        _filteredLogs = updatedLogs;
      });

      // 显示结果
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.success),
              SizedBox(width: 8),
              Text('自检完成'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('系统自检报告：'),
              SizedBox(height: 12),
              Text('• CPU状态: 正常 (使用率 23%)'),
              Text('• 内存状态: 正常 (使用率 45%)'),
              Text('• 网络连接: 正常 (延迟 12ms)'),
              Text('• 数据库: 正常 (响应时间 5ms)'),
              Text('• 存储空间: 正常 (剩余 588GB)'),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderSection(),
            const SizedBox(height: 24),
            _buildStatsGrid(),
            const SizedBox(height: 24),
            _buildMainContent(),
          ],
        ),
      ),
    );
  }

  /// 构建顶部标题区域
  Widget _buildHeaderSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('今日核心概览', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            SizedBox(height: 4),
            Text('系统当前运行状态及实时运营指标汇总', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          ],
        ),
        Row(
          children: [
            _buildOutlineButton(icon: Icons.history, label: '历史周报', onTap: _showHistoryReportDialog),
            const SizedBox(width: 12),
            _buildPrimaryButton(icon: Icons.add, label: '添加机器人', onTap: _showAddRobotDialog),
          ],
        ),
      ],
    );
  }

  /// 显示历史周报对话框
  void _showHistoryReportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.history, color: AppColors.primary),
            SizedBox(width: 8),
            Text('历史周报'),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 300,
          child: ListView(
            children: [
              _buildReportItem('2026年第9周报告', '2026-02-24 ~ 2026-03-02', '系统运行正常，完成巡检任务 896 次'),
              _buildReportItem('2026年第8周报告', '2026-02-17 ~ 2026-02-23', '系统运行正常，完成巡检任务 912 次'),
              _buildReportItem('2026年第7周报告', '2026-02-10 ~ 2026-02-16', '发现2次设备异常，已处理'),
              _buildReportItem('2026年第6周报告', '2026-02-03 ~ 2026-02-09', '系统运行正常，完成巡检任务 878 次'),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportItem(String title, String date, String summary) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.description, color: AppColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(date, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
            Text(summary, style: const TextStyle(fontSize: 12)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.download),
          onPressed: () async {
            final content = '# $title\n日期范围: $date\n\n## 概要\n$summary\n\n## 详细报告\n系统运行稳定，各项指标正常。';
            final fileName = '${title.replaceAll(' ', '_')}.txt';
            try {
              final filePath = await DataService.saveWithFilePicker(content, fileName);
              if (filePath == null) {
                // 用户取消了选择
                return;
              }
              Navigator.pop(context);
              _showDownloadDialog(filePath, fileName);
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('下载失败: $e'), backgroundColor: AppColors.error),
              );
            }
          },
        ),
      ),
    );
  }

  /// 构建统计卡片网格
  Widget _buildStatsGrid() {
    return Row(
      children: [
        Expanded(child: _buildStatCard(icon: Icons.memory, iconBgColor: AppColors.primary.withOpacity(0.1), iconColor: AppColors.primary, title: '今日巡检次数', value: '128', unit: '次', trend: '+12%', trendUp: true)),
        const SizedBox(width: 16),
        Expanded(child: _buildStatCard(icon: Icons.report_problem, iconBgColor: AppColors.error.withOpacity(0.1), iconColor: AppColors.error, title: '实时报警统计', value: '02', unit: '个', trend: '↑', trendUp: false, trendColor: AppColors.error)),
        const SizedBox(width: 16),
        Expanded(child: _buildStatCard(icon: Icons.verified_user, iconBgColor: AppColors.success.withOpacity(0.1), iconColor: AppColors.success, title: '机器人活跃率', value: '98.5', unit: '%', trend: '+0.5%', trendUp: true)),
        const SizedBox(width: 16),
        Expanded(child: _buildStatCard(icon: Icons.cloud_queue, iconBgColor: const Color(0xFF9370DB).withOpacity(0.1), iconColor: const Color(0xFF9370DB), title: '云端存储空间', value: '412', unit: 'GB')),
      ],
    );
  }

  /// 构建主要内容区域
  Widget _buildMainContent() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _buildLogTable()),
        const SizedBox(width: 24),
        Expanded(flex: 1, child: Column(
          children: [
            _buildUserRolesCard(),
            const SizedBox(height: 24),
            _buildSystemConfigCard(),
            const SizedBox(height: 24),
            _buildQuickAccessButtons(),
          ],
        )),
      ],
    );
  }

  /// 构建统计卡片
  Widget _buildStatCard({required IconData icon, required Color iconBgColor, required Color iconColor, required String title, required String value, required String unit, String? trend, bool trendUp = true, Color? trendColor}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: iconColor, size: 22)),
              const SizedBox(height: 16),
              Text(title, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  const SizedBox(width: 4),
                  Text(unit, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                ],
              ),
            ],
          ),
          if (trend != null)
            Positioned(
              top: 0, right: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (trendUp) Icon(Icons.north_east, size: 12, color: trendColor ?? AppColors.success),
                  Text(trend, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: trendColor ?? (trendUp ? AppColors.success : AppColors.error))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 构建系统操作日志表格
  Widget _buildLogTable() {
    // 计算当前页的日志
    final startIndex = _currentPage * _pageSize;
    final endIndex = (startIndex + _pageSize).clamp(0, _filteredLogs.length);
    final pageData = _filteredLogs.sublist(startIndex, endIndex);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          // 表格头部
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('系统操作日志', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    SizedBox(height: 2),
                    Text('从 system_logs.csv 实时读取', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
                  ],
                ),
                Row(
                  children: [
                    SizedBox(
                      width: 240,
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: '搜索操作人或动作...',
                          hintStyle: const TextStyle(fontSize: 14, color: AppColors.textHint),
                          prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textHint),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildSmallOutlineButton(icon: Icons.filter_list, label: '筛选', onTap: () {}),
                    const SizedBox(width: 8),
                    _buildSmallOutlineButton(icon: Icons.ios_share, label: '导出', onTap: _exportLogs),
                  ],
                ),
              ],
            ),
          ),
          // 表格内容
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border, width: 0.5))),
            child: Column(
              children: [
                // 表头
                Container(
                  color: const Color(0xFFF8FAFC),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: const Row(
                    children: [
                      Expanded(flex: 2, child: Text('操作时间', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                      Expanded(flex: 1, child: Text('操作人', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                      Expanded(flex: 1, child: Text('动作模块', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('动作内容', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                      Expanded(flex: 1, child: Text('状态', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                    ],
                  ),
                ),
                // 数据行
                if (_logsLoading)
                  const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())
                else if (pageData.isEmpty)
                  const Padding(padding: EdgeInsets.all(40), child: Text('暂无日志数据', style: TextStyle(color: AppColors.textHint)))
                else
                  ...pageData.map((log) => _buildLogRow(log)),
              ],
            ),
          ),
          // 分页区域
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border, width: 0.5))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('共计 ${_filteredLogs.length} 条操作记录', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                Row(
                  children: [
                    _buildPaginationButton('上一页', enabled: _currentPage > 0, onTap: () => setState(() => _currentPage--)),
                    const SizedBox(width: 8),
                    Text('${_currentPage + 1} / ${((_filteredLogs.length - 1) ~/ _pageSize) + 1}', style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                    const SizedBox(width: 8),
                    _buildPaginationButton('下一页', enabled: endIndex < _filteredLogs.length, onTap: () => setState(() => _currentPage++)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建日志表格行
  Widget _buildLogRow(LogEntry log) {
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5))),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {},
          hoverColor: const Color(0xFFF8FAFC),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(log.date, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
                  Text(log.time, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                ])),
                Expanded(flex: 1, child: Text(log.operator, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary))),
                Expanded(flex: 1, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
                  child: Text(log.module, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                )),
                Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(left: 12), child: Text(log.action, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)))),
                Expanded(flex: 1, child: Align(alignment: Alignment.centerRight, child: _buildStatusBadge(log.status))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建状态徽章
  Widget _buildStatusBadge(LogStatus status) {
    switch (status) {
      case LogStatus.success:
        return const Text('成功', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.success));
      case LogStatus.warning:
        return const Text('警告', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.warning));
      case LogStatus.error:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(4)),
          child: const Text('错误', style: TextStyle(fontSize: 12, color: Colors.white)),
        );
    }
  }

  /// 构建用户与角色卡片
  Widget _buildUserRolesCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(children: [
                Icon(Icons.people_outline, color: AppColors.primary, size: 20),
                SizedBox(width: 8),
                Text('用户与角色', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
              ]),
              Row(
                children: [
                  IconButton(
                    onPressed: _refreshUsers, 
                    icon: const Icon(Icons.refresh, color: AppColors.textHint, size: 20), 
                    padding: EdgeInsets.zero, 
                    constraints: const BoxConstraints(),
                    tooltip: '刷新用户列表',
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _showAddUserDialog, 
                    icon: const Icon(Icons.add_circle_outline, color: AppColors.textHint, size: 22), 
                    padding: EdgeInsets.zero, 
                    constraints: const BoxConstraints(),
                    tooltip: '添加用户',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('从 assets/users 目录动态读取', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
          const SizedBox(height: 12),
          if (_usersLoading)
            const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())
          else
            ..._users.map((user) => Padding(padding: const EdgeInsets.only(bottom: 20), child: _buildUserItem(user))),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _showPermissionManagementDialog,
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), side: const BorderSide(color: AppColors.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('管理所有权限', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示权限管理对话框 - 从 assets/users 动态读取
  void _showPermissionManagementDialog() {
    // 从用户列表中提取所有权限并统计哪些用户拥有这些权限
    final permissionMap = <String, List<String>>{};
    for (final user in _users) {
      for (final permission in user.permissions) {
        if (!permissionMap.containsKey(permission)) {
          permissionMap[permission] = [];
        }
        permissionMap[permission]!.add(user.name);
      }
    }
    
    // 权限描述映射
    final permissionDescriptions = {
      '系统全权限': '完全控制系统所有功能',
      '日志导出': '导出系统操作日志',
      '实时监控': '查看视频监控和设备状态',
      '硬件调整': '控制机器人硬件参数',
      '参数校准': '校准传感器和设备参数',
      '故障上报': '提交和管理故障报告',
      '数据分析': '查看和导出数据报表',
    };

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings, color: AppColors.primary),
            SizedBox(width: 8),
            Text('权限管理'),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('系统权限列表', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('(来源: assets/users)', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
                ],
              ),
              const SizedBox(height: 8),
              // 显示所有用户及其角色
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        children: _users.map((u) => Chip(
                          avatar: CircleAvatar(
                            backgroundColor: AppColors.primary,
                            child: Text(u.name[0], style: const TextStyle(fontSize: 10, color: Colors.white)),
                          ),
                          label: Text('${u.name} (${u.role})', style: const TextStyle(fontSize: 11)),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        )).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: permissionMap.entries.map((entry) => _buildPermissionRow(
                    entry.key,
                    permissionDescriptions[entry.key] ?? '系统功能权限',
                    entry.value,
                  )).toList(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionRow(String permission, String description, List<String> users) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(permission, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(description, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Wrap(
                spacing: 4,
                children: users.map((u) => Chip(
                  label: Text(u, style: const TextStyle(fontSize: 10)),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                )).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建用户项
  Widget _buildUserItem(UserRole user) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头像 - 尝试从本地文件加载，失败则显示默认头像
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: ClipOval(
            child: Image.asset(
              user.avatarPath,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                // 显示默认头像（首字母）
                return Center(child: Text(user.name.isNotEmpty ? user.name[0] : '?', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)));
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(user.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text(user.role, style: const TextStyle(fontSize: 10, color: AppColors.primary)),
                      ),
                      if (user.id != 0)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.error),
                          tooltip: '删除用户',
                          onPressed: () => _deleteUser(user),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8, runSpacing: 4,
                children: user.permissions.map((p) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
                  child: Text(p, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                )).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 删除用户（后端数据库校验，超级管理员不可删除）
  Future<void> _deleteUser(UserRole user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除用户'),
        content: Text('确定删除用户「${user.name}」吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final token = UserSession().authToken;
    if (token == null || token.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('登录会话已失效，请重新登录'), backgroundColor: AppColors.error),
        );
      }
      return;
    }
    try {
      final result = await ApiClient.deleteUser(token, user.id);
      if (result['ok'] == true) {
        await _refreshUsers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('用户「${user.name}」已删除')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['error']?.toString() ?? '删除失败'), backgroundColor: AppColors.error),
          );
        }
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：$e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// 构建系统配置卡片
  Widget _buildSystemConfigCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.list_alt, color: AppColors.primary, size: 20),
            SizedBox(width: 8),
            Text('系统配置快选', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
          ]),
          const SizedBox(height: 20),
          _buildConfigOption(title: '数据自动备份', subtitle: '每 24 小时增量备份', value: _autoBackup, onChanged: (v) => _toggleConfig('autoBackup', v)),
          const SizedBox(height: 16),
          _buildConfigOption(title: 'AI 异常自动识别', subtitle: '实时分析视频流', value: _aiAutoDetect, onChanged: (v) => _toggleConfig('aiAutoDetect', v)),
          const SizedBox(height: 16),
          _buildConfigOption(title: '报警推送限制', subtitle: '仅限高级别预警', value: _alarmLimit, onChanged: (v) => _toggleConfig('alarmLimit', v), isRadio: true),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _runFullDiagnostics,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.auto_fix_high, size: 18, color: Colors.white),
                SizedBox(width: 8),
                Text('运行全量自检', style: TextStyle(fontSize: 14, color: Colors.white)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// 切换配置并记录日志
  Future<void> _toggleConfig(String configName, bool value) async {
    String configTitle;
    switch (configName) {
      case 'autoBackup':
        setState(() => _autoBackup = value);
        configTitle = '数据自动备份';
        break;
      case 'aiAutoDetect':
        setState(() => _aiAutoDetect = value);
        configTitle = 'AI异常自动识别';
        break;
      case 'alarmLimit':
        setState(() => _alarmLimit = value);
        configTitle = '报警推送限制';
        break;
      default:
        return;
    }
    
    // 添加操作日志
    final now = DateTime.now();
    final log = LogEntry(
      date: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      time: '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
      operator: '管理员',
      module: '系统配置',
      action: '$configTitle: ${value ? "已启用" : "已禁用"}',
      status: LogStatus.success,
    );
    final updatedLogs = await DataService.addLog(log, _logs);
    setState(() {
      _logs = updatedLogs;
      _filteredLogs = updatedLogs;
    });
  }

  /// 构建配置选项
  Widget _buildConfigOption({required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged, bool isRadio = false}) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20, height: 20, margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: value ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(isRadio ? 10 : 4),
              border: Border.all(color: value ? AppColors.primary : AppColors.border, width: 1.5),
            ),
            child: value ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: value ? AppColors.textPrimary : AppColors.textHint)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建快捷入口按钮
  Widget _buildQuickAccessButtons() {
    return Row(
      children: [
        Expanded(child: _buildQuickButton(icon: Icons.settings_remote, iconBgColor: AppColors.primary.withOpacity(0.1), iconColor: AppColors.primary, label: '控制台', onTap: () {})),
        const SizedBox(width: 16),
        Expanded(child: _buildQuickButton(icon: Icons.insert_chart, iconBgColor: const Color(0xFF6366F1).withOpacity(0.1), iconColor: const Color(0xFF6366F1), label: '分析', onTap: () {})),
      ],
    );
  }

  /// 构建快捷按钮
  Widget _buildQuickButton({required IconData icon, required Color iconBgColor, required Color iconColor, required String label, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: const Color(0xFFF8FAFC),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Column(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: iconColor, size: 22)),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
          ]),
        ),
      ),
    );
  }

  Widget _buildOutlineButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: const Color(0xFFF8FAFC),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 1))]),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
          ]),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 14, color: Colors.white)),
          ]),
        ),
      ),
    );
  }

  Widget _buildSmallOutlineButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: const Color(0xFFF8FAFC),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          ]),
        ),
      ),
    );
  }

  Widget _buildPaginationButton(String label, {required bool enabled, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        hoverColor: enabled ? const Color(0xFFF8FAFC) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: enabled ? AppColors.border : AppColors.border.withOpacity(0.5))),
          child: Text(label, style: TextStyle(fontSize: 12, color: enabled ? AppColors.textPrimary : AppColors.textHint)),
        ),
      ),
    );
  }
}
