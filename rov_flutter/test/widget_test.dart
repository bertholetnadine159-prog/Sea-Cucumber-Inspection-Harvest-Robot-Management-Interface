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

    expect(find.text('系统运行正常 (v3.0.0)'), findsOneWidget);

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
