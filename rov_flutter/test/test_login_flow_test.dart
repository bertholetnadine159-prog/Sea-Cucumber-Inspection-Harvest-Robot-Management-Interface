// Wave 3 测试补全：登录页流程测试（契约 docs/UPGRADE_CONTRACTS.md §4）
//
// 覆盖：
// 1. 错误凭据 → 显示错误 SnackBar（后端文案透传），且不进入主界面
// 2. 用户名/密码为空 → 直接拦截提示，且不发起任何网络请求
// 3. must_change_password=true → 弹出强制改密对话框；改密成功前不进主界面；
//    对话框校验（两次新密码不一致）拦截且不发请求；改密成功后自动重建会话进入主界面
//
// 实现方式：ApiClient 的 baseUrl 硬编码为 http://127.0.0.1:5000（只读
// core/services/api_client.dart 已确认，测试无法覆盖注入），因此本文件在
// 本机回环 5000 端口起一个有状态的 mock 后端（dart:io HttpServer），
// 按请求路径+请求体实时路由应答（登录路径会连发两次 POST /api/login，
// 不能按预设队列回包），登录页的真实 HTTP 经 tester.runAsync 提供的
// 真实事件循环完成回环。
//
// 两个 flutter_test 陷阱（本文件曾经翻车的根因，改动前务必理解）：
// 1. 覆盖 flutter_test 全局 _MockHttpOverrides 时，createHttpClient 里
//    绝不能写 `HttpClient()`——那会再次解析 HttpOverrides.current（即本
//    override 自身）造成无限递归 StackOverflowError，请求根本发不出去。
//    正确写法是 `super.createHttpClient(context)`。
// 2. 在 testWidgets 的 fake-async zone 里发起的真实 socket 请求永远不会
//    完成（socket 事件不进 fake 时钟）。凡是触发 HTTP 的交互（点击登录、
//    点击确认修改）必须包在 tester.runAsync 里执行，等待回包也用
//    runAsync 轮询 mock 后端状态。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rov_flutter/features/auth/login_screen.dart';

/// 覆盖 flutter_test 默认的 _MockHttpOverrides（它会把一切 HttpClient 请求
/// 拦截为 400 空响应，导致真实的回环 HTTP 永远到不了 mock 后端）。
/// 本文件需要登录页发起真实 loopback 请求，因此恢复真实 HttpClient；
/// 仅本测试文件的 VM 生效，不触及其它测试文件。
///
/// 注意：必须 `super.createHttpClient(context)`。若在此处写 `HttpClient()`
/// 会再次解析 HttpOverrides.current（正是本 override），无限递归直到
/// StackOverflowError，请求根本不会离开进程（见文件顶部"陷阱 1"）。
class _RealLoopbackHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    // super.createHttpClient 返回的是"绕开 _MockHttpOverrides 的真实 HttpClient"；
    // 千万不能在此处直接 `HttpClient()`——那会再次解析 HttpOverrides.current
    //（正是本 override），无限递归直到 StackOverflowError（见文件顶部"陷阱 1"）。
    final client = super.createHttpClient(context);
    // 回环 mock 应当立刻可连：显式收紧连接超时，环境异常时尽早失败
    client.connectionTimeout = const Duration(seconds: 5);
    return client;
  }
}

/// mock 后端约定的账号与口令
const String _username = 'zmm';
const String _initialPwd = 'Zmm771023';
const String _newPwd = 'NewSecure456';
const int _adminId = 1;

/// 主界面占位路由文案（登录成功后 pushReplacementNamed('/dashboard')）
const String _dashboardText = '主界面-仪表盘';

/// 一次被记录的 mock 后端请求
class _RecordedRequest {
  const _RecordedRequest(this.method, this.path, this.body, this.authorization);

  final String method;
  final String path;
  final Map<String, dynamic> body;
  final String? authorization;
}

/// 有状态 mock 后端：只在 127.0.0.1:5000 监听（ApiClient.baseUrl 硬编码该地址）
class _MockAuthServer {
  final List<_RecordedRequest> requests = [];

  /// 是否已完成改密（影响 /api/login 的返回语义）
  bool passwordChanged = false;

  HttpServer? _server;

