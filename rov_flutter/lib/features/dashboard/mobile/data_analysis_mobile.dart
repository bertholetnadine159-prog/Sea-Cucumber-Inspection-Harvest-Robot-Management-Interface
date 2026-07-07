/// 数据分析 - 移动端
/// 
/// 功能：环境指标、图表展示、AI分析看板
/// 设计稿对应：app/data_analysis/screen.png
library;

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_colors.dart';

/// 移动端数据分析页面
class DataAnalysisMobile extends StatelessWidget {
  const DataAnalysisMobile({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : null,
      body: CustomScrollView(
        slivers: [
          // 渐变头部
          SliverToBoxAdapter(child: _buildHeader(context)),
          // 内容区域
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 页面标题
                  Text('数据分析报表', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary)),
                  const SizedBox(height: 16),
                  
                  // 环境指标卡片
                  _buildMetricsCards(),
                  const SizedBox(height: 24),
                  
                  // PH值动态趋势
                  _buildPHChart(),
                  const SizedBox(height: 24),
                  
                  // 盐度浓度分布
                  _buildSalinityChart(),
                  const SizedBox(height: 24),
                  
                  // 底层水温变化
                  _buildTemperatureChart(),
                  const SizedBox(height: 24),
                  
                  // 环境大气压强
                  _buildPressureChart(),
                  const SizedBox(height: 24),
                  
                  // AI智能分析看板
                  _buildAIPanel(),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建渐变头部
  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 16,
      ),
      decoration: const BoxDecoration(
        gradient: AppColors.headerGradient,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '海参检测系统',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          Row(
            children: [
              Icon(Icons.notifications_outlined, color: Colors.white.withOpacity(0.9)),
              const SizedBox(width: 16),
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white.withOpacity(0.2),
                child: const Icon(Icons.person, color: Colors.white, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建环境指标卡片
  Widget _buildMetricsCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildMetricCard(Icons.water_drop, '实时 PH值', '8.12', 'ph', '~0.2%', AppColors.primary)),
            const SizedBox(width: 12),
            Expanded(child: _buildMetricCard(Icons.thermostat, '平均水温', '22.5', '°C', '~1.5%', AppColors.error)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildMetricCard(Icons.opacity, '盐度浓度', '31.2', 'psu', '~0.8%', AppColors.primary)),
            const SizedBox(width: 12),
            Expanded(child: _buildMetricCard(Icons.air, '气压水平', '101.3', 'kPa', '~0.1%', AppColors.success)),
          ],
        ),
      ],
    );
  }

