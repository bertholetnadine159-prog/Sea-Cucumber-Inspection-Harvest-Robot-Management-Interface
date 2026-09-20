/// 命令 ack 确认与登出会话吊销的界面层通道（features 层）
///
/// 边界说明：`RovBackendService` 收到后端 `ack` 只落 debugPrint
/// （core/services/rov_backend_service.dart `case 'ack'`），主通道上的命令
/// 结果 UI 读不到；core/services 按本轮约束只读不改。因此沿用
/// admin_panel_desktop / data_analysis_desktop 页内 `_UiSocketRequest` 的
/// 既有模式：临时短连接触达后端，拿到 ack 后立即关闭，不新增常驻连接，
/// 不新增计时器（铁律⑤；超时用一次性 `Future.timeout`，随连接关闭即释放）。
///
/// 协议事实（backend/app.py，只读走查）：
/// - 命令 ack：`{"type":"ack","command":...,"success":true|false,"message":...}`；
///   emergency_stop 对任何已鉴权角色永远放行，未鉴权回 success=false
///   unauthorized，无权命令回 forbidden。
/// - `{"type":"auth","action":"logout","token":...}` → 服务端
///   `revoke_session(token)` 删除该会话行，对任意连接生效（app.py:456-464）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/services/rov_backend_service.dart';
import '../../../core/services/user_session.dart';

/// 单条命令的后端 ack 确认结果
class CommandAckResult {
  /// 后端 ack.success == true（命令已被后端受理执行）
  final bool confirmed;

  /// 确认通道本身是否可用（false = 连接失败/超时，结果未知）
  final bool transportOk;

  /// 人类可读口径（ack 原文的人话翻译，或失败原因）
  final String message;

  const CommandAckResult({
    required this.confirmed,
    required this.transportOk,
    required this.message,
  });
}

/// 界面层命令通道：短连接发送命令并等待后端 ack；尽力吊销服务端会话。
class CommandLink {
  /// 确认通道超时（急停确认链路：连接 + auth + 命令 + ack 实测两位数毫秒级，
  /// 5s 已覆盖弱网；超时用 Future.timeout，不持有 Timer）
  static const Duration _timeout = Duration(seconds: 5);

