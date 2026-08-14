/// 数据分析报表 - 桌面端
/// 
/// 功能：环境指标监控、图表展示、AI智能分析
/// 数据源：从 assets/data/environment_data.csv 读取
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/data_service.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/user_session.dart';

/// 数据分析页面桌面端
class DataAnalysisDesktop extends StatefulWidget {
  const DataAnalysisDesktop({super.key});

  @override
  State<DataAnalysisDesktop> createState() => _DataAnalysisDesktopState();
}

class _DataAnalysisDesktopState extends State<DataAnalysisDesktop> {
  // 时间范围选择
  int _selectedTimeRange = 1; // 0:今日, 1:本周, 2:本月, 3:本年
  
  // 数据
  List<EnvironmentData> _allData = [];
  List<EnvironmentData> _filteredData = [];
  bool _isLoading = true;

  // 计算指标
  double _avgPh = 0;
  double _avgTemp = 0;
  double _avgSalinity = 0;
  double _avgPressure = 0;
  double _avgDepth = 0;
  double _avgLux = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// 加载数据
  Future<void> _loadData() async {
    // 优先读取后端数据库中的传感器历史，无会话/无数据时回退演示数据
    final liveData = await _loadLiveSensorHistory();
    final data = liveData.isNotEmpty
        ? liveData
        : await DataService.loadEnvironmentData();
    setState(() {
      _allData = data.isNotEmpty ? data : _getDefaultData();
      _isLoading = false;
      _filterDataByTimeRange();
    });
  }

  /// 从 PC 后端数据库读取 RDK X5 传感器历史，按分钟聚合
  Future<List<EnvironmentData>> _loadLiveSensorHistory() async {
    final token = UserSession().authToken;
    if (token == null || token.isEmpty) return [];
    try {
      final rows = await ApiClient.listSensors(token, limit: 2000);
      final buckets = <int, List<Map<String, dynamic>>>{};
      for (final row in rows) {
        final ts = (row['ts'] as num?)?.toDouble() ?? 0;
        if (ts <= 0) continue;
        final key = (ts / 60).floor();
        buckets.putIfAbsent(key, () => []).add({
          'ts': ts,
          'name': row['name']?.toString() ?? '',
          'value': (row['value'] as num?)?.toDouble() ?? 0,
        });
      }

      final data = <EnvironmentData>[];
      final keys = buckets.keys.toList()..sort();
      for (final key in keys.reversed) {
        final rowsInBucket = buckets[key]!;
        double temperature = 0;
        double pressure = 0;
        double depth = 0;
        double lux = 0;
        int tempCount = 0;
        int pressureCount = 0;
        int depthCount = 0;
        int luxCount = 0;
        for (final row in rowsInBucket) {
          final name = row['name'];
          final value = row['value'] as double;
          if (name == 'ds18b20_water_1.temperature_c' ||
              name == 'ds18b20_water_2.temperature_c') {
            temperature += value;
            tempCount++;
          } else if (name == 'ms5837_depth.pressure_mbar') {
            pressure += value;
            pressureCount++;
          } else if (name == 'ms5837_depth.depth_m') {
            depth += value;
            depthCount++;
          } else if (name == 'veml7700_front_light.lux' ||
              name == 'veml7700_down_light.lux') {
            lux += value;
            luxCount++;
          }
        }
        final ts = rowsInBucket.first['ts'] as double;
        data.add(EnvironmentData(
          dateTime: DateTime.fromMillisecondsSinceEpoch((ts * 1000).round()),
          phValue: 0,
          temperature: tempCount > 0 ? temperature / tempCount : 0,
          salinity: 0,
          // 数据库存 mbar，图表沿用 kPa 量程
          pressure: pressureCount > 0 ? (pressure / pressureCount) / 10.0 : 0,
          depth: depthCount > 0 ? depth / depthCount : 0,
          lux: luxCount > 0 ? lux / luxCount : 0,
        ));
      }
      return data;
    } catch (_) {
      return [];
    }
  }

  /// 获取默认数据
  List<EnvironmentData> _getDefaultData() {
    final now = DateTime.now();
    final data = <EnvironmentData>[];
    for (int i = 0; i < 24; i++) {
      data.add(EnvironmentData(
        dateTime: now.subtract(Duration(hours: i)),
        phValue: 7.8 + (i % 5) * 0.1,
        temperature: 12.0 + (i % 8) * 0.5,
        salinity: 31.5 + (i % 4) * 0.3,
        pressure: 101.5 + (i % 6) * 0.2,
      ));
    }
    return data;
  }

