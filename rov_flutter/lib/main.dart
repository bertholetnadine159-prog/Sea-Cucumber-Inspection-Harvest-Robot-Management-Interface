import 'package:flutter/material.dart';
import 'dart:io';
import 'app.dart';
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

/// 应用程序入口
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 注册生命周期监听器
  WidgetsBinding.instance.addObserver(LifecycleEventHandler());
  
  // 运行前启动后端服务
  await _startBackend();
  
  // 连接 Python 后端 WebSocket 视频流
  final service = RovBackendService();
  service.setVideoSourceType(VideoSourceType.websocket);
  service.setServerAddress('localhost', 8765);
  service.connectVideoSource();
  
  runApp(const ROVApp());
}
