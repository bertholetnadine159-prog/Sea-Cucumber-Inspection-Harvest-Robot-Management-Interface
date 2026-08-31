/// 后端 REST API 客户端（http://127.0.0.1:5000）
/// 登录、管理员、传感器、日志、命令等接口。
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient._();

  static const String baseUrl = 'http://127.0.0.1:5000';

  static Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 5));
          break;
        case 'POST':
          response = await http
              .post(uri, headers: headers, body: json.encode(body ?? {}))
              .timeout(const Duration(seconds: 5));
          break;
        case 'PUT':
          response = await http
              .put(uri, headers: headers, body: json.encode(body ?? {}))
              .timeout(const Duration(seconds: 5));
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers).timeout(const Duration(seconds: 5));
          break;
        default:
          throw ApiException(0, 'unsupported method $method');
      }
    } catch (e) {
      throw ApiException(0, '无法连接本地后端服务：$e');
    }

    Map<String, dynamic> data;
    try {
      data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      data = {};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, data['error']?.toString() ?? '请求失败');
    }
    return data;
  }

  /// 登录：失败抛 ApiException，界面据此拦截。
  static Future<Map<String, dynamic>> login(String username, String password) {
    return _request('POST', '/api/login', body: {'username': username, 'password': password});
  }

  static Future<Map<String, dynamic>> health() => _request('GET', '/api/health');

  static Future<List<dynamic>> listUsers(String token) async {
    final data = await _request('GET', '/api/users', token: token);
    return (data['data'] as List?) ?? [];
  }

  static Future<List<dynamic>> listSensors(String token, {int limit = 200}) async {
    final data = await _request('GET', '/api/sensors?limit=$limit', token: token);
    return (data['data'] as List?) ?? [];
  }

  static Future<List<dynamic>> listLogs(String token, {int limit = 200}) async {
    final data = await _request('GET', '/api/logs?limit=$limit', token: token);
    return (data['data'] as List?) ?? [];
  }

  static Future<Map<String, dynamic>> createUser(
    String token, {
    required String username,
    required String password,
    String role = 'admin',
    String realName = '',
  }) {
    return _request(
      'POST',
      '/api/users',
      token: token,
      body: {'username': username, 'password': password, 'role': role, 'real_name': realName},
    );
  }

  static Future<Map<String, dynamic>> updateUser(
    String token,
    int id, {
    String? role,
    String? realName,
    bool? enabled,
  }) {
    return _request(
      'PUT',
      '/api/users/$id',
      token: token,
      body: {
        if (role != null) 'role': role,
        if (realName != null) 'real_name': realName,
        if (enabled != null) 'enabled': enabled,
      },
    );
  }

  static Future<Map<String, dynamic>> deleteUser(String token, int id) {
    return _request('DELETE', '/api/users/$id', token: token);
  }

  static Future<Map<String, dynamic>> sendCommand(
    String token,
    String command,
    Map<String, dynamic> params,
  ) {
    return _request('POST', '/api/command', token: token, body: {'command': command, 'params': params});
  }
}
