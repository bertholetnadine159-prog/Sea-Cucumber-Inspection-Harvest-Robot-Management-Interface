// Wave 3 测试补全：服务层单元测试（契约 docs/UPGRADE_CONTRACTS.md §5/§6）
//
// 覆盖：
// 1. VideoFrame.linkLatencySeconds：正常计算 / sent_ts 缺失返 null / 时钟倒挂返 null
// 2. TelemetrySnapshot.ageSeconds：按 lastUpdated 推算数据年龄
// 3. 连接状态机：离线 → 连接成功 → 服务端断开后进入重连中（本地伪 WS 网关回环）
// 4. StaleBadge 组件：超时阈值前无徽标、超时后出现"⚠ 信号丢失"、数据恢复后消失
//
// 说明：本文件不修改任何产品代码；网络类用例通过 dart:io 在 127.0.0.1 起
// 真实回环端口上的伪网关（选不冲突端口 18791）完成。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rov_flutter/core/services/rov_backend_service.dart';
import 'package:rov_flutter/features/shared/widgets/stale_badge.dart';

/// 测试专用端口（与其余测试文件错开，避免并行回环端口冲突）
const int _fakeGatewayPort = 18791;

/// 等待条件成立（真实事件循环轮询，超时即失败）
Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String message = 'waitUntil 超时',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(message);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// 本地伪 WS 网关：dart:io HttpServer + WebSocketTransformer 升级实现，
/// 连接后先推 hello（对齐后端"未 auth 只回 hello"协议），并记录客户端上行报文。
class FakeGatewayServer {
  FakeGatewayServer(this.port);

  final int port;
  HttpServer? _server;
  final List<WebSocket> sockets = [];

  /// 收到的客户端上行文本报文（已 JSON 解码）
  final List<Map<String, dynamic>> received = [];

  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.add(jsonEncode(<String, dynamic>{
        'type': 'hello',
        'message': 'fake-gateway',
      }));
      socket.listen(
        (data) {
          if (data is String) {
            final decoded = jsonDecode(data);
            if (decoded is Map<String, dynamic>) {
              received.add(decoded);
            }
          }
        },
        onDone: () => sockets.remove(socket),
        onError: (Object _) {},
      );
    });
  }

  /// 停止网关：先对已升级的 WebSocket 逐个发送 close 帧（触发客户端
  /// onDone → 重连中），再强断监听端口。
  ///
  /// 注意 1：dart:io 的 `HttpServer.close(force: true)` 不会终止已经
  /// WebSocket 升级的连接（升级后连接已脱离 HttpServer 的连接跟踪），
  /// 因此必须显式关闭每个 socket。
  ///
  /// 注意 2：close 帧发出后必须留出真实时间让它送达客户端。实测若在
  /// close 后立刻 `close(force: true)`，强制销毁底层 socket 可能吞掉
  /// 尚未完成传输的 close 帧，客户端永远感知不到断链（连接建立后立即
  /// 关闭时 100% 复现），导致状态机测试超时。这里排水 100ms 作为兜底。
  Future<void> stop() async {
    for (final socket in List<WebSocket>.of(sockets)) {
      try {
        await socket.close();
      } on WebSocketException {
        // 客户端可能已先行断开
      }
    }
    // 排水：等 close 帧真正送达客户端后再销毁监听端口（见上方"注意 2"）
    await Future<void>.delayed(const Duration(milliseconds: 100));
    sockets.clear();
    await _server?.close(force: true);
    _server = null;
  }
}

/// 服务层 disconnect 的超时保护包装。
///
/// 产品代码（本测试只读、不许改）的 `disconnect` 实现里有
/// `await _channel?.sink.close()`：当 `_channel` 是"自动重连失败后残留的
/// 未建立通道"时，该 sink 的 close future 实测永不完成，会让
/// `addTearDown(service.disconnect)` 挂死直到 30s 整体超时。
/// 用 timeout 兜底跳过：`_manualDisconnect`、重连定时器取消等同步清理
/// 都发生在挂起点之前，状态已是安全的；残留的 sink close 后台自行消亡。
Future<void> guardedDisconnect(RovBackendService service) {
  return service
      .disconnect(manual: true)
      .timeout(const Duration(seconds: 2), onTimeout: () {});
}

