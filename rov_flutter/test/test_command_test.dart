// Wave 3 测试补全：经服务层发送控制命令时的 WS 出站报文结构测试
//
// 覆盖：move（forward）/ light（lightOn/lightOff）/ suction（grab/release，
// UI 层命令名经 PC 后端 translate_ui_command 翻译为 suction）三类命令，
// 以及 set_camera（嵌套 params 形态）与 token 缺省回退链。
//
// 实现方式：RovBackendService 连接本机回环 18794 端口上的伪 WS 网关
// （dart:io 实现），在网关侧回采客户端上行报文并断言 JSON 结构。
// 产品代码只读，不引入任何 mock 框架。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rov_flutter/core/services/rov_backend_service.dart';

/// 测试专用端口（与其余测试文件错开）
const int _gatewayPort = 18794;

/// 伪网关：连接即回 hello，记录全部客户端上行报文
class FakeGatewayServer {
  final int port;
  HttpServer? _server;
  final List<Map<String, dynamic>> received = [];

  FakeGatewayServer(this.port);

  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add(jsonEncode(<String, dynamic>{'type': 'hello'}));
      socket.listen((data) {
        if (data is String) {
          final decoded = jsonDecode(data);
          if (decoded is Map<String, dynamic>) {
            received.add(decoded);
          }
        }
      }, onError: (Object _) {});
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}

/// 轮询等待网关回采到匹配的上行报文（超时即失败）
Future<Map<String, dynamic>> waitForOutbound(
  FakeGatewayServer gateway,
  bool Function(Map<String, dynamic>) predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    for (final message in gateway.received) {
      if (predicate(message)) {
        return message;
      }
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('等待 WS 出站报文超时，已收到：${gateway.received}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late FakeGatewayServer gateway;
  // RovBackendService 为单例：文件内所有用例共享，统一在连接好的前提下发命令
  final service = RovBackendService();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    gateway = FakeGatewayServer(_gatewayPort);
    await gateway.start();
  });

  tearDownAll(() async {
    await service.disconnect();
    await gateway.stop();
  });

  setUp(() async {
    // 每个用例重新连接并清空回采记录，保证互不串扰
    service.detachAuth();
    final ok = await service.connect(host: '127.0.0.1', port: _gatewayPort);
    expect(ok, isTrue, reason: '连接本地伪网关应成功');
    gateway.received.clear();
  });

  tearDown(() async {
    await service.disconnect();
  });

  group('move 类命令（服务层 → WS 出站）', () {
    test('forward：type/command/token/timestamp 齐全，speed 平铺在根层', () async {
      service.attachAuth('tok-move-1');
      // attachAuth 在已连接状态下会立即补发 auth（契约 §6 鉴权接线）
      final authMsg = await waitForOutbound(
        gateway,
        (m) => m['type'] == 'auth',
      );
      expect(authMsg['action'], 'login');
      expect(authMsg['token'], 'tok-move-1');
      gateway.received.clear();

      service.forward(speed: 0.75);
      final message = await waitForOutbound(
        gateway,
        (m) => m['type'] == 'command' && m['command'] == 'forward',
      );
      expect(message['type'], 'command');
      expect(message['command'], 'forward');
      expect(message['token'], 'tok-move-1');
      expect(message['speed'], 0.75);
      // timestamp 必须是可解析的 ISO8601 字符串
      expect(DateTime.tryParse(message['timestamp'] as String), isNotNull);
    });
  });

  group('light 类命令（服务层 → WS 出站）', () {
    test('setLight(true/false) → lightOn / lightOff，token 来自 attachAuth', () async {
      service.attachAuth('tok-light-2');
      await waitForOutbound(gateway, (m) => m['type'] == 'auth');
      gateway.received.clear();

      service.setLight(true);
      final onMsg = await waitForOutbound(
        gateway,
        (m) => m['command'] == 'lightOn',
      );
      expect(onMsg['type'], 'command');
      expect(onMsg['token'], 'tok-light-2');
      expect(DateTime.tryParse(onMsg['timestamp'] as String), isNotNull);

      service.setLight(false);
      final offMsg = await waitForOutbound(
        gateway,
        (m) => m['command'] == 'lightOff',
      );
      expect(offMsg['type'], 'command');
      expect(offMsg['token'], 'tok-light-2');
    });
  });

  group('suction 类命令（服务层 grab/release，后端翻译为 suction）', () {
    test('grab/release：命令名原样出站，由 PC 后端翻译为 suction', () async {
      service.attachAuth('tok-suction-3');
      await waitForOutbound(gateway, (m) => m['type'] == 'auth');
      gateway.received.clear();

      service.grab();
      final grabMsg = await waitForOutbound(
        gateway,
        (m) => m['command'] == 'grab',
      );
      expect(grabMsg['type'], 'command');
      expect(grabMsg['token'], 'tok-suction-3');

      service.release();
      final releaseMsg = await waitForOutbound(
        gateway,
        (m) => m['command'] == 'release',
      );
      expect(releaseMsg['type'], 'command');
      expect(releaseMsg['token'], 'tok-suction-3');
    });
  });

  test('set_camera：嵌套 params 形态（camera_id 在 params 内）', () async {
    service.attachAuth('tok-camera-4');
    await waitForOutbound(gateway, (m) => m['type'] == 'auth');
    gateway.received.clear();

    service.switchCamera('camera_2');
    final message = await waitForOutbound(
      gateway,
      (m) => m['command'] == 'set_camera',
    );
    expect(message['type'], 'command');
    expect(message['token'], 'tok-camera-4');
    final params = message['params'];
    expect(params, isA<Map<dynamic, dynamic>>());
    expect((params as Map<dynamic, dynamic>)['camera_id'], 'camera_2');
  });

  test('token 缺省回退：未 attachAuth 且 UserSession 无令牌时出站 token 为空串',
      () async {
    service.detachAuth();
    service.sendCommand(RovCommand.stop);
    final message = await waitForOutbound(
      gateway,
      (m) => m['command'] == 'stop',
    );
    expect(message['type'], 'command');
    expect(message['command'], 'stop');
    // 无任何已注入令牌 → token 允许为空串（后端将回 unauthorized，不执行）
    expect(message['token'], '');
  });
}
