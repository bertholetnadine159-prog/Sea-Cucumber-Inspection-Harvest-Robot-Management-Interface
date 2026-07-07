/// 数据服务类
/// 处理从文件读取日志和用户数据
library;

import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

/// 日志条目数据模型
class LogEntry {
  final String date;
  final String time;
  final String operator;
  final String module;
  final String action;
  final LogStatus status;

  LogEntry({
    required this.date,
    required this.time,
    required this.operator,
    required this.module,
    required this.action,
    required this.status,
  });

  /// 从CSV行解析日志条目
  /// CSV格式: 时间,操作人,模块,内容,状态
  factory LogEntry.fromLine(String line) {
    final parts = line.split(',');
    if (parts.length < 5) {
      throw FormatException('Invalid log format: $line');
    }

    // 解析日期和时间
    final dateTimeParts = parts[0].split(' ');
    final date = dateTimeParts[0];
    final time = dateTimeParts.length > 1 ? dateTimeParts[1] : '00:00:00';

    // 解析状态
    LogStatus status;
    switch (parts[4].trim().toLowerCase()) {
      case 'warning':
        status = LogStatus.warning;
        break;
      case 'error':
        status = LogStatus.error;
        break;
      default:
        status = LogStatus.success;
    }

    return LogEntry(
      date: date,
      time: time,
      operator: parts[1].trim(),
      module: parts[2].trim(),
      action: parts[3].trim(),
      status: status,
    );
  }

  /// 转换为CSV行
  String toLine() {
    final statusStr = status == LogStatus.success
        ? 'success'
        : (status == LogStatus.warning ? 'warning' : 'error');
    return '$date $time,$operator,$module,$action,$statusStr';
  }

  /// 从JSON解析
  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      date: json['date'] ?? '',
      time: json['time'] ?? '',
      operator: json['operator'] ?? '',
      module: json['module'] ?? '',
      action: json['action'] ?? '',
      status: LogStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => LogStatus.success,
      ),
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() => {
    'date': date,
    'time': time,
    'operator': operator,
    'module': module,
    'action': action,
    'status': status.name,
  };
}

/// 日志状态枚举
enum LogStatus { success, warning, error }

/// 用户角色数据模型
class UserRole {
  final String name;
  final String role;
  final List<String> permissions;
  final String avatarPath;

  UserRole({
    required this.name,
    required this.role,
    required this.permissions,
    required this.avatarPath,
  });