void main() {
  group('VideoFrame.linkLatencySeconds（契约 §5 ≈链路时延）', () {
    test('sent_ts 缺失时返回 null，不猜测时延', () {
      final frame = VideoFrame(
        jpegBytes: Uint8List(4),
        fps: 15,
        receivedAt: DateTime.now(),
      );
      expect(frame.sentTs, isNull);
      expect(frame.linkLatencySeconds, isNull);
    });

    test('正常链路：时延为正且约等于帧在本地滞留的时长', () async {
      // 网关在 0.5s 前发出（sent_ts 为 epoch 秒），本地稍后才收到
      final sentTs =
          DateTime.now().millisecondsSinceEpoch / 1000.0 - 0.5;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final frame = VideoFrame(
        jpegBytes: Uint8List(4),
        fps: 15,
        sentTs: sentTs,
        receivedAt: DateTime.now(),
      );
      final latency = frame.linkLatencySeconds;
      expect(latency, isNotNull);
      expect(latency, greaterThanOrEqualTo(0.5));
      expect(latency, lessThan(3.0));
    });

    test('时钟倒挂（sent_ts 晚于本地接收时刻）时返回 null，避免负值误导', () {
      final futureSentTs =
          DateTime.now().millisecondsSinceEpoch / 1000.0 + 10.0;
      final frame = VideoFrame(
        jpegBytes: Uint8List(4),
        fps: 15,
        sentTs: futureSentTs,
        receivedAt: DateTime.now(),
      );
      expect(frame.linkLatencySeconds, isNull);
    });
  });

  group('TelemetrySnapshot.ageSeconds', () {
    test('刚收到的快照年龄接近 0', () {
      final snapshot = TelemetrySnapshot(
        status: const <String, dynamic>{},
        sensors: const <String, dynamic>{},
        pixhawk: const <String, dynamic>{},
        rdk: const <String, dynamic>{},
        lastUpdated: DateTime.now(),
      );
      expect(snapshot.ageSeconds, inInclusiveRange(-0.5, 0.5));
    });

    test('lastUpdated 在 3 秒前 → 年龄约 3 秒', () {
      final snapshot = TelemetrySnapshot(
        status: const <String, dynamic>{},
        sensors: const <String, dynamic>{},
        pixhawk: const <String, dynamic>{},
        rdk: const <String, dynamic>{},
        lastUpdated: DateTime.now().subtract(const Duration(seconds: 3)),
      );
      expect(snapshot.ageSeconds, inInclusiveRange(2.5, 4.5));
    });
  });

  group('连接状态机（connectionNotifier，契约 §6）', () {
    test('离线 → 连接成功 → 服务端断开后进入重连中且持续重试', () async {
      final service = RovBackendService();
      // 不能用裸 tear-off：断链残留通道的 sink.close 可能挂死（见
      // guardedDisconnect 注释），必须带超时保护
      addTearDown(() => guardedDisconnect(service));

      // 1) 初始态：离线（未连接）
      expect(
        service.connectionNotifier.value.phase,
        RovConnectionPhase.offline,
      );

      // 2) 起本地伪网关并连接 → connected
      final gateway = FakeGatewayServer(_fakeGatewayPort);
      await gateway.start();
      addTearDown(gateway.stop);
      final ok = await service.connect(
        host: '127.0.0.1',
        port: _fakeGatewayPort,
      );
      expect(ok, isTrue, reason: '连接本地伪网关应成功');
      expect(
        service.connectionNotifier.value.phase,
        RovConnectionPhase.connected,
      );
      expect(service.isConnected, isTrue);

      // 2.1) 注入 token 触发客户端上行 auth 报文，并以"网关收到上行"为
      //      全双工就绪信号：握手刚建立就立刻断开的话，close 帧会与握手
      //      尾巴竞态（实测必现丢失），客户端永远感知不到断链。
      service.attachAuth('test-token');
      await waitUntil(
        () => gateway.received.isNotEmpty,
        message: '伪网关应收到客户端 auth 上行报文（链路未就绪）',
      );

      // 3) 服务端强制断开 → 客户端自动进入 reconnecting
      //    （waitUntil 轮询 notifier，而非 await 单次事件：重连循环每次
      //    重试都会更新 notifier，await 单事件极易错过）
      await gateway.stop();
      await waitUntil(
        () =>
            service.connectionNotifier.value.phase ==
            RovConnectionPhase.reconnecting,
        message: '服务端断开后应进入重连中状态',
      );
      expect(service.connectionNotifier.value.message, contains('重连'));

      // 4) 指数退避的第一次重连失败（网关已停止监听）后仍停留在 reconnecting，
      //    不允许误报 offline（否则 UI 会把"重连中"当成"已手动断开"）
      await Future<void>.delayed(const Duration(milliseconds: 2600));
      expect(
        service.connectionNotifier.value.phase,
        RovConnectionPhase.reconnecting,
      );

      // 5) 立即手动断开收尾（带超时保护），不让重连定时器/失败通道泄漏到
      //    下一个用例或 tearDown
      await guardedDisconnect(service);
    });

    test('手动断开后回到离线且不再自动重连', () async {
      final service = RovBackendService();
      addTearDown(() => guardedDisconnect(service));

      // 独立端口，避免与其它用例/测试文件的回环端口冲突
      const manualPort = _fakeGatewayPort + 2; // 18793
      final gateway = FakeGatewayServer(manualPort);
      await gateway.start();
      addTearDown(gateway.stop);

      expect(
        await service.connect(host: '127.0.0.1', port: manualPort),
        isTrue,
      );
      await service.disconnect(manual: true);
      expect(
        service.connectionNotifier.value.phase,
        RovConnectionPhase.offline,
      );
      expect(service.isConnected, isFalse);
      // 手动断开后不应出现 reconnecting（无自动重连定时器）
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(
        service.connectionNotifier.value.phase,
        RovConnectionPhase.offline,
      );
    });
  });

  group('StaleBadge（契约 §6 信号丢失徽标）', () {
    Future<void> pumpBadge(WidgetTester tester, DateTime? lastUpdated) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StaleBadge(lastUpdated: lastUpdated),
          ),
        ),
      );
      // initState 首评 + 稳定一帧
      await tester.pump();
    }

    testWidgets('数据新鲜（阈值内）时不显示徽标', (tester) async {
      await pumpBadge(tester, DateTime.now());
      expect(find.text('⚠ 信号丢失'), findsNothing);
      // 卸载组件以取消内部 1 秒周期定时器，避免遗留定时器
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('超过超时阈值（5s）后出现"⚠ 信号丢失"', (tester) async {
      await pumpBadge(
        tester,
        DateTime.now().subtract(const Duration(seconds: 6)),
      );
      expect(find.text('⚠ 信号丢失'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('lastUpdated == null（从未收到数据）视为断链', (tester) async {
      await pumpBadge(tester, null);
      expect(find.text('⚠ 信号丢失'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('数据恢复（lastUpdated 更新）后徽标自动消失', (tester) async {
      Widget badgeWith(DateTime ts) => MaterialApp(
            home: Scaffold(body: StaleBadge(lastUpdated: ts)),
          );

      // 断链状态：先出现徽标
      await tester.pumpWidget(
        badgeWith(DateTime.now().subtract(const Duration(seconds: 6))),
      );
      await tester.pump();
      expect(find.text('⚠ 信号丢失'), findsOneWidget);

      // 数据恢复：外部刷新 lastUpdated → didUpdateWidget 即时评估 → 徽标消失
      await tester.pumpWidget(badgeWith(DateTime.now()));
      await tester.pump();
      expect(find.text('⚠ 信号丢失'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('自定义阈值生效（阈值 30s 内的 6s 旧数据不告警）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StaleBadge(
              lastUpdated: DateTime.now().subtract(const Duration(seconds: 6)),
              staleThreshold: const Duration(seconds: 30),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('⚠ 信号丢失'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
