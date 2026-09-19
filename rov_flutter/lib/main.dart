import 'package:flutter/material.dart';
import 'dart:io';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/services/rov_backend_service.dart';

Process? _backendProcess;

/// 启动所在项目父目录中的 Python 后端服务
Future<void> _startBackend() async {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    try {
      final currentDir = Directory.current.path;
      String backendWorkingDir = currentDir.endsWith('rov_flutter')
          ? '${Directory.current.parent.path}${Platform.pathSeparator}backend'
          : '$currentDir${Platform.pathSeparator}backend';

      // 打包态（Inno 布局）：SeaUI.exe 同级的 backend\SeaUIBackend.exe，
      // 客户机器无需 Python 环境；显式环境变量可覆盖（如 ROV_BACKEND_MODE=sim 演示）。
      if (Platform.isWindows) {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final packagedBackendDir = '$exeDir${Platform.pathSeparator}backend';
        final packagedBackendExe =
            '$packagedBackendDir${Platform.pathSeparator}SeaUIBackend.exe';
        if (await File(packagedBackendExe).exists()) {
          debugPrint('====== Starting packaged SeaUIBackend ======');
          _backendProcess = await Process.start(
            packagedBackendExe,
            const [],
            workingDirectory: packagedBackendDir,
            mode: ProcessStartMode.normal,
          );
          _backendProcess!.stdout.listen(stdout.add);
          _backendProcess!.stderr.listen(stderr.add);
          return;
        }
      }

      final appPyPath = '$backendWorkingDir${Platform.pathSeparator}app.py';

      if (await File(appPyPath).exists()) {
        debugPrint('====== Starting Python Backend ======');
        _backendProcess = await Process.start(
          'python',
          ['app.py'],
          workingDirectory: backendWorkingDir,
          mode: ProcessStartMode.normal, // normal模式使得我们可以kill它
        );
        debugPrint('Backend started with PID: ${_backendProcess!.pid}');

        // 捕获输出便于调试
        _backendProcess!.stdout.listen((event) => stdout.add(event));
        _backendProcess!.stderr.listen((event) => stderr.add(event));
      } else {
        debugPrint('Warning: Python backend file not found at $appPyPath');
      }
    } catch (e) {
      debugPrint('Failed to start Python backend: $e');
    }
  }
}

/// 监听应用生命周期用于清理后端进程
class LifecycleEventHandler extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.detached) {
      if (_backendProcess != null) {
        debugPrint('App detached. Killing backend process (PID: ${_backendProcess!.pid})...');
        _backendProcess!.kill();
        _backendProcess = null;
      }
    }
  }
}

/// 初始化桌面端窗口（window_manager 仅桌面平台生效，Android 直接跳过）
///
/// 契约要求：窗口可调、最小 1024×640、默认 1440×900、标题 SeaUI、居中。
/// 原先 windows/runner/main.cpp 中固定 1280×720 的 hack 已移除。
Future<void> _initDesktopWindow() async {
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;

  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1440, 900),           // 默认窗口尺寸
    minimumSize: Size(1024, 640),    // 最小可读布局尺寸
    center: true,                    // 首次启动居中
    title: AppConstants.appWindowTitle,
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    // 窗口可自由调整大小（0.5.x 的 WindowOptions 无 resizable 参数，单独设置）
    await windowManager.setResizable(true);
    await windowManager.show();
    await windowManager.focus();
  });
}

/// 应用程序入口
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 注册生命周期监听器
  WidgetsBinding.instance.addObserver(LifecycleEventHandler());

  // 桌面端窗口尺寸/标题/居中初始化（Android 无窗口概念，跳过）
  await _initDesktopWindow();

  // 运行前启动后端服务
  await _startBackend();

  // 连接 Python 后端 WebSocket 视频流。
  // 注意：连接建立后后端只回 hello；登录成功（UserSession.login）会自动
  // 调用 RovBackendService().attachAuth(token) 发送鉴权，之后才开始推流。
  final service = RovBackendService();
  service.setVideoSourceType(VideoSourceType.websocket);
  service.setServerAddress('localhost', 8765);
  service.connectVideoSource();

  runApp(const ROVApp());
}