  Future<void> start() async {
    // 绑定失败（如 5000 被占用）会直接抛出，测试立即给出明确原因
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 5000);
    _server!.listen((HttpRequest request) async {
      final bodyRaw = await utf8.decoder.bind(request).join();
      Map<String, dynamic> body = <String, dynamic>{};
      try {
        final decoded = jsonDecode(bodyRaw);
        if (decoded is Map<String, dynamic>) body = decoded;
      } on FormatException {
        // 非 JSON 请求体按空处理
      }
      requests.add(_RecordedRequest(
        request.method,
        request.uri.path,
        body,
        request.headers.value('Authorization'),
      ));
      await _route(request, body);
    });
  }

  void reset() {
    requests.clear();
    passwordChanged = false;
  }

  Future<void> _route(HttpRequest request, Map<String, dynamic> body) async {
    if (request.method == 'POST' && request.uri.path == '/api/login') {
      final username = body['username']?.toString() ?? '';
      final password = body['password']?.toString() ?? '';
      final ok = username == _username &&
          ((passwordChanged && password == _newPwd) ||
              (!passwordChanged && password == _initialPwd));
      if (!ok) {
        await _json(request, 401, <String, dynamic>{
          'ok': false,
          'error': '用户名或密码错误',
        });
        return;
      }
      await _json(request, 200, <String, dynamic>{
        'ok': true,
        'token': passwordChanged ? 'tok-new' : 'tok-initial',
        'user': <String, dynamic>{
          'id': _adminId,
          'username': _username,
          'role': 'super_admin',
          'real_name': '总管理员',
        },
        // 契约 §4：初始口令阶段必须强制改密；改密成功后为 false
        'must_change_password': !passwordChanged,
      });
      return;
    }
    if (request.method == 'PUT' &&
        request.uri.path == '/api/users/$_adminId/password') {
      // 与真实后端一致：改密接口必须携带 Bearer token
      if (request.headers.value('Authorization') != 'Bearer tok-initial') {
        await _json(request, 401, <String, dynamic>{
          'ok': false,
          'error': 'unauthorized',
        });
        return;
      }
      passwordChanged = true;
      await _json(request, 200, <String, dynamic>{'ok': true});
      return;
    }
    await _json(
        request, 404, <String, dynamic>{'ok': false, 'error': 'not found'});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _json(
      HttpRequest request, int status, Map<String, dynamic> obj) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(obj));
    await request.response.close();
  }
}

/// 在真实事件循环里等待 mock 后端侧的交互完成（runAsync 期间真实 HTTP 可完成）。
///
/// 返回条件是否在超时前成立。这里刻意不抛异常：runAsync 内部抛出的异常会被
/// 测试框架"记录后吞掉"（报告为 Multiple exceptions），测试体反而继续往下跑，
/// 失败信息互相干扰；返回布尔值由调用方用 expect 断言，失败时干净地中止。
Future<bool> runUntil(WidgetTester tester, bool Function() done,
    {Duration timeout = const Duration(seconds: 5)}) async {
  var ok = false;
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(timeout);
    while (!(ok = done()) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (ok) {
      // 额外让渡一小段真实时间，保证响应解析与 setState 完成
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  });
  return ok;
}

/// 在真实事件循环里触发一次点击。
///
/// 触发 HTTP 的点击必须让 onPressed 回调（及其中发起的请求）运行在
/// runAsync 的真实 zone 中：fake-async zone 里发起的 socket 请求永远不会
/// 被处理（见文件顶部"陷阱 2"）。纯本地交互（无网络）不需要用它。
Future<void> tapInRealAsync(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
  });
}