  /// 短连接发送命令并等待首个 ack（与页内 _UiSocketRequest 同模式：
  /// 连接 → auth → 命令 → 首个 type=ack 即完成 → 关闭）。
  ///
  /// 连接失败/超时返回 transportOk=false 的结果，不抛出。
  static Future<CommandAckResult> sendCommandAwaitAck({
    required String serverAddress,
    required String token,
    required String command,
    Map<String, dynamic> params = const {},
  }) async {
    WebSocketChannel? channel;
    StreamSubscription<dynamic>? sub;
    final completer = Completer<Map<String, dynamic>>();
    try {
      channel = WebSocketChannel.connect(Uri.parse('ws://$serverAddress'));
      await channel.ready.timeout(_timeout);
      sub = channel.stream.listen(
        (data) {
          if (data is String && !completer.isCompleted) {
            try {
              final msg = json.decode(data) as Map<String, dynamic>;
              // 命令 ack 即完成（hello/auth_result/frame/status 等忽略）
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
      channel.sink.add(json.encode({
        'type': 'command',
        'command': command,
        'params': params,
        'token': token,
        'timestamp': DateTime.now().toIso8601String(),
      }));
      final ack = await completer.future.timeout(_timeout);
      return CommandAckResult(
        confirmed: ack['success'] == true,
        transportOk: true,
        message: humanizeAck(ack),
      );
    } on TimeoutException {
      return const CommandAckResult(
        confirmed: false,
        transportOk: false,
        message: '后端响应超时，未获确认',
      );
    } catch (_) {
      return const CommandAckResult(
        confirmed: false,
        transportOk: false,
        message: '无法连接后端确认通道',
      );
    } finally {
      try {
        await sub?.cancel();
      } catch (_) {}
      try {
        await channel?.sink.close().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  /// 尽力吊销服务端会话：发送 `auth action=logout`，服务端按 token 删会话行。
  ///
  /// 只发不等回执（后端收到即吊销）；WS 可能已断，任何失败静默返回 false，
  /// 调用方必须继续本地清理、不得阻断登出。
  static Future<bool> revokeSession({
    required String serverAddress,
    required String token,
  }) async {
    if (token.isEmpty) return false;
    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(Uri.parse('ws://$serverAddress'));
      await channel.ready.timeout(_timeout);
      channel.sink.add(json.encode({'type': 'auth', 'action': 'logout', 'token': token}));
      await channel.sink.close().timeout(const Duration(seconds: 2));
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        await channel?.sink.close().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  /// ack 失败原因的人话口径（success=true 时返回"已执行"）
  static String humanizeAck(Map<String, dynamic> ack) {
    if (ack['success'] == true) return '已执行';
    final raw = ack['message']?.toString() ?? '被后端拒绝';
    switch (raw) {
      case 'forbidden':
        return '权限不足（forbidden）：当前账号无权执行该命令';
      case 'unauthorized':
        return '登录会话已失效（unauthorized），请重新登录';
      default:
        return raw;
    }
  }
}

/// 急停闭环：三个入口（悬浮急停球 / operate 页 / 主控页）共用同一确认口径。
///
/// 流程：先经既有主通道快路径下发（能发就发，真车立即受益），再经短连接
/// 等待后端 ack：「已急停」只在 ack.success=true 后显示；ack.success=false
/// （forbidden/unauthorized）写入 [alarm] 升级为红色常驻告警直到恢复
/// （下一次急停获确认，或操作者手动关闭）。
class EmergencyStopFlow {
  /// 红色常驻告警文案（null = 无告警）。ValueNotifier 承载，无计时器（铁律⑤）。
  static final ValueNotifier<String?> alarm = ValueNotifier<String?>(null);

  /// 手动关闭常驻告警
  static void clearAlarm() => alarm.value = null;

  /// 触发一次急停并等待后端确认，返回 SnackBar 口径。
  static Future<EmergencyStopReport> fire() async {
    final service = RovBackendService();
    // 快路径：主通道能发就发（未连接时返回 false，命令没有发出）
    final primarySent = service.emergencyStop();
    final token = UserSession().authToken ?? '';

    if (token.isEmpty) {
      // 无令牌：后端必然拒绝执行（unauthorized），如实告知，不报"已急停"
      if (!primarySent) {
        alarm.value = '急停未发出：后端未连接，且当前无登录会话';
        return const EmergencyStopReport(
          confirmed: false,
          isError: true,
          text: '急停未发出：后端未连接，请检查连接后重试',
        );
      }
      alarm.value = '急停未执行：当前无登录会话，后端不会受理该命令（unauthorized）';
      return const EmergencyStopReport(
        confirmed: false,
        isError: true,
        text: '急停已交由通道发送，但当前未登录，后端不会执行，请重新登录后重试',
      );
    }

    final ack = await CommandLink.sendCommandAwaitAck(
      serverAddress: service.serverAddress,
      token: token,
      command: 'emergencyStop',
    );

    if (!ack.transportOk) {
      // 确认通道不可用：主通道已发出的场合如实报"未获确认"，未发出的报未发出
      if (primarySent) {
        return const EmergencyStopReport(
          confirmed: false,
          isError: true,
          text: '急停已交由通道发送，但未获后端确认，请观察推进器是否已停并重试',
        );
      }
      alarm.value = '急停未发出：后端未连接，请检查连接后重试';
      return const EmergencyStopReport(
        confirmed: false,
        isError: true,
        text: '急停未发出：后端未连接，请检查连接后重试',
      );
    }

    if (ack.confirmed) {
      // 恢复：清掉常驻告警
      alarm.value = null;
      return const EmergencyStopReport(
        confirmed: true,
        isError: false,
        text: '已急停（后端已确认执行）',
      );
    }

    // 后端明确拒绝：升级为红色常驻告警直到恢复
    alarm.value = '急停未执行：${ack.message}';
    return EmergencyStopReport(
      confirmed: false,
      isError: true,
      text: '急停被后端拒绝：${ack.message}',
    );
  }
}

/// 急停触发结果（SnackBar 口径）
class EmergencyStopReport {
  /// 后端 ack.success == true
  final bool confirmed;

  /// SnackBar 是否按错误（红色）呈现
  final bool isError;

  /// 展示文案
  final String text;

  const EmergencyStopReport({
    required this.confirmed,
    required this.isError,
    required this.text,
  });
}
