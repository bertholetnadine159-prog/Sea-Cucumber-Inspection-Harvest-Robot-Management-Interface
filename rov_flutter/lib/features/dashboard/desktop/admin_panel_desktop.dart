/// 管理员面板 - 桌面端
///
/// 功能：系统实时概览（真实统计）、系统操作日志、用户管理、系统状态（只读）、
///       RDK X5 地址配置、链路诊断。
/// 数据溯源（契约§7）：全部 KPI 来自 GET /api/stats（本地后端 SQLite，
/// 传感器指标仅统计 source='rdk' 真实链路）；日志来自 GET /api/logs；
/// 用户来自 GET /api/users。无真实数据时显示空态/错误态，不回退合成数据。
/// Wave 2 变更：删除假 KPI（128/2/98.5/412）、_getDefaultLogs/_getDefaultUsers、
/// 假配置开关、假自检与假周报；新增 30s 统计轮询与链路诊断。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/services/data_service.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/user_session.dart';
import '../../../core/services/rov_backend_service.dart';
import '../../shared/widgets/motion_kit.dart';
import '../../shared/widgets/stale_badge.dart';

/// 管理员面板桌面端主界面
class AdminPanelDesktop extends StatefulWidget {
  const AdminPanelDesktop({super.key});

  @override
  State<AdminPanelDesktop> createState() => _AdminPanelDesktopState();
}

class _AdminPanelDesktopState extends State<AdminPanelDesktop> {
  /// KPI 轮询周期（30 秒）
  static const Duration _statsPollInterval = Duration(seconds: 30);

  // 统计数据（GET /api/stats，仅统计 source='rdk' 真实链路）
  Map<String, dynamic>? _stats;
  DateTime? _statsFetchedAt;
  String? _statsError;
  Timer? _statsTimer;

  // 系统健康状态（GET /api/health：backend_mode / rdk / 摄像头能力）
  Map<String, dynamic>? _health;
  String? _healthError;

  // 搜索关键词
  final TextEditingController _searchController = TextEditingController();

  // RDK 地址输入（初值由 /api/health 回填，避免硬编码假地址）
  final TextEditingController _rdkHostController = TextEditingController();
  final TextEditingController _rdkPortController = TextEditingController();
  bool _rdkFieldsFilled = false;

  // 日志数据（GET /api/logs，后端数据库为唯一来源）
  List<LogEntry> _logs = [];
  List<LogEntry> _filteredLogs = [];
  bool _logsLoading = true;
  String? _logsError;

  // 用户数据（GET /api/users，后端数据库为唯一来源）
  List<UserRole> _users = [];
  bool _usersLoading = true;
  String? _usersError;