  /// 根据时间范围过滤数据
  void _filterDataByTimeRange() {
    final now = DateTime.now();
    DateTime start;
    
    switch (_selectedTimeRange) {
      case 0: // 今日
        start = DateTime(now.year, now.month, now.day);
        break;
      case 1: // 本周
        start = now.subtract(Duration(days: now.weekday - 1));
        start = DateTime(start.year, start.month, start.day);
        break;
      case 2: // 本月
        start = DateTime(now.year, now.month, 1);
        break;
      case 3: // 本年
        start = DateTime(now.year, 1, 1);
        break;
      default:
        start = DateTime(now.year, now.month, now.day);
    }

    _filteredData = DataService.filterByDateRange(_allData, start, now);
    
    // 如果过滤后没有数据，使用全部数据（可能CSV数据日期较旧）
    if (_filteredData.isEmpty && _allData.isNotEmpty) {
      _filteredData = List.from(_allData);
    }
    
    _calculateMetrics();
  }

  /// 计算指标
  void _calculateMetrics() {
    if (_filteredData.isEmpty) {
      _avgPh = 0;
      _avgTemp = 0;
      _avgSalinity = 0;
      _avgPressure = 0;
      _avgDepth = 0;
      _avgLux = 0;
      return;
    }

    double totalPh = 0, totalTemp = 0, totalSalinity = 0, totalPressure = 0;
    double totalDepth = 0, totalLux = 0;
    for (final data in _filteredData) {
      totalPh += data.phValue;
      totalTemp += data.temperature;
      totalSalinity += data.salinity;
      totalPressure += data.pressure;
      totalDepth += data.depth;
      totalLux += data.lux;
    }

    final count = _filteredData.length;
    _avgPh = totalPh / count;
    _avgTemp = totalTemp / count;
    _avgSalinity = totalSalinity / count;
    _avgPressure = totalPressure / count;
    _avgDepth = totalDepth / count;
    _avgLux = totalLux / count;
  }