  /// 构建单个指标卡片
  Widget _buildMetricCard(IconData icon, String title, String value, String unit, String change, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 4),
                  Text(title, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(change, style: TextStyle(fontSize: 10, color: color)),
              ),
            ],
          ),
          const SizedBox(height: 12),
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

  /// 构建图表卡片通用
  Widget _buildChartCard({
    required String title,
    required String subtitle,
    required Color indicatorColor,
    required String statusText,
    required Widget chart,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: indicatorColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: indicatorColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(statusText, style: TextStyle(fontSize: 10, color: indicatorColor)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textHint)),
          const SizedBox(height: 16),
          chart,
        ],
      ),
    );
  }

  /// 构建PH值图表
  Widget _buildPHChart() {
    return _buildChartCard(
      title: 'PH 值动态趋势',
      subtitle: '最近 12 小时水域酸碱度波动曲线',
      indicatorColor: AppColors.primary,
      statusText: '实时监控中',
      chart: SizedBox(
        height: 160,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 0.25,
              getDrawingHorizontalLine: (value) => FlLine(color: AppColors.border.withOpacity(0.5), strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 35,
                  interval: 0.25,
                  getTitlesWidget: (value, meta) => Text('${value.toStringAsFixed(2)}', style: const TextStyle(fontSize: 9, color: AppColors.textHint)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 25,
                  interval: 2,
                  getTitlesWidget: (value, meta) {
                    final hours = ['08:00', '10:00', '12:00', '14:00', '16:00', '18:00', '20:00'];
                    if (value.toInt() < hours.length) {
                      return Text(hours[value.toInt()], style: const TextStyle(fontSize: 9, color: AppColors.textHint));
                    }
                    return const SizedBox();
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            minX: 0, maxX: 6, minY: 7.75, maxY: 8.5,
            lineBarsData: [
              LineChartBarData(
                spots: const [FlSpot(0, 7.9), FlSpot(1, 8.0), FlSpot(2, 8.1), FlSpot(3, 8.15), FlSpot(4, 8.2), FlSpot(5, 8.25), FlSpot(6, 8.35)],
                isCurved: true,
                color: AppColors.primary,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: true, color: AppColors.primary.withOpacity(0.1)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建盐度浓度图表
  Widget _buildSalinityChart() {
    return _buildChartCard(
      title: '盐度浓度分布',
      subtitle: '分时段平均盐度水平统计 (psu)',
      indicatorColor: const Color(0xFFF87171),
      statusText: '数据已同步',
      chart: SizedBox(
        height: 160,
        child: BarChart(
          BarChartData(
            gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 2),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 35,
                  interval: 2.5,
                  getTitlesWidget: (value, meta) => Text('${value.toInt()}', style: const TextStyle(fontSize: 9, color: AppColors.textHint)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 25,
                  getTitlesWidget: (value, meta) {
                    final hours = ['08:00', '10:00', '12:00', '14:00', '16:00', '18:00', '20:00'];
                    if (value.toInt() < hours.length) {
                      return Text(hours[value.toInt()], style: const TextStyle(fontSize: 9, color: AppColors.textHint));
                    }
                    return const SizedBox();
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            minY: 25, maxY: 35,
            barGroups: [0, 1, 2, 3, 4, 5, 6].map((i) => BarChartGroupData(
              x: i,
              barRods: [BarChartRodData(toY: 29 + (i == 3 ? 4 : i == 4 ? 3 : i * 0.5), color: const Color(0xFFF87171).withOpacity(0.7), width: 20, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))],
            )).toList(),
          ),
        ),
      ),
    );
  }

  /// 构建水温图表
  Widget _buildTemperatureChart() {
    return _buildChartCard(
      title: '底层水温变化',
      subtitle: '垂直分布传感器获取的底层水温 (°C)',
      indicatorColor: const Color(0xFFA855F7),
      statusText: '传感器正常',
      chart: SizedBox(
        height: 120,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(show: true, drawVerticalLine: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 20,
                  interval: 2,
                  getTitlesWidget: (value, meta) {
                    final hours = ['08:00', '12:00', '16:00', '20:00'];
                    if (value.toInt() ~/ 2 < hours.length && value.toInt() % 2 == 0) {
                      return Text(hours[value.toInt() ~/ 2], style: const TextStyle(fontSize: 9, color: AppColors.textHint));
                    }
                    return const SizedBox();
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            minX: 0, maxX: 6, minY: 15, maxY: 25,
            lineBarsData: [
              LineChartBarData(
                spots: const [FlSpot(0, 19), FlSpot(2, 20), FlSpot(4, 22), FlSpot(6, 19)],
                isCurved: false,
                color: const Color(0xFFA855F7),
                barWidth: 3,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: true, color: const Color(0xFFA855F7).withOpacity(0.1)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建气压图表
  Widget _buildPressureChart() {
    return _buildChartCard(
      title: '环境大气压强',
      subtitle: '监测点周围气压波动 (kPa)',
      indicatorColor: AppColors.success,
      statusText: '采样频率 5s',
      chart: SizedBox(
        height: 100,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(show: true, drawVerticalLine: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 20,
                  interval: 2,
                  getTitlesWidget: (value, meta) {
                    final hours = ['08:00', '12:00', '16:00', '20:00'];
                    if (value.toInt() ~/ 2 < hours.length && value.toInt() % 2 == 0) {
                      return Text(hours[value.toInt() ~/ 2], style: const TextStyle(fontSize: 9, color: AppColors.textHint));
                    }
                    return const SizedBox();
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            minX: 0, maxX: 6, minY: 100.5, maxY: 102,
            lineBarsData: [
              LineChartBarData(
                spots: const [FlSpot(0, 101), FlSpot(2, 101.3), FlSpot(4, 101.5), FlSpot(6, 101.2)],
                isCurved: true,
                color: AppColors.success,
                barWidth: 3,
                dotData: const FlDotData(show: false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建AI分析看板
  Widget _buildAIPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.psychology, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI 智能分析看板', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('基于多维传感器实时生成的环境评估报告', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // 分析内容
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
            ),
            child: const Text(
              '"当前水域环境整体表现 稳定。PH 值保持在 8.1 左右，由于光照加强，水温略微上升 1.2°C，但仍在海参最适宜生长的 18-24°C 范围内。预计未来 12 小时内，水质溶解氧水平将随潮汐变化小幅波动，无需人工干预。"',
              style: TextStyle(color: Colors.white70, height: 1.6, fontSize: 13),
            ),
          ),
          const SizedBox(height: 20),
          // 提示卡片
          _buildInsightItem(Icons.check_circle, AppColors.success, '采收适宜度', '底层处于最佳采收窗口期，水质澄清度高。'),
          const SizedBox(height: 12),
          _buildInsightItem(Icons.warning, AppColors.warning, '环境预警', '底层溶解氧监测点 A03 接近警戒线 (4.2mg/L)。'),
          const SizedBox(height: 12),
          _buildInsightItem(Icons.lightbulb, AppColors.primary, '养殖建议', '建议在下午 16 时适当开启底部增氧循环设备。'),
          const SizedBox(height: 20),
          // 按钮组
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text('生成完整报告', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text('历史趋势对比', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建洞察提示项
  Widget _buildInsightItem(IconData icon, Color color, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(description, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}
