/// 数据分析报表 - 桌面端
///
/// 功能：传感器时间范围聚合曲线（/api/sensors）、统计摘要、CSV 导出、
///       RDK 快照画廊（WS list_snapshots / fetch_snapshot）。
/// 数据溯源（契约§2/§7）：曲线与统计全部来自 GET /api/sensors
/// （source 默认 rdk 真实链路，bucket 窗口 AVG 聚合，stats 提供 min/max/avg）。
/// Wave 2 变更：删除合成假曲线 _getDefaultData 与"AI 分析"面板；
/// 新增 1h/6h/24h/7d/自定义时间范围、传感器多选、手动+自动（30s）刷新、
/// 快照画廊；断链/无数据时显示空态文案，绝不回退假曲线。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/user_session.dart';
import '../../../core/services/rov_backend_service.dart';
import '../../../core/services/data_service.dart';
import '../../shared/widgets/stale_badge.dart';

/// 传感器目录（契约清单：深度/水温1/2/光照前下/超声前下/压力）
class _SensorDef {
  final String name;   // 后端传感器名（source=rdk 记录的 name 字段）
  final String label;  // 中文标签
  final String unit;   // 单位
  final Color color;   // 曲线颜色
  const _SensorDef(this.name, this.label, this.unit, this.color);
}

/// 单条传感器序列（来自 /api/sensors 的 series 项）
class _SeriesData {
  final String name;
  final String label;
  final String unit;
  final Color color;
  final List<MapEntry<double, double>> points; // (ts epoch秒, value)
  const _SeriesData({
    required this.name,
    required this.label,
    required this.unit,
    required this.color,
    required this.points,
  });
}

/// 数据分析页面桌面端
class DataAnalysisDesktop extends StatefulWidget {
  const DataAnalysisDesktop({super.key});

  @override
  State<DataAnalysisDesktop> createState() => _DataAnalysisDesktopState();
}

class _DataAnalysisDesktopState extends State<DataAnalysisDesktop> {
  /// 自动刷新周期（30 秒）
  static const Duration _autoRefreshInterval = Duration(seconds: 30);

  /// 契约传感器清单（rdk 网关真实上报的传感器名）
  static const List<_SensorDef> _catalog = [
    _SensorDef('ms5837_depth.depth_m', '深度', 'm', AppColors.primary),
    _SensorDef('ds18b20_water_1.temperature_c', '水温1', '°C', Color(0xFFF97316)),
    _SensorDef('ds18b20_water_2.temperature_c', '水温2', '°C', Color(0xFFFB923C)),
    _SensorDef('veml7700_front_light.lux', '光照（前视）', 'lux', Color(0xFF22C55E)),
    _SensorDef('veml7700_down_light.lux', '光照（下视）', 'lux', Color(0xFF16A34A)),
    _SensorDef('ultrasonic_front_suction_mouth.distance_m', '超声（前视）', 'm', Color(0xFF0EA5E9)),
    _SensorDef('ultrasonic_downward_altitude.distance_m', '超声（下视）', 'm', Color(0xFF6366F1)),
    _SensorDef('ms5837_depth.pressure_mbar', '压力', 'mbar', Color(0xFF9370DB)),
  ];

  // 时间范围：0=1h, 1=6h, 2=24h, 3=7d, 4=自定义
  int _selectedRange = 2;
  DateTime? _customFrom;
  DateTime? _customTo;

  // 已选传感器（默认：深度 + 水温1）
  final Set<String> _selectedSensors = {
    'ms5837_depth.depth_m',
    'ds18b20_water_1.temperature_c',
  };

  // 图表类型：0=折线，1=柱状
  int _chartType = 0;

  // 序列数据（真实 rdk 来源）
  List<_SeriesData> _series = const [];
  Map<String, Map<String, dynamic>> _seriesStats = {};
  bool _isLoading = false;
  String? _error;
  DateTime? _lastSuccessAt;
  (DateTime, DateTime)? _lastRange;
  bool _autoRefresh = false;
  Timer? _autoTimer;