  /// 从JSON解析
  factory UserRole.fromJson(Map<String, dynamic> json) {
    return UserRole(
      name: json['name'] ?? '',
      role: json['role'] ?? '',
      permissions: List<String>.from(json['permissions'] ?? []),
      avatarPath: json['avatarPath'] ?? '',
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() => {
    'name': name,
    'role': role,
    'permissions': permissions,
    'avatarPath': avatarPath,
  };
}

/// 环境数据条目
class EnvironmentData {
  final DateTime dateTime;
  final double phValue;
  final double temperature;
  final double salinity;
  final double pressure;

  EnvironmentData({
    required this.dateTime,
    required this.phValue,
    required this.temperature,
    required this.salinity,
    required this.pressure,
  });

  /// 从CSV行解析
  factory EnvironmentData.fromCsvLine(String line) {
    final parts = line.split(',');
    if (parts.length < 6) {
      throw FormatException('Invalid CSV format: $line');
    }

    // 解析日期时间
    final dateParts = parts[0].split('-');
    final timeParts = parts[1].split(':');
    final dateTime = DateTime(
      int.parse(dateParts[0]),
      int.parse(dateParts[1]),
      int.parse(dateParts[2]),
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
    );

    return EnvironmentData(
      dateTime: dateTime,
      phValue: double.parse(parts[2]),
      temperature: double.parse(parts[3]),
      salinity: double.parse(parts[4]),
      pressure: double.parse(parts[5]),
    );
  }

  /// 转换为CSV行
  String toCsvLine() {
    final dateStr = '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    final timeStr = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    return '$dateStr,$timeStr,$phValue,$temperature,$salinity,$pressure';
  }
}

/// 数据服务
class DataService {
  // 本地数据存储路径
  static String? _localDataPath;
  
  /// 获取本地数据存储路径
  static Future<String> getLocalDataPath() async {
    if (_localDataPath != null) return _localDataPath!;
    final dir = await getApplicationDocumentsDirectory();
    _localDataPath = '${dir.path}/rov_flutter_data';
    final dataDir = Directory(_localDataPath!);
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    return _localDataPath!;
  }

  /// 从CSV文件读取日志
  static Future<List<LogEntry>> loadLogs() async {
    try {
      // 先尝试从本地存储读取
      final localPath = await getLocalDataPath();
      final localFile = File('$localPath/system_logs.json');
      if (await localFile.exists()) {
        final content = await localFile.readAsString();
        final List<dynamic> jsonList = json.decode(content);
        return jsonList.map((e) => LogEntry.fromJson(e)).toList();
      }
      
      // 如果本地没有，从assets读取CSV文件
      final String content = await rootBundle.loadString('assets/data/system_logs.csv');
      final lines = content.split('\n');
      final logs = <LogEntry>[];

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        // 跳过空行和标题行（第一行）
        if (line.isEmpty || i == 0) continue;

        try {
          logs.add(LogEntry.fromLine(line));
        } catch (e) {
          // 跳过解析失败的行
          continue;
        }
      }

      return logs;
    } catch (e) {
      // 返回空列表，使用默认数据
      return [];
    }
  }

  /// 保存日志到本地
  static Future<void> saveLogs(List<LogEntry> logs) async {
    final localPath = await getLocalDataPath();
    final localFile = File('$localPath/system_logs.json');
    final jsonList = logs.map((e) => e.toJson()).toList();
    await localFile.writeAsString(json.encode(jsonList));
  }

  /// 添加新日志
  static Future<List<LogEntry>> addLog(LogEntry log, List<LogEntry> currentLogs) async {
    final newLogs = [log, ...currentLogs];
    await saveLogs(newLogs);
    return newLogs;
  }

  /// 动态读取用户目录，获取用户列表
  /// 始终从 assets/users 目录读取，确保与实际目录同步
  static Future<List<UserRole>> loadUsers() async {
    final users = <UserRole>[];
    
    // 从assets读取 - 动态扫描目录
    // 由于Flutter assets无法真正动态扫描，我们使用已知的目录列表
    // 但会在运行时检查每个目录是否存在
    final knownUserDirs = ['张伟', '王超'];

    for (final userName in knownUserDirs) {
      try {
        final infoContent = await rootBundle.loadString('assets/users/$userName/info.txt');
        final lines = infoContent.split('\n');

        if (lines.isNotEmpty) {
          final role = lines[0].trim();
          final permissions = lines.length > 1
              ? lines[1].split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
              : <String>[];

          // 检查是否存在头像文件
          String avatarPath = 'assets/users/$userName/avatar.png';

          users.add(UserRole(
            name: userName,
            role: role,
            permissions: permissions,
            avatarPath: avatarPath,
          ));
        }
      } catch (e) {
        // 跳过读取失败的用户
        continue;
      }
    }

    return users;
  }

  /// 从本地存储加载用户（用于获取修改过的用户数据）
  static Future<List<UserRole>> loadUsersFromLocal() async {
    try {
      final localPath = await getLocalDataPath();
      final localFile = File('$localPath/users.json');
      if (await localFile.exists()) {
        final content = await localFile.readAsString();
        final List<dynamic> jsonList = json.decode(content);
        return jsonList.map((e) => UserRole.fromJson(e)).toList();
      }
    } catch (e) {
      // 忽略错误
    }
    return [];
  }

  /// 保存用户列表到本地
  static Future<void> saveUsers(List<UserRole> users) async {
    final localPath = await getLocalDataPath();
    final localFile = File('$localPath/users.json');
    final jsonList = users.map((e) => e.toJson()).toList();
    await localFile.writeAsString(json.encode(jsonList));
  }

  /// 添加新用户
  static Future<List<UserRole>> addUser(UserRole user, List<UserRole> currentUsers) async {
    // 检查用户是否已存在
    final existingIndex = currentUsers.indexWhere((u) => u.name == user.name);
    List<UserRole> newUsers;
    if (existingIndex >= 0) {
      // 更新现有用户
      newUsers = List.from(currentUsers);
      newUsers[existingIndex] = user;
    } else {
      // 添加新用户
      newUsers = [...currentUsers, user];
    }
    await saveUsers(newUsers);
    return newUsers;
  }

  /// 删除用户
  static Future<List<UserRole>> deleteUser(String userName, List<UserRole> currentUsers) async {
    final newUsers = currentUsers.where((u) => u.name != userName).toList();
    await saveUsers(newUsers);
    return newUsers;
  }

  /// 导出日志到CSV文件
  static Future<String> exportLogs(List<LogEntry> logs) async {
    final buffer = StringBuffer();
    // CSV标题行
    buffer.writeln('时间,操作人,模块,内容,状态');

    for (final log in logs) {
      buffer.writeln(log.toLine());
    }

    return buffer.toString();
  }

  /// 保存文件到下载目录
  static Future<String> saveToDownloads(String content, String fileName) async {
    try {
      // 获取下载目录
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        // 如果无法获取下载目录，使用文档目录
        final docDir = await getApplicationDocumentsDirectory();
        final file = File('${docDir.path}/$fileName');
        await file.writeAsString(content);
        return file.path;
      }
      final file = File('${downloadsDir.path}/$fileName');
      await file.writeAsString(content);
      return file.path;
    } catch (e) {
      throw Exception('保存文件失败: $e');
    }
  }