  /// 导出CSV - 弹出保存对话框让用户选择路径
  Future<void> _exportCsv() async {
    final csvContent = DataService.exportEnvironmentDataToCsv(_filteredData);
    final timestamp = DateTime.now().toString().replaceAll(':', '-').split('.')[0];
    final fileName = 'environment_data_$timestamp.csv';
    
    try {
      final filePath = await DataService.saveWithFilePicker(csvContent, fileName);
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

  /// 生成完整报告并下载
  Future<void> _generateFullReport() async {
    // 生成报告内容
    String phAnalysis = _avgPh >= 7.8 && _avgPh <= 8.2 ? '水体PH值处于最佳范围(7.8-8.2)，适合海参生长' : '水体PH值偏离最佳范围，建议调整';
    String tempAnalysis = _avgTemp >= 10 && _avgTemp <= 15 ? '水温适中，海参活性良好' : (_avgTemp < 10 ? '水温偏低，海参可能进入休眠状态' : '水温偏高，注意观察海参状态');
    String salinityAnalysis = _avgSalinity >= 30 && _avgSalinity <= 33 ? '盐度适宜，环境稳定' : '盐度偏离正常范围，需要关注';
    
    int score = 0;
    if (_avgPh >= 7.8 && _avgPh <= 8.2) score += 30;
    if (_avgTemp >= 10 && _avgTemp <= 15) score += 30;
    if (_avgSalinity >= 30 && _avgSalinity <= 33) score += 25;
    if (_avgPressure >= 100 && _avgPressure <= 103) score += 15;

    final reportContent = '''
# 海参检测机器人管理系统 - 环境数据分析报告
生成时间: ${DateTime.now().toString().split('.')[0]}
数据范围: ${['今日', '本周', '本月', '本年'][_selectedTimeRange]}
数据条数: ${_filteredData.length}

## 环境指标概览
- 平均PH值: ${_avgPh.toStringAsFixed(2)} ph
- 平均水温: ${_avgTemp.toStringAsFixed(1)} °C
- 平均盐度: ${_avgSalinity.toStringAsFixed(1)} psu
- 平均气压: ${_avgPressure.toStringAsFixed(1)} kPa

## AI智能分析
综合评分: $score 分

### 详细分析
1. PH值分析: $phAnalysis
2. 水温分析: $tempAnalysis
3. 盐度分析: $salinityAnalysis

## 采收建议
${score >= 70 ? '当前环境条件适宜采收作业' : '建议等待环境条件改善后再进行采收'}

---
报告由海参检测机器人管理系统自动生成
''';

    final timestamp = DateTime.now().toString().replaceAll(':', '-').split('.')[0];
    final fileName = 'analysis_report_$timestamp.txt';
    
    try {
      final filePath = await DataService.saveWithFilePicker(reportContent, fileName);
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
          SnackBar(content: Text('生成报告失败: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderSection(),
                  const SizedBox(height: 24),
                  _buildMetricsGrid(),
                  const SizedBox(height: 32),
                  _buildChartsGrid(),
                  const SizedBox(height: 32),
                  _buildAIAnalysisPanel(),
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('数据分析报表', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text('数据源: environment_data.csv · 共 ${_allData.length} 条记录', style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          ],
        ),
        Row(
          children: [
            _buildTimeRangeSelector(),
            const SizedBox(width: 12),
            _buildExportButton(),
          ],
        ),
      ],
    );
  }

  /// 构建时间范围选择器
  Widget _buildTimeRangeSelector() {
    final ranges = ['今日', '本周', '本月', '本年'];
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
          final isSelected = _selectedTimeRange == entry.key;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedTimeRange = entry.key;
                _filterDataByTimeRange();
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFF1F5F9) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                entry.value,
                style: TextStyle(
                  fontSize: 14,
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

  /// 构建导出按钮
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

  /// 构建指标网格
  Widget _buildMetricsGrid() {
    return Row(
      children: [
        Expanded(child: _buildMetricCard(icon: Icons.water_drop, iconColor: AppColors.primary, title: '实时PH值', value: _avgPh.toStringAsFixed(2), unit: 'ph', trend: '+0.05', trendUp: true)),
        const SizedBox(width: 16),
        Expanded(child: _buildMetricCard(icon: Icons.thermostat, iconColor: const Color(0xFFF97316), title: '平均水温', value: _avgTemp.toStringAsFixed(1), unit: '°C', trend: '+1.2', trendUp: true)),
        const SizedBox(width: 16),
        Expanded(child: _buildMetricCard(icon: Icons.science, iconColor: const Color(0xFF22C55E), title: '盐度浓度', value: _avgSalinity.toStringAsFixed(1), unit: 'psu', trend: '-0.3', trendUp: false)),
        const SizedBox(width: 16),
        Expanded(child: _buildMetricCard(icon: Icons.speed, iconColor: const Color(0xFF9370DB), title: '气压水平', value: _avgPressure.toStringAsFixed(1), unit: 'kPa', trend: '+0.1', trendUp: true)),
      ],
    );
  }

  /// 构建指标卡片
  Widget _buildMetricCard({required IconData icon, required Color iconColor, required String title, required String value, required String unit, required String trend, required bool trendUp}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    const SizedBox(width: 4),
                    Text(unit, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: trendUp ? AppColors.success.withOpacity(0.1) : AppColors.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(trendUp ? Icons.trending_up : Icons.trending_down, size: 14, color: trendUp ? AppColors.success : AppColors.error),
                const SizedBox(width: 2),
                Text(trend, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: trendUp ? AppColors.success : AppColors.error)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建图表网格
  Widget _buildChartsGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildChartCard('深度变化趋势 (m)', _buildDepthChart())),
            const SizedBox(width: 24),
            Expanded(child: _buildChartCard('环境光照 (lux)', _buildLuxChart())),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: _buildChartCard('底层水温变化', _buildTemperatureChart())),
            const SizedBox(width: 24),
            Expanded(child: _buildChartCard('环境大气压强', _buildPressureChart())),
          ],
        ),
      ],
    );
  }

  /// 构建图表卡片
  Widget _buildChartCard(String title, Widget chart) {
    return Container(
      height: 280,
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
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
                child: Text('${_filteredData.length} 条数据', style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(child: chart),
        ],
      ),
    );
  }

  /// 深度折线图（来自 MS5837 depth_m）
  Widget _buildDepthChart() {
    if (_filteredData.isEmpty) return const Center(child: Text('暂无数据'));
    
    final spots = <FlSpot>[];
    final dataToShow = _filteredData.take(24).toList().reversed.toList();
    for (int i = 0; i < dataToShow.length; i++) {
      spots.add(FlSpot(i.toDouble(), dataToShow[i].depth));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 0.5, getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFFE5E7EB), strokeWidth: 1)),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(1), style: const TextStyle(fontSize: 10, color: AppColors.textHint)))),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: 0,
        maxY: 2,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppColors.primary,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: AppColors.primary.withOpacity(0.1)),
          ),
        ],
      ),
    );
  }

  /// 光照柱状图（来自 VEML7700 lux）
  Widget _buildLuxChart() {
    if (_filteredData.isEmpty) return const Center(child: Text('暂无数据'));
    
    final barGroups = <BarChartGroupData>[];
    final dataToShow = _filteredData.take(12).toList().reversed.toList();
    for (int i = 0; i < dataToShow.length; i++) {
      barGroups.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(toY: dataToShow[i].lux, color: const Color(0xFF22C55E), width: 16, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
      ]));
    }

    return BarChart(
      BarChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 100, getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFFE5E7EB), strokeWidth: 1)),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(fontSize: 10, color: AppColors.textHint)))),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        barGroups: barGroups,
        minY: 0,
        maxY: 500,
      ),
    );
  }

  /// 水温折线图
  Widget _buildTemperatureChart() {
    if (_filteredData.isEmpty) return const Center(child: Text('暂无数据'));
    
    final spots = <FlSpot>[];
    final dataToShow = _filteredData.take(24).toList().reversed.toList();
    for (int i = 0; i < dataToShow.length; i++) {
      spots.add(FlSpot(i.toDouble(), dataToShow[i].temperature));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 2, getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFFE5E7EB), strokeWidth: 1)),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (value, meta) => Text('${value.toInt()}°', style: const TextStyle(fontSize: 10, color: AppColors.textHint)))),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: 8,
        maxY: 18,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFFF97316),
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: const Color(0xFFF97316).withOpacity(0.1)),
          ),
        ],
      ),
    );
  }

  /// 气压折线图
  Widget _buildPressureChart() {
    if (_filteredData.isEmpty) return const Center(child: Text('暂无数据'));
    
    final spots = <FlSpot>[];
    final dataToShow = _filteredData.take(24).toList().reversed.toList();
    for (int i = 0; i < dataToShow.length; i++) {
      spots.add(FlSpot(i.toDouble(), dataToShow[i].pressure));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 0.5, getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFFE5E7EB), strokeWidth: 1)),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(1), style: const TextStyle(fontSize: 10, color: AppColors.textHint)))),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: 100,
        maxY: 104,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color(0xFF9370DB),
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: const Color(0xFF9370DB).withOpacity(0.1)),
          ),
        ],
      ),
    );
  }

  /// AI分析面板
  Widget _buildAIAnalysisPanel() {
    // 根据数据生成分析
    String depthAnalysis = '当前平均深度 ${_avgDepth.toStringAsFixed(2)} m，${_avgDepth > 0 && _avgDepth <= 20 ? '处于常规作业范围' : '等待有效深度数据'}';
    String tempAnalysis = _avgTemp >= 10 && _avgTemp <= 15 ? '水温适中，海参活性良好' : (_avgTemp < 10 ? '水温偏低，海参可能进入休眠状态' : '水温偏高，注意观察海参状态');
    String luxAnalysis = _avgLux > 5 ? '环境光照正常（均值 ${_avgLux.toStringAsFixed(0)} lux）' : '光照数据不足';
    
    int score = 0;
    if (_avgDepth > 0 && _avgDepth <= 20) score += 30;
    if (_avgTemp >= 10 && _avgTemp <= 15) score += 30;
    if (_avgLux > 5) score += 25;
    if (_avgPressure >= 100 && _avgPressure <= 104) score += 15;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF87CEEB).withOpacity(0.1), const Color(0xFF9370DB).withOpacity(0.1)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.auto_awesome, color: Color(0xFF6366F1), size: 24),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI 智能分析看板', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    SizedBox(height: 2),
                    Text('基于传感器数据的智能综合分析', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: score >= 80 ? AppColors.success : (score >= 60 ? AppColors.warning : AppColors.error),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('综合评分: $score分', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildAnalysisItem('采收适宜度', score >= 70 ? '条件适宜' : '条件一般', score >= 70 ? AppColors.success : AppColors.warning, score >= 70 ? Icons.check_circle : Icons.warning)),
              const SizedBox(width: 16),
              Expanded(child: _buildAnalysisItem('环境预警', _avgTemp > 15 || _avgTemp < 10 ? '水温异常' : '正常', _avgTemp > 15 || _avgTemp < 10 ? AppColors.warning : AppColors.success, _avgTemp > 15 || _avgTemp < 10 ? Icons.warning : Icons.check_circle)),
              const SizedBox(width: 16),
              Expanded(child: _buildAnalysisItem('养殖建议', depthAnalysis.length > 15 ? depthAnalysis.substring(0, 15) + '...' : depthAnalysis, AppColors.primary, Icons.lightbulb)),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('详细分析报告', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                Text('• $depthAnalysis', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.6)),
                Text('• $tempAnalysis', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.6)),
                Text('• $luxAnalysis', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.6)),
                Text('• 当前数据基于 ${_filteredData.length} 条监测记录', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.6)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: const Color(0xFF6366F1),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: _generateFullReport,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.description, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text('生成完整报告', style: TextStyle(fontSize: 14, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 分析项
  Widget _buildAnalysisItem(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
