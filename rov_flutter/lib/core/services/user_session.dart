/// 用户会话服务
/// 管理当前登录用户的状态
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'data_service.dart';

/// 用户账户信息（用户名可变，人名不变）
class UserAccount {
  final String realName;      // 真实人名（不变）
  String username;            // 登录用户名（可变）
  String role;                // 角色
  List<String> permissions;   // 权限列表
  String avatarPath;          // 头像路径

  UserAccount({
    required this.realName,
    required this.username,
    required this.role,
    required this.permissions,
    this.avatarPath = '',
  });

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
      realName: json['realName'] ?? '',
      username: json['username'] ?? '',
      role: json['role'] ?? '',
      permissions: List<String>.from(json['permissions'] ?? []),
      avatarPath: json['avatarPath'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'realName': realName,
    'username': username,
    'role': role,
    'permissions': permissions,
    'avatarPath': avatarPath,
  };
}

/// 用户会话管理器（单例）
class UserSession extends ChangeNotifier {
  static final UserSession _instance = UserSession._internal();
  factory UserSession() => _instance;
  UserSession._internal();

  UserAccount? _currentUser;
  List<UserAccount> _allAccounts = [];
  bool _initialized = false;
  String? _authToken;
  String _lastLoginError = '';

  UserAccount? get currentUser => _currentUser;
  List<UserAccount> get allAccounts => _allAccounts;
  bool get isLoggedIn => _currentUser != null;
  String get displayName => _currentUser?.realName ?? '未登录';
  String get displayRole => _currentUser?.role ?? '';
  String? get authToken => _authToken;
  String get lastLoginError => _lastLoginError;

  /// 初始化，加载账户数据
  Future<void> initialize() async {
    if (_initialized) return;
    
    // 从本地存储加载账户映射
    await _loadAccountMappings();
    
    // 从assets加载用户角色信息
    await _loadUsersFromAssets();
    
    _initialized = true;
  }

  /// 从本地存储加载账户映射
  Future<void> _loadAccountMappings() async {
    try {
      final localPath = await DataService.getLocalDataPath();
      final file = File('$localPath/account_mappings.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = json.decode(content);
        _allAccounts = jsonList.map((e) => UserAccount.fromJson(e)).toList();
      }
    } catch (e) {
      // 忽略错误
    }
  }

  /// 从assets加载用户角色信息
  Future<void> _loadUsersFromAssets() async {
    final users = await DataService.loadUsers();
    
    for (final user in users) {
      // 检查是否已有此用户的账户映射
      final existingIndex = _allAccounts.indexWhere((a) => a.realName == user.name);
      if (existingIndex < 0) {
        // 创建新的账户映射，默认用户名为空
        _allAccounts.add(UserAccount(
          realName: user.name,
          username: '', // 默认无用户名
          role: user.role,
          permissions: user.permissions,
          avatarPath: user.avatarPath,
        ));
      } else {
        // 更新角色和权限信息
        _allAccounts[existingIndex].role = user.role;
        _allAccounts[existingIndex].permissions = user.permissions;
        _allAccounts[existingIndex].avatarPath = user.avatarPath;
      }
    }
    
    await _saveAccountMappings();
  }

  /// 保存账户映射到本地
  Future<void> _saveAccountMappings() async {
    try {
      final localPath = await DataService.getLocalDataPath();
      final file = File('$localPath/account_mappings.json');
      final jsonList = _allAccounts.map((e) => e.toJson()).toList();
      await file.writeAsString(json.encode(jsonList));
    } catch (e) {
      // 忽略错误
    }
  }

  /// 登录 - 由 PC 本地后端校验（数据库为唯一权威来源）。
  /// 用户名或密码缺失/错误时一律返回 false，界面必须拦截，不再放行“访客”。
  Future<bool> login(String username, String password) async {
    _lastLoginError = '';
    if (username.trim().isEmpty || password.isEmpty) {
      _lastLoginError = '请输入用户名和密码';
      return false;
    }

    try {
      final result = await ApiClient.login(username.trim(), password);
      final user = result['user'] as Map<String, dynamic>? ?? {};
      _authToken = result['token']?.toString();
      _currentUser = UserAccount(
        realName: user['real_name']?.toString().isNotEmpty == true
            ? user['real_name'].toString()
            : user['username']?.toString() ?? username,
        username: user['username']?.toString() ?? username,
        role: user['role']?.toString() ?? '普通用户',
        permissions: const [],
      );
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _lastLoginError = e.message;
      return false;
    } catch (e) {
      _lastLoginError = '登录失败：$e';
      return false;
    }
  }

  /// 登出
  void logout() {
    _currentUser = null;
    _authToken = null;
    notifyListeners();
  }

  /// 绑定用户名到真实人名
  Future<void> bindUsername(String realName, String username) async {
    final index = _allAccounts.indexWhere((a) => a.realName == realName);
    if (index >= 0) {
      _allAccounts[index].username = username;
      await _saveAccountMappings();
      notifyListeners();
    }
  }

  /// 添加新用户
  Future<void> addUser(UserAccount account) async {
    final existingIndex = _allAccounts.indexWhere((a) => a.realName == account.realName);
    if (existingIndex >= 0) {
      _allAccounts[existingIndex] = account;
    } else {
      _allAccounts.add(account);
    }
    await _saveAccountMappings();
    notifyListeners();
  }

  /// 更新用户信息
  Future<void> updateUser(String realName, {String? role, List<String>? permissions}) async {
    final index = _allAccounts.indexWhere((a) => a.realName == realName);
    if (index >= 0) {
      if (role != null) _allAccounts[index].role = role;
      if (permissions != null) _allAccounts[index].permissions = permissions;
      await _saveAccountMappings();
      
      // 同步更新到assets文件
      await _syncUserToAssets(_allAccounts[index]);
      
      notifyListeners();
    }
  }

  /// 同步用户信息到assets文件
  Future<void> _syncUserToAssets(UserAccount account) async {
    try {
      // 写入info.txt文件
      final localPath = await DataService.getLocalDataPath();
      final userDir = Directory('$localPath/users/${account.realName}');
      if (!await userDir.exists()) {
        await userDir.create(recursive: true);
      }
      
      final infoFile = File('${userDir.path}/info.txt');
      final content = '${account.role}\n${account.permissions.join(',')}';
      await infoFile.writeAsString(content);
    } catch (e) {
      // 忽略错误
    }
  }

  /// 刷新用户列表
  Future<void> refresh() async {
    _initialized = false;
    await initialize();
    notifyListeners();
  }
}