/// 让 SnackBar 的自动消失定时器走完并卸载整棵树，避免遗留定时器/动画
Future<void> settleSnackBarAndTearDown(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4)); // auto-hide 定时器
  await tester.pump(const Duration(seconds: 1)); // 退场动画
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  late _MockAuthServer server;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // 替换 flutter_test 的全局 HttpClient mock，恢复真实回环 HTTP（见类注释）
    HttpOverrides.global = _RealLoopbackHttpOverrides();
    server = _MockAuthServer();
    await server.start();
  });

  tearDownAll(() async {
    await server.stop();
    HttpOverrides.global = null;
  });

  Future<void> pumpLogin(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: <String, WidgetBuilder>{
          '/dashboard': (_) => const Scaffold(
                body: Center(child: Text(_dashboardText)),
              ),
        },
        home: const LoginScreen(),
      ),
    );
    await tester.pump();
  }

  Future<void> fillCredentials(WidgetTester tester,
      {required String username, required String password}) async {
    await tester.enterText(find.byType(TextField).at(0), username);
    await tester.enterText(find.byType(TextField).at(1), password);
  }

  testWidgets('错误凭据：显示后端错误 SnackBar，且不进入主界面', (tester) async {
    server.reset();
    await pumpLogin(tester);
    await fillCredentials(tester, username: _username, password: 'wrong-pwd');

    // 登录点击在真实 zone 内触发，HTTP 请求才能真正发往 mock 后端
    await tapInRealAsync(tester, find.text('登录'));
    final arrived = await runUntil(tester,
        () => server.requests.any((r) => r.path == '/api/login'));
    expect(arrived, isTrue, reason: 'mock 后端应在 5s 内收到 /api/login 请求');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // SnackBar 入场动画

    expect(find.text('用户名或密码错误'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(_dashboardText), findsNothing);
    await settleSnackBarAndTearDown(tester);
  });

  testWidgets('用户名或密码为空：直接拦截提示，不发起网络请求', (tester) async {
    server.reset();
    await pumpLogin(tester);
    // 只填用户名，密码留空
    await fillCredentials(tester, username: _username, password: '');

    await tester.tap(find.text('登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('请输入用户名和密码'), findsOneWidget);
    expect(server.requests, isEmpty, reason: '本地校验拦截后不得发起任何 HTTP 请求');
    expect(find.text(_dashboardText), findsNothing);
    await settleSnackBarAndTearDown(tester);
  });

  testWidgets('must_change_password=true：弹出强制改密对话框，改密成功前不进主界面',
      (tester) async {
    server.reset();
    await pumpLogin(tester);
    await fillCredentials(tester, username: _username, password: _initialPwd);

    // 第一次登录（读 must_change_password / user.id / token）——真实 zone 触发
    await tapInRealAsync(tester, find.text('登录'));
    final arrived = await runUntil(tester,
        () => server.requests.any((r) => r.path == '/api/login'));
    expect(arrived, isTrue, reason: 'mock 后端应在 5s 内收到第一次 /api/login');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 对话框弹出
    expect(find.text('请修改初始密码'), findsOneWidget);
    // 改密成功前绝不进入主界面
    expect(find.text(_dashboardText), findsNothing);

    // 填写对话框三个密码框：旧密码 / 新密码 / 确认新密码
    final dialogFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogFields.at(0), _initialPwd);
    await tester.enterText(dialogFields.at(1), _newPwd);
    await tester.enterText(dialogFields.at(2), _newPwd);
    // 提交改密（PUT /api/users/{id}/password）——同样必须真实 zone 触发
    await tapInRealAsync(tester, find.text('确认修改'));
    final changed = await runUntil(tester, () => server.passwordChanged);
    expect(changed, isTrue, reason: 'mock 后端应完成改密状态翻转');
    // 等待对话框 pop + 用新密码重建会话（第二次 POST /api/login）
    final relogged = await runUntil(
      tester,
      () => server.requests.where((r) => r.path == '/api/login').length >= 2,
    );
    expect(relogged, isTrue, reason: '改密成功后应自动用新密码重新登录');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 对话框已关闭，进入主界面
    expect(find.text('请修改初始密码'), findsNothing);
    expect(find.text(_dashboardText), findsOneWidget);

    // 核对改密请求：PUT /api/users/1/password，Bearer 初始 token + 新密码（契约 §4）
    final puts = server.requests.where((r) => r.method == 'PUT').toList();
    expect(puts, hasLength(1));
    expect(puts.single.path, '/api/users/$_adminId/password');
    expect(puts.single.authorization, 'Bearer tok-initial');
    expect(puts.single.body['password'], _newPwd);
    // 改密成功后用新密码重新登录了一次
    expect(server.requests.where((r) => r.path == '/api/login'), hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('强制改密对话框：两次新密码不一致时提示错误且不发请求', (tester) async {
    server.reset();
    await pumpLogin(tester);
    await fillCredentials(tester, username: _username, password: _initialPwd);

    await tapInRealAsync(tester, find.text('登录'));
    final arrived = await runUntil(tester,
        () => server.requests.any((r) => r.path == '/api/login'));
    expect(arrived, isTrue, reason: 'mock 后端应在 5s 内收到 /api/login 请求');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('请修改初始密码'), findsOneWidget);

    final dialogFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogFields.at(0), _initialPwd);
    await tester.enterText(dialogFields.at(1), 'A12345678');
    await tester.enterText(dialogFields.at(2), 'B12345678');
    await tester.tap(find.text('确认修改'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('两次输入的新密码不一致'), findsOneWidget);
    expect(server.requests.where((r) => r.method == 'PUT'), isEmpty);
    // 仍在对话框中，未进入主界面
    expect(find.text('请修改初始密码'), findsOneWidget);
    expect(find.text(_dashboardText), findsNothing);

    // 收尾：选择"暂不修改"关闭对话框（停留在登录页，不进主界面）
    await tester.tap(find.text('暂不修改'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('请修改初始密码'), findsNothing);
    expect(find.text(_dashboardText), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