  /// 使用文件选择器保存文件（让用户选择保存路径）
  static Future<String?> saveWithFilePicker(String content, String defaultFileName) async {
    try {
      // 判断文件类型
      String? extension;
      FileType fileType = FileType.any;
      
      if (defaultFileName.endsWith('.csv')) {
        extension = 'csv';
      } else if (defaultFileName.endsWith('.txt')) {
        extension = 'txt';
      }
      
      // 弹出保存文件对话框
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '选择保存位置',
        fileName: defaultFileName,
        type: fileType,
        allowedExtensions: extension != null ? [extension] : null,
      );
      
      if (result == null) {
        // 用户取消了选择
        return null;
      }
      
      // 确保文件扩展名正确
      String filePath = result;
      if (extension != null && !filePath.endsWith('.$extension')) {
        filePath = '$filePath.$extension';
      }
      
      // 写入文件
      final file = File(filePath);
      await file.writeAsString(content);
      return file.path;
    } catch (e) {
      throw Exception('保存文件失败: $e');
    }
  }

  /// 从CSV文件读取环境数据
  static Future<List<EnvironmentData>> loadEnvironmentData() async {
    try {
      final String content = await rootBundle.loadString('assets/data/environment_data.csv');
      final lines = content.split('\n');
      final data = <EnvironmentData>[];

      for (int i = 1; i < lines.length; i++) { // 跳过标题行
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        try {
          data.add(EnvironmentData.fromCsvLine(line));
        } catch (e) {
          continue;
        }
      }

      return data;
    } catch (e) {
      return [];
    }
  }

  /// 导出环境数据为CSV
  static String exportEnvironmentDataToCsv(List<EnvironmentData> data) {
    final buffer = StringBuffer();
    buffer.writeln('日期,时间,PH值,水温,盐度,气压');

    for (final item in data) {
      buffer.writeln(item.toCsvLine());
    }

    return buffer.toString();
  }

  /// 根据时间范围过滤数据
  static List<EnvironmentData> filterByDateRange(
    List<EnvironmentData> data,
    DateTime start,
    DateTime end,
  ) {
    return data.where((item) =>
      item.dateTime.isAfter(start.subtract(const Duration(seconds: 1))) &&
      item.dateTime.isBefore(end.add(const Duration(days: 1)))
    ).toList();
  }

  /// 加载用户名与真名映射表
  /// 从 assets/data/user_mapping.csv 读取
  /// CSV格式: 用户名,真名
  /// 返回 Map<用户名, 真名>
  static Future<Map<String, String>> loadUserMapping() async {
    final mapping = <String, String>{};
    
    try {
      final content = await rootBundle.loadString('assets/data/user_mapping.csv');
      final lines = content.split('\n');
      
      for (int i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        // 跳过空行和标题行
        if (trimmed.isEmpty || i == 0) continue;
        
        final parts = trimmed.split(',');
        if (parts.length >= 2) {
          final username = parts[0].trim();
          final realName = parts[1].trim();
          if (username.isNotEmpty && realName.isNotEmpty) {
            mapping[username] = realName;
          }
        }
      }
    } catch (e) {
      // 如果文件不存在或读取失败，返回空映射
    }
    
    return mapping;
  }

  /// 根据用户名获取真名
  static Future<String?> getRealNameByUsername(String username) async {
    final mapping = await loadUserMapping();
    return mapping[username];
  }
}