  // 分页
  int _currentPage = 0;
  final int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _statsTimer = Timer.periodic(_statsPollInterval, (_) => _loadStats());
    _searchController.addListener(_filterLogs);
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _searchController.dispose();
    _rdkHostController.dispose();
    _rdkPortController.dispose();
    super.dispose();
  }

  /// 首次加载：统计 + 健康 + 日志 + 用户
  Future<void> _loadAll() async {
    await Future.wait([
      _loadStats(),
      _loadLogs(),
      _refreshUsers(),
    ]);
  }

  // ============ 统计（/api/stats，30s 轮询） ============

  Future<void> _loadStats() async {
    final token = UserSession().authToken;
    if (token == null || token.isEmpty) {
      _setStatsState(error: '未登录，无法读取统计');
      return;
    }
    try {
      final stats = await _StatsApi.fetch(token);
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _statsFetchedAt = DateTime.now();
        _statsError = null;
      });
    } catch (e) {
      _setStatsState(error: e.toString());
    }
    // 统计加载完成后顺带刷新系统健康状态
    _loadHealth();
  }

  void _setStatsState({required String error}) {
    if (!mounted) return;
    setState(() => _statsError = error);
  }

  /// 读取系统健康状态（/api/health）：backend_mode、RDK 连接、摄像头能力
  Future<void> _loadHealth() async {
    try {
      final health = await ApiClient.health();
      if (!mounted) return;
      setState(() {
        _health = health;
        _healthError = null;
        _fillRdkFields(health);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _healthError = e.toString());
    }
  }

  /// 用真实网关地址回填 RDK 输入框（仅首次，避免覆盖用户输入）
  void _fillRdkFields(Map<String, dynamic> health) {
    if (_rdkFieldsFilled) return;
    final rdk = health['rdk'] as Map<String, dynamic>? ?? {};
    final host = rdk['host']?.toString();
    final port = rdk['port']?.toString();
    if (host != null && host.isNotEmpty) _rdkHostController.text = host;
    if (port != null && port.isNotEmpty) _rdkPortController.text = port;
    _rdkFieldsFilled = true;
  }

  // ============ 日志（/api/logs） ============

  Future<void> _loadLogs() async {
    final token = UserSession().authToken;
    if (token == null || token.isEmpty) {
      _setLogsState([], '登录会话已失效，请重新登录');
      return;
    }
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
      _setLogsState(logs, null);
    } catch (e) {
      _setLogsState([], '日志读取失败：$e');
    }
  }

  void _setLogsState(List<LogEntry> logs, String? error) {
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _filteredLogs = logs;
      _logsLoading = false;
      _logsError = error;
      _currentPage = 0;
    });
  }

  // ============ 用户（/api/users） ============

  /// 刷新用户列表（后端数据库为唯一权威来源）
  Future<void> _refreshUsers() async {
    if (!mounted) return;
    setState(() {
      _usersLoading = true;
      _usersError = null;
    });
    final token = UserSession().authToken;
    if (token == null || token.isEmpty) {
      _setUsersState([], '登录会话已失效，请重新登录');
      return;
    }
    try {
      final list = await ApiClient.listUsers(token);
      final users = list.map((item) {
        final map = item as Map<String, dynamic>;
        final realName = map['real_name']?.toString() ?? '';
        final username = map['username']?.toString() ?? '';
        final role = map['role']?.toString() ?? 'admin';
        return UserRole(
          id: (map['id'] as num?)?.toInt() ?? 0,
          name: realName.isNotEmpty ? realName : username,
          role: role == 'super_admin' ? '超级管理员' : (role == 'admin' ? '管理员' : role),
          permissions: const [],
          avatarPath: '',
        );
      }).toList();
      _setUsersState(users, null);
    } catch (e) {
      _setUsersState([], '用户列表读取失败：$e');
    }
  }

  void _setUsersState(List<UserRole> users, String? error) {
    if (!mounted) return;
    setState(() {
      _users = users;
      _usersLoading = false;
      _usersError = error;
    });
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

  /// 导出日志 - 弹出保存对话框让用户选择路径（导出当前展示的真实记录）
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

  // ============ RDK X5 地址配置（WS set_rdk_config，需 admin token） ============

  /// 保存 RDK X5 地址：经 WS set_rdk_config 通道（后端要求 admin 角色），
  /// ack.success 即真实结果，成功/失败都有明确反馈。
  Future<void> _saveRdkConfig() async {
    final host = _rdkHostController.text.trim();
    final port = int.tryParse(_rdkPortController.text.trim());
    if (host.isEmpty || port == null || port < 1 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入合法的 RDK X5 IP 和端口'), backgroundColor: AppColors.error),
      );
      return;
    }
    final token = UserSession().authToken;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录会话已失效，请重新登录'), backgroundColor: AppColors.error),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在下发 RDK 配置...'),
          ],
        ),
      ),
    );

    String? error;
    try {
      final ack = await _UiSocketRequest.send(
        RovBackendService().serverAddress,
        token: token,
        message: {'type': 'set_rdk_config', 'host': host, 'port': port, 'token': token},
      );
      if (ack['success'] != true) {
        error = ack['message']?.toString() ?? '后端拒绝（需要管理员角色）';
      }
    } catch (e) {
      error = '后端连接失败：$e';
    }

    if (!mounted) return;
    Navigator.pop(context); // 关闭进度对话框

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('RDK 配置失败：$error'), backgroundColor: AppColors.error),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('RDK 地址已更新为 $host:$port，后端正在重连网关'), backgroundColor: AppColors.success),
    );
    _loadHealth();
  }

  // ============ 链路诊断（真实数据，替代旧假自检） ============

  /// 链路诊断：展示 /api/health + /api/stats 的真实链路数据，
  /// 不再伪造 CPU/内存/延迟等无来源指标。
  Future<void> _runLinkDiagnostics() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在采集链路状态...'),
          ],
        ),
      ),
    );
    await _loadStats();
    if (!mounted) return;
    Navigator.pop(context); // 关闭进度对话框

    final rdk = _health?['rdk'] as Map<String, dynamic>? ?? {};
    final connected = rdk['connected'] == true;
    final caps = (rdk['caps'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    final cameras = (rdk['cameras'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    final lastError = rdk['last_error']?.toString() ?? '';
    final mode = _health?['backend_mode']?.toString() ?? '未知';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.monitor_heart, color: AppColors.primary),
            SizedBox(width: 8),
            Text('链路诊断（真实数据）'),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDiagRow('后端模式', mode == 'rdk' ? 'rdk（真实硬件链路）' : (mode == 'sim' ? 'sim（仿真模式）' : mode)),
              _buildDiagRow('RDK X5 连接', connected
                  ? '已连接 ${rdk['host']}:${rdk['port']}'
                  : '未连接${lastError.isNotEmpty ? '（$lastError）' : ''}'),
              _buildDiagRow('活动摄像头', rdk['active_camera']?.toString().isNotEmpty == true
                  ? rdk['active_camera'].toString()
                  : '无'),
              _buildDiagRow('摄像头列表', cameras.isNotEmpty ? cameras.join('、') : '未知（网关未上报）'),
              _buildDiagRow('网关能力', caps.isNotEmpty ? caps.join('、') : '未知（网关未上报）'),
              const Divider(height: 24),
              _buildDiagRow('用户总数', '${(_stats?['users'] as num?)?.toInt() ?? '--'}'),
              _buildDiagRow('活跃会话', '${(_stats?['sessions_active'] as num?)?.toInt() ?? '--'}'),
              _buildDiagRow('数据库大小', _stats?['db_size_mb'] != null
                  ? '${(_stats!['db_size_mb'] as num).toStringAsFixed(2)} MB'
                  : '--'),
              _buildDiagRow('后端运行时长', _formatUptime((_stats?['uptime_s'] as num?)?.toInt())),
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

  Widget _buildDiagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  // ============ 页面构建 ============

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
            Text('系统实时概览', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            SizedBox(height: 4),
            Text('数据来源：本地后端数据库 /api/stats · 仅统计 rdk 真实链路 · 30 秒自动刷新', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          ],
        ),
        Row(
          children: [
            _buildOutlineButton(icon: Icons.monitor_heart, label: '链路诊断', onTap: _runLinkDiagnostics),
            const SizedBox(width: 12),
            _buildPrimaryButton(icon: Icons.refresh, label: '刷新数据', onTap: _loadAll),
          ],
        ),
      ],
    );
  }

  /// 运行时长人类可读化
  String _formatUptime(int? seconds) {
    if (seconds == null) return '--';
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (d > 0) return '$d 天 $h 小时';
    if (h > 0) return '$h 小时 $m 分';
    return '$m 分钟';
  }

  /// 构建统计卡片网格（2 行 × 3，全部来自 /api/stats）
  Widget _buildStatsGrid() {
    return Column(
      children: [
        // 统计读取失败提示（保留最后成功值，配合 StaleBadge 断链提示）
        if (_statsError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '⚠ 统计读取失败：$_statsError（显示的是最近一次成功数据）',
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ),
          ),
        Row(
          children: [
            // 动效工具箱：统计卡错峰入场（仅首次挂载播放，30s 轮询刷新不重放）
            Expanded(child: StaggerIn(index: 0, child: _buildStatCard(
              icon: Icons.people_outline,
              iconColor: AppColors.primary,
              title: '用户总数',
              value: _intOrDashes('users'),
              unit: '人',
            ))),
            const SizedBox(width: 16),
            Expanded(child: StaggerIn(index: 1, child: _buildStatCard(
              icon: Icons.devices_other,
              iconColor: const Color(0xFF6366F1),
              title: '活跃会话',
              value: _intOrDashes('sessions_active'),
              unit: '个',
            ))),
            const SizedBox(width: 16),
            Expanded(child: StaggerIn(index: 2, child: _buildStatCard(
              icon: Icons.terminal,
              iconColor: const Color(0xFF9370DB),
              title: '24h 控制日志',
              value: _intOrDashes('control_logs_24h'),
              unit: '条',
            ))),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: StaggerIn(index: 3, child: _buildStatCard(
              icon: Icons.sensors,
              iconColor: AppColors.success,
              title: '24h 传感器数据（rdk）',
              value: _intOrDashes('sensor_readings_24h'),
              unit: '条',
            ))),
            const SizedBox(width: 16),
            Expanded(child: StaggerIn(index: 4, child: _buildStatCard(
              icon: Icons.storage,
              iconColor: const Color(0xFFF97316),
              title: '数据库大小',
              value: _stats?['db_size_mb'] != null
                  ? (_stats!['db_size_mb'] as num).toStringAsFixed(2)
                  : '--',
              unit: 'MB',
            ))),
            const SizedBox(width: 16),
            Expanded(child: StaggerIn(index: 5, child: _buildStatCard(
              icon: Icons.timer_outlined,
              iconColor: const Color(0xFF0EA5E9),
              title: '后端运行时长',
              value: _formatUptimeShort((_stats?['uptime_s'] as num?)?.toInt()),
              unit: _stats?['uptime_s'] != null ? '' : '--',
            ))),
          ],
        ),
      ],
    );
  }

  String _intOrDashes(String key) {
    final v = (_stats?[key] as num?)?.toInt();
    return v?.toString() ?? '--';
  }

  /// 运行时长短格式（卡片展示）
  String _formatUptimeShort(int? seconds) {
    if (seconds == null) return '--';
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (d > 0) return '$d天$h时';
    if (h > 0) return '$h时$m分';
    return '$m分';
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
            _buildSystemStatusCard(),
          ],
        )),
      ],
    );
  }

  /// 构建统计卡片（不再展示无来源的假趋势箭头）
  Widget _buildStatCard({required IconData icon, required Color iconColor, required String title, required String value, required String unit}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: iconColor, size: 22)),
              // 断链提示：统计超过 65 秒（>2 个轮询周期）未刷新 → "信号丢失"
              StaleBadge(
                lastUpdated: _statsFetchedAt,
                staleThreshold: const Duration(seconds: 65),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // 旧版统计卡数值排版：30 bold + 14 单位
              Flexible(child: Text(value, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppColors.textPrimary))),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(unit, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 构建系统操作日志表格（后端数据库真实记录）
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
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
                    Text('从后端数据库（/api/logs）实时读取', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
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
                    _buildSmallOutlineButton(icon: Icons.refresh, label: '刷新', onTap: _loadLogs),
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
                // 数据行（无合成数据：空态/错误态明确展示）
                if (_logsLoading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    // 动效工具箱：加载骨架（reduceMotion 时为静态骨架）
                    child: SkeletonLoader(lines: 5, spacing: 16, height: 14),
                  )
                else if (_logsError != null)
                  Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text('⚠ $_logsError', style: const TextStyle(color: AppColors.error)),
                  )
                else if (pageData.isEmpty)
                  const Padding(padding: EdgeInsets.all(40), child: Text('暂无日志数据（后端数据库尚无控制记录）', style: TextStyle(color: AppColors.textHint)))
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

  /// 构建用户与角色卡片（后端数据库真实用户）
  Widget _buildUserRolesCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
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
          const Text('从后端数据库（/api/users）读取，支持增删', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
          const SizedBox(height: 12),
          if (_usersLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              // 动效工具箱：加载骨架（reduceMotion 时为静态骨架）
              child: SkeletonLoader(lines: 3, spacing: 18, height: 14),
            )
          else if (_usersError != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('⚠ $_usersError', style: const TextStyle(color: AppColors.error, fontSize: 12)),
            )
          else if (_users.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Text('暂无用户数据', style: TextStyle(color: AppColors.textHint)))
          else
            ..._users.map((user) => Padding(padding: const EdgeInsets.only(bottom: 20), child: _buildUserItem(user))),
        ],
      ),
    );
  }

  /// 构建用户项
  Widget _buildUserItem(UserRole user) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头像（后端无头像数据，展示首字符占位，非合成数据）
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(user.name.isNotEmpty ? user.name[0] : '?',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
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
                  Expanded(child: Text(user.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
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
        ),
      ],
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

              if (dialogContext.mounted) Navigator.pop(dialogContext);
              await _refreshUsers();

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

  /// 构建系统状态卡片（只读，来自 /api/health，替代旧假配置开关）
  Widget _buildSystemStatusCard() {
    final rdk = _health?['rdk'] as Map<String, dynamic>? ?? {};
    final connected = rdk['connected'] == true;
    final mode = _health?['backend_mode']?.toString();
    final cameras = (rdk['cameras'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    final lastError = rdk['last_error']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Row(children: [
                Icon(Icons.list_alt, color: AppColors.primary, size: 20),
                SizedBox(width: 8),
                Text('系统状态（只读）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
              ])),
              IconButton(
                onPressed: _loadHealth,
                icon: const Icon(Icons.refresh, color: AppColors.textHint, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: '刷新状态',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _healthError != null ? '⚠ 健康状态读取失败：$_healthError' : '来自 GET /api/health（只读展示，不做假开关）',
            style: TextStyle(fontSize: 11, color: _healthError != null ? AppColors.error : AppColors.textHint),
          ),
          const SizedBox(height: 16),
          // 后端模式（sim 时黄色标注，与全局角标呼应）
          Row(
            children: [
              const SizedBox(
                width: 96,
                child: Text('后端模式', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: mode == 'sim' ? AppColors.warning.withValues(alpha: 0.15) : AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  mode == 'sim' ? 'sim（仿真）' : (mode == 'rdk' ? 'rdk（真实链路）' : (mode ?? '未知')),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: mode == 'sim' ? AppColors.warning : AppColors.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // RDK 连接状态
          Row(
            children: [
              const SizedBox(
                width: 96,
                child: Text('RDK 连接', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ),
              Expanded(
                child: Text(
                  connected
                      ? '已连接 ${rdk['host']}:${rdk['port']}'
                      : (lastError.isNotEmpty ? '未连接（$lastError）' : '未连接'),
                  style: TextStyle(fontSize: 13, color: connected ? AppColors.success : AppColors.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 摄像头能力
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: 96,
                child: Text('摄像头能力', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ),
              Expanded(
                child: Text(
                  cameras.isNotEmpty ? cameras.join('、') : '未知（网关未上报）',
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const Divider(height: 28),
          // RDK 地址配置（走 set_rdk_config，需 admin）
          const Text('RDK X5 地址配置', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('修改经 WS set_rdk_config 下发（需管理员），后端持久化并重连网关', style: TextStyle(fontSize: 11, color: AppColors.textHint)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _rdkHostController,
                  decoration: const InputDecoration(
                    labelText: 'RDK X5 IP',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: TextField(
                  controller: _rdkPortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '端口',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveRdkConfig,
              icon: const Icon(Icons.cable, size: 18),
              label: const Text('保存并连接'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
            ),
          ),
        ],
      ),
    );
  }

  // ============ 通用按钮 ============

  Widget _buildOutlineButton({required IconData icon, required String label, required VoidCallback onTap}) {
    // 动效工具箱：按压缩放反馈（点击仍由内部 InkWell 处理）
    return PressableScale(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: const Color(0xFFF8FAFC),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 1))]),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({required IconData icon, required String label, required VoidCallback onTap}) {
    // 动效工具箱：按压缩放反馈（点击仍由内部 InkWell 处理）
    return PressableScale(
      child: Material(
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
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: enabled ? AppColors.border : AppColors.border.withValues(alpha: 0.5))),
          child: Text(label, style: TextStyle(fontSize: 12, color: enabled ? AppColors.textPrimary : AppColors.textHint)),
        ),
      ),
    );
  }
}

/// 页面内 REST 轻封装：补齐 ApiClient 未覆盖的 /api/stats 契约端点。
/// （ApiClient 属 C 轮基建文件，本轮只读不改，故在页面内私有封装。）
class _StatsApi {
  /// GET /api/stats（Bearer，admin 角色）→ stats 对象
  static Future<Map<String, dynamic>> fetch(String token) async {
    final uri = Uri.parse('${ApiClient.baseUrl}/api/stats');
    final response = await http
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      String message = 'HTTP ${response.statusCode}';
      try {
        final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        message = data['error']?.toString() ?? message;
      } catch (_) {}
      throw Exception(message);
    }
    final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw Exception(data['error']?.toString() ?? '请求失败');
    }
    return (data['stats'] as Map<String, dynamic>?) ?? {};
  }
}

/// 辅助 WS 通道：用于需要读取 ack 结果反馈的管理操作（set_rdk_config 等）。
/// 主服务层（RovBackendService）不回传 ack 负载，这里建立短连接触达后端，
/// 操作完成（或超时）立即关闭。
class _UiSocketRequest {
  static const Duration _timeout = Duration(seconds: 6);

  /// 连接 → auth → 发送命令 → 等待首个 ack → 关闭，返回 ack 消息
  static Future<Map<String, dynamic>> send(
    String serverAddress, {
    required String token,
    required Map<String, dynamic> message,
  }) async {
    final completer = Completer<Map<String, dynamic>>();
    WebSocketChannel? channel;
    StreamSubscription<dynamic>? sub;
    try {
      channel = WebSocketChannel.connect(Uri.parse('ws://$serverAddress'));
      await channel.ready.timeout(_timeout);
      sub = channel.stream.listen(
        (data) {
          if (data is String && !completer.isCompleted) {
            try {
              final msg = json.decode(data) as Map<String, dynamic>;
              // 命令 ack 即完成（hello/auth_result/status 等消息忽略）
              if (msg['type'] == 'ack') completer.complete(msg);
            } catch (_) {/* 非 JSON 消息忽略 */}
          }
        },
        onError: (Object e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) completer.completeError(Exception('后端连接已关闭'));
        },
      );
      channel.sink.add(json.encode({'type': 'auth', 'action': 'login', 'token': token}));
      channel.sink.add(json.encode(message));
      return await completer.future.timeout(_timeout);
    } on TimeoutException {
      throw Exception('后端响应超时，请确认 PC 后端已启动');
    } finally {
      try {
        await sub?.cancel();
      } catch (_) {}
      try {
        await channel?.sink.close();
      } catch (_) {}
    }
  }
}
