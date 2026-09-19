// 海参检测机器人管理系统Widget测试

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rov_flutter/app.dart';

void main() {
  Future<void> setScreenSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pump();
  }

  testWidgets('App smoke test - 登录页加载测试', (WidgetTester tester) async {
    await setScreenSize(tester, const Size(1440, 900));
    await tester.pumpWidget(const ROVApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('海参检测机器人管理系统'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });

  testWidgets('Desktop flow - 登录后显示桌面布局', (WidgetTester tester) async {
    await setScreenSize(tester, const Size(1440, 900));
    await tester.pumpWidget(const MaterialApp(home: DashboardRouter()));
    await tester.pump(const Duration(milliseconds: 500));
    // 让页签转场（300ms）与右栏错峰入场（≤200ms 延迟 + 300ms）全部走完
    await tester.pump(const Duration(milliseconds: 500));

    // 页脚状态由 connectionNotifier 真实驱动（铁律②：无后端连接时如实
    // 显示真实连接状态 + 版本号，不再出现写死的"系统运行正常"假文案），
    // 因此断言"真实状态文案 + 版本标记"渲染在页脚，而非旧假文案。
    expect(find.textContaining('(v3.0.0)'), findsOneWidget);
    // 桌面布局默认落在主控页（页签 2）
    expect(find.text('实时监控中心'), findsOneWidget);
  });

  testWidgets('Mobile flow - 登录后显示移动端布局', (WidgetTester tester) async {
    await setScreenSize(tester, const Size(390, 844));
    await tester.pumpWidget(const MaterialApp(home: DashboardRouter()));
    await tester.pump(const Duration(milliseconds: 500));

    // Wave 2 导航收敛：移动端仅保留 主控 + 设置 两个真实页面
    // （管理员/数据分析演示页已隐藏，桌面端仍为完整实现）
    expect(find.text('主控'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('概览'), findsNothing);
    expect(find.text('数据'), findsNothing);

    await tester.tap(find.text('设置'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('辅助功能与性能优化。'), findsOneWidget);
  });
}