  // 快照画廊（WS list_snapshots / fetch_snapshot）
  List<Map<String, dynamic>> _snapshots = const [];
  bool _snapsLoading = false;
  String? _snapsNote; // 空态附注（如后端桥接未转发快照数据）

  @override
  void initState() {
    super.initState();
    _loadSeries();
    _loadSnapshots();
    _autoTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (_autoRefresh && mounted && !_isLoading) {
        _loadSeries();
      }
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  // ============ 数据获取 ============

  /// 解析当前时间范围（from/to）
  (DateTime, DateTime) _resolveRange() {
    final now = DateTime.now();
    switch (_selectedRange) {
      case 0:
        return (now.subtract(const Duration(hours: 1)), now);
      case 1:
        return (now.subtract(const Duration(hours: 6)), now);
      case 3:
        return (now.subtract(const Duration(days: 7)), now);
      case 4:
        final from = _customFrom ?? now.subtract(const Duration(hours: 24));
        var to = _customTo ?? now;
        // 自定义选择的是日期，结束取当天末尾
        to = DateTime(to.year, to.month, to.day, 23, 59, 59);
        if (to.isAfter(now)) to = now;
        return (from, to);
      case 2:
      default:
        return (now.subtract(const Duration(hours: 24)), now);
    }
  }

  /// bucket 聚合窗口：按范围自动取 ~240 个点，限制在 10s~1h
  int _resolveBucket(DateTime from, DateTime to) {
    final span = to.difference(from).inSeconds;
    final raw = span ~/ 240;
    if (raw < 10) return 10;
    if (raw > 3600) return 3600;
    return raw;
  }

  /// 拉取传感器聚合序列（GET /api/sensors，source=rdk）
  Future<void> _loadSeries() async {
    if (_selectedSensors.isEmpty) {
      setState(() {
        _series = const [];
        _seriesStats = {};
        _error = null;
        _lastRange = null;
      });
      return;
    }
    final token = UserSession().authToken;
    if (token == null || token.isEmpty) {
      setState(() => _error = '未登录，无法读取传感器数据');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final (from, to) = _resolveRange();
    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/api/sensors').replace(queryParameters: {
        'from': '${from.millisecondsSinceEpoch ~/ 1000}',
        'to': '${to.millisecondsSinceEpoch ~/ 1000}',
        'bucket': '${_resolveBucket(from, to)}',
        'names': _selectedSensors.join(','),
        'limit': '5000',
      });
      final response = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        String message = 'HTTP ${response.statusCode}';
        try {
          final body = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          message = body['error']?.toString() ?? message;
        } catch (_) {}
        throw Exception(message);
      }
      final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error']?.toString() ?? '请求失败');
      }

      // 解析 series（契约：[{name,unit,points:[{ts,value}]}]）
      final List<_SeriesData> series = [];
      for (final raw in (data['series'] as List? ?? [])) {
        final item = raw as Map<String, dynamic>;
        final name = item['name']?.toString() ?? '';
        final def = _catalog.firstWhere(
          (d) => d.name == name,
          orElse: () => _SensorDef(name, name, item['unit']?.toString() ?? '', AppColors.textSecondary),
        );
        final points = <MapEntry<double, double>>[];
        for (final rawPoint in (item['points'] as List? ?? [])) {
          final p = rawPoint as Map<String, dynamic>;
          final ts = (p['ts'] as num?)?.toDouble() ?? 0;
          final value = (p['value'] as num?)?.toDouble();
          if (ts > 0 && value != null) {
            points.add(MapEntry(ts, value));
          }
        }
        points.sort((a, b) => a.key.compareTo(b.key));
        series.add(_SeriesData(
          name: name,
          label: def.label,
          unit: def.unit,
          color: def.color,
          points: points,
        ));
      }

      final stats = <String, Map<String, dynamic>>{};
      for (final entry in ((data['stats'] as Map<String, dynamic>?) ?? {}).entries) {
        if (entry.value is Map<String, dynamic>) {
          stats[entry.key] = entry.value as Map<String, dynamic>;
        }
      }

      if (!mounted) return;
      setState(() {
        _series = series;
        _seriesStats = stats;
        _lastRange = (from, to);
        _lastSuccessAt = DateTime.now();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '$e';
      });
    }
  }

  // ============ 快照画廊（WS list_snapshots / fetch_snapshot） ============

  /// 拉取快照列表（契约§5：WS 命令 list_snapshots → ack{success,snapshots}）
  Future<void> _loadSnapshots() async {
    final token = UserSession().authToken;
    if (token == null || token.isEmpty) return;
    setState(() {
      _snapsLoading = true;
      _snapsNote = null;
    });
    try {
      final ack = await _UiSocketRequest.send(
        RovBackendService().serverAddress,
        token: token,
        message: {
          'type': 'command',
          'command': 'list_snapshots',
          'params': {},
          'token': token,
        },
      );
      if (!mounted) return;
      final rawList = ack['snapshots'] as List?;
      if (rawList == null) {
        // 网关 ack 负载未到达（后端桥接未转发快照数据，契约§5 转发链路待接通）
        setState(() {
          _snapshots = const [];
          _snapsNote = ack['success'] == true
              ? '后端已受理但未回传快照列表（桥接转发未就绪）'
              : (ack['message']?.toString() ?? '快照命令被拒绝');
          _snapsLoading = false;
        });
        return;
      }
      setState(() {
        _snapshots = rawList.whereType<Map<String, dynamic>>().toList();
        _snapsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _snapshots = const [];
        _snapsNote = '快照通道连接失败：$e';
        _snapsLoading = false;
      });
    }
  }

  /// 取单张快照（fetch_snapshot → ack{success,jpeg(base64)}）
  Future<Uint8List?> _fetchSnapshotJpeg(String name) async {
    final token = UserSession().authToken;
    if (token == null || token.isEmpty) return null;
    final ack = await _UiSocketRequest.send(
      RovBackendService().serverAddress,
      token: token,
      message: {
        'type': 'command',
        'command': 'fetch_snapshot',
        'params': {'name': name},
        'token': token,
      },
    );
    final jpeg = ack['jpeg']?.toString();
    if (ack['success'] != true || jpeg == null || jpeg.isEmpty) return null;
    return base64Decode(jpeg);
  }

  // ============ CSV 导出（真实 series 数据） ============

  Future<void> _exportCsv() async {
    if (_series.isEmpty || _series.every((s) => s.points.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可导出的真实数据'), backgroundColor: AppColors.error),
      );
      return;
    }
    final buffer = StringBuffer();
    // 表头：时间 + 每条序列一列「标签(单位)」
    buffer.writeln('时间,${_series.map((s) => '${s.label}(${s.unit})').join(',')}');
    // 时间轴取所有序列时间戳的并集（升序）
    final tsSet = <double>{};
    for (final s in _series) {
      for (final p in s.points) {
        tsSet.add(p.key);
      }
    }
    final axis = tsSet.toList()..sort();
    for (final ts in axis) {
      final dt = DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());
      final cells = <String>[dt.toIso8601String()];
      for (final s in _series) {
        final match = s.points.where((p) => p.key == ts).toList();
        cells.add(match.isNotEmpty ? match.first.value.toString() : '');
      }
      buffer.writeln(cells.join(','));
    }

    final timestamp = DateTime.now().toString().replaceAll(':', '-').split('.')[0];
    final fileName = 'sensor_series_$timestamp.csv';
    try {
      final filePath = await DataService.saveWithFilePicker(buffer.toString(), fileName);
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
            const Text('文件已保存到：'),
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

  // ============ 工具 ============

  bool get _hasRealData => _series.any((s) => s.points.isNotEmpty);

  String _two(int v) => v.toString().padLeft(2, '0');

  String _fmtTs(double ts, {bool withDate = false}) {
    final dt = DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());
    final hm = '${_two(dt.hour)}:${_two(dt.minute)}';
    return withDate ? '${_two(dt.month)}-${_two(dt.day)} $hm' : hm;
  }

  // ============ 页面构建 ============

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderSection(),
            const SizedBox(height: 20),
            _buildSensorChips(),
            const SizedBox(height: 20),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _buildErrorPanel()
            else if (!_hasRealData)
              _buildEmptyPanel()
            else ...[
              _buildStatsSummary(),
              const SizedBox(height: 24),
              _buildChartCard(),
              const SizedBox(height: 32),
            ],
            _buildSnapshotGallery(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  /// 构建顶部标题与控制区
  Widget _buildHeaderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('数据分析报表', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                SizedBox(height: 4),
                Text('数据来源：后端 /api/sensors（source=rdk 真实链路，bucket 聚合）', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              ],
            ),
            Row(
              children: [
                _buildTimeRangeSelector(),
                const SizedBox(width: 12),
                // 手动刷新
                _buildIconButton(Icons.refresh, '刷新', _loadSeries),
                const SizedBox(width: 8),
                // 自动刷新开关（30s）
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('自动刷新', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    SizedBox(
                      width: 40,
                      child: Switch(
                        value: _autoRefresh,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => _autoRefresh = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                _buildExportButton(),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 自定义范围选择（仅自定义模式显示）
        if (_selectedRange == 4)
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickCustomDate(isFrom: true),
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(_customFrom != null
                    ? '起始：${_customFrom!.year}-${_two(_customFrom!.month)}-${_two(_customFrom!.day)}'
                    : '选择起始日期'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _pickCustomDate(isFrom: false),
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(_customTo != null
                    ? '结束：${_customTo!.year}-${_two(_customTo!.month)}-${_two(_customTo!.day)}'
                    : '选择结束日期'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _loadSeries,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('应用范围'),
              ),
            ],
          ),
      ],
    );
  }

  /// 自定义起止日期选择
  Future<void> _pickCustomDate({required bool isFrom}) async {
    final initial = isFrom
        ? (_customFrom ?? DateTime.now().subtract(const Duration(days: 1)))
        : (_customTo ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _customFrom = picked;
      } else {
        _customTo = picked;
      }
    });
  }

  /// 时间范围选择器（1h/6h/24h/7d/自定义）
  Widget _buildTimeRangeSelector() {
    const ranges = ['1小时', '6小时', '24小时', '7天', '自定义'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Row(
        children: ranges.asMap().entries.map((entry) {
          final isSelected = _selectedRange == entry.key;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedRange = entry.key);
              _loadSeries();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFF1F5F9) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                entry.value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                  color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 传感器多选 chips（契约传感器清单）
  Widget _buildSensorChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final def in _catalog)
          FilterChip(
            label: Text('${def.label} (${def.unit})'),
            selected: _selectedSensors.contains(def.name),
            selectedColor: def.color.withOpacity(0.2),
            checkmarkColor: def.color,
            labelStyle: TextStyle(
              fontSize: 13,
              color: _selectedSensors.contains(def.name) ? def.color : AppColors.textSecondary,
            ),
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  _selectedSensors.add(def.name);
                } else {
                  _selectedSensors.remove(def.name);
                }
              });
              _loadSeries();
            },
          ),
        // 图表类型切换（柱状图按需：仅单传感器时可用）
        const SizedBox(width: 8),
        ToggleButtons(
          isSelected: [_chartType == 0, _chartType == 1],
          onPressed: (i) => setState(() => _chartType = i),
          borderRadius: BorderRadius.circular(8),
          constraints: const BoxConstraints(minHeight: 34),
          children: const [
            Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.show_chart, size: 18)),
            Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.bar_chart, size: 18)),
          ],
        ),
      ],
    );
  }

  Widget _buildIconButton(IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
            child: Icon(icon, size: 20, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }

  Widget _buildExportButton() {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: _exportCsv,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: const Row(
            children: [
              Icon(Icons.download, size: 18, color: Colors.white),
              SizedBox(width: 8),
              Text('导出 CSV', style: TextStyle(fontSize: 14, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  /// 断链/错误面板（绝不回退假曲线）
  Widget _buildErrorPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off, size: 40, color: AppColors.error),
          const SizedBox(height: 12),
          const Text('数据链路中断', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.error)),
          const SizedBox(height: 8),
          Text('无法获取真实数据：$_error', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _loadSeries,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 无数据空态（契约：不得回退假曲线）
  Widget _buildEmptyPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, size: 40, color: AppColors.textHint),
          const SizedBox(height: 12),
          const Text('暂无真实数据（rdk 来源）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text(
            _selectedSensors.isEmpty
                ? '请至少选择一个传感器'
                : '所选传感器在当前时间范围内尚无 rdk 真实链路数据（sim 仿真数据不计入）',
            style: const TextStyle(fontSize: 13, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  /// 统计摘要卡（min/max/avg 来自 /api/sensors 的 stats）
  Widget _buildStatsSummary() {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        for (final s in _series)
          if (s.points.isNotEmpty)
            _buildStatSummaryCard(s),
      ],
    );
  }

  Widget _buildStatSummaryCard(_SeriesData s) {
    final stats = _seriesStats[s.name];
    double? minV = (stats?['min'] as num?)?.toDouble();
    double? maxV = (stats?['max'] as num?)?.toDouble();
    double? avgV = (stats?['avg'] as num?)?.toDouble();
    // 后端未带 stats 时从真实点计算（仍为真实数据）
    if (minV == null || maxV == null || avgV == null) {
      if (s.points.isEmpty) return const SizedBox.shrink();
      final values = s.points.map((p) => p.value).toList();
      minV ??= values.reduce((a, b) => a < b ? a : b);
      maxV ??= values.reduce((a, b) => a > b ? a : b);
      avgV ??= values.reduce((a, b) => a + b) / values.length;
    }
    String fmt(double v) => v.abs() >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    return Container(
      padding: const EdgeInsets.all(16),
      width: 260,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text('${s.label} (${s.unit})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatCell('最小', fmt(minV)),
              _buildStatCell('最大', fmt(maxV)),
              _buildStatCell('平均', fmt(avgV)),
              _buildStatCell('点数', '${s.points.length}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCell(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      ],
    );
  }

  /// 聚合曲线图卡片
  Widget _buildChartCard() {
    final showDate = _lastRange != null &&
        _lastRange!.$2.difference(_lastRange!.$1).inHours > 48;
    final activeSeries = _series.where((s) => s.points.isNotEmpty).toList();

    return Container(
      height: 360,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    _chartType == 0 ? '传感器聚合曲线' : '传感器聚合柱状图',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(width: 12),
                  // 断链提示：成功获取超过 65 秒（>2 个自动刷新周期）未更新
                  StaleBadge(
                    lastUpdated: _lastSuccessAt,
                    staleThreshold: const Duration(seconds: 65),
                  ),
                ],
              ),
              Text(
                '${activeSeries.length} 条序列 · bucket 聚合',
                style: const TextStyle(fontSize: 11, color: AppColors.textHint),
              ),
            ],
          ),
          if (_chartType == 1 && activeSeries.length > 1)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '柱状图按需仅支持单传感器对比，当前多选时请使用折线图',
                style: TextStyle(fontSize: 12, color: AppColors.warning),
              ),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: _chartType == 0 || activeSeries.length > 1
                ? _buildLineChart(activeSeries, showDate)
                : _buildBarChart(activeSeries.first, showDate),
          ),
          // 图例
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            children: [
              for (final s in activeSeries)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 14, height: 3, color: s.color),
                    const SizedBox(width: 6),
                    Text('${s.label} (${s.unit})', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 折线图（多序列叠加，x=真实时间戳）
  Widget _buildLineChart(List<_SeriesData> series, bool showDate) {
    // x 轴范围：优先后端请求范围，异常时从真实数据点推导
    double minX;
    double maxX;
    if (_lastRange != null) {
      minX = _lastRange!.$1.millisecondsSinceEpoch / 1000.0;
      maxX = _lastRange!.$2.millisecondsSinceEpoch / 1000.0;
    } else {
      final allTs = <double>[
        for (final s in series)
          for (final p in s.points) p.key,
      ]..sort();
      minX = allTs.isNotEmpty ? allTs.first : 0;
      maxX = allTs.isNotEmpty ? allTs.last : 1;
    }
    final span = maxX - minX;
    final xInterval = (span / 6).clamp(1.0, double.infinity).toDouble();

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFFE5E7EB), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              getTitlesWidget: (value, meta) => Text(
                value.abs() >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1),
                style: const TextStyle(fontSize: 10, color: AppColors.textHint),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: xInterval,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_fmtTs(value, withDate: showDate), style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
              ),
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: true),
        lineBarsData: [
          for (final s in series)
            LineChartBarData(
              spots: [for (final p in s.points) FlSpot(p.key, p.value)],
              isCurved: false,
              color: s.color,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
        ],
      ),
    );
  }

  /// 柱状图（单传感器，按 bucket 聚合展示）
  Widget _buildBarChart(_SeriesData s, bool showDate) {
    final points = s.points;
    final span = points.last.key - points.first.key;
    final xInterval = (span / 6).clamp(1.0, double.infinity).toDouble();
    // y 轴从 0 起，顶部留 10% 余量
    final maxY = points.map((p) => p.value).reduce((a, b) => a > b ? a : b) * 1.1;

    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFFE5E7EB), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              getTitlesWidget: (value, meta) => Text(
                value.abs() >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1),
                style: const TextStyle(fontSize: 10, color: AppColors.textHint),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: xInterval,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_fmtTs(value, withDate: showDate), style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
              ),
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: true),
        barGroups: [
          for (final p in points)
            BarChartGroupData(
              x: p.key.round(),
              barRods: [
                BarChartRodData(
                  toY: p.value,
                  color: s.color,
                  width: 8,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 快照画廊（WS list_snapshots 列表 + fetch_snapshot 取图网格）
  Widget _buildSnapshotGallery() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('作业快照画廊', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                SizedBox(height: 2),
                Text('来源：RDK 网关快照目录（WS list_snapshots / fetch_snapshot）', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
              ],
            ),
            _buildIconButton(Icons.refresh, '刷新快照', _loadSnapshots),
          ],
        ),
        const SizedBox(height: 12),
        if (_snapsLoading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_snapshots.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Icon(Icons.camera_alt_outlined, size: 36, color: AppColors.textHint),
                const SizedBox(height: 8),
                const Text('暂无快照', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                if (_snapsNote != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '($_snapsNote)',
                    style: const TextStyle(fontSize: 12, color: AppColors.textHint),
                  ),
                ],
              ],
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 240,
              mainAxisExtent: 200,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _snapshots.length,
            itemBuilder: (context, index) {
              final snap = _snapshots[index];
              final name = snap['name']?.toString() ?? '';
              final ts = (snap['ts'] as num?)?.toDouble();
              return _buildSnapshotTile(name, ts);
            },
          ),
      ],
    );
  }

  /// 快照缩略图块（懒加载 fetch_snapshot 取真实 JPEG）
  Widget _buildSnapshotTile(String name, double? ts) {
    final timeText = ts != null
        ? DateTime.fromMillisecondsSinceEpoch((ts * 1000).round()).toString().split('.')[0]
        : '';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () async {
          final bytes = await _fetchSnapshotJpeg(name);
          if (!mounted) return;
          if (bytes == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('快照「$name」取图失败（网关未回传数据）'), backgroundColor: AppColors.error),
            );
            return;
          }
          _showSnapshotZoom(name, timeText, bytes);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: FutureBuilder<Uint8List?>(
                  future: _fetchSnapshotJpeg(name),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                    }
                    final bytes = snap.data;
                    if (bytes == null) {
                      return const Center(
                        child: Icon(Icons.broken_image_outlined, size: 32, color: AppColors.textHint),
                      );
                    }
                    return ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textPrimary)),
                    if (timeText.isNotEmpty)
                      Text(timeText, style: const TextStyle(fontSize: 10, color: AppColors.textHint)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 快照放大查看
  void _showSnapshotZoom(String name, String timeText, Uint8List bytes) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text('$name  $timeText', style: const TextStyle(color: Colors.white, fontSize: 13))),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                maxScale: 5,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// 辅助 WS 通道：快照命令需要读取 ack 负载（snapshots/jpeg），
/// 主服务层不回传 ack 负载，这里建立短连接触达后端，用完即关。
class _UiSocketRequest {
  static const Duration _timeout = Duration(seconds: 8);

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
