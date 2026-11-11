import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;

import '../core/env.dart';
import '../core/log.dart';
import 'auth_service.dart';

class ApiError implements Exception {
  const ApiError(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  bool get isNetwork => status == 0;

  bool get isDailyLimit => status == 429;

  bool get isNotReady => status == 503;

  @override
  String toString() => message;
}

/// Calls to the diary backend (router-backend, mounted at /diary). Every call except
/// createSession carries the app pass (AuthService.backendToken).
class ApiClient {
  /// [baseUrl] is for tests only; the app always uses Env.apiBase.
  ApiClient({http.Client? client, String? baseUrl})
      : _http = client ?? http.Client(),
        _base = baseUrl ?? Env.apiBase;

  final http.Client _http;
  final String _base;

  /// Set after construction (AuthService needs createSession, ApiClient needs the pass).
  AuthService? auth;

  bool get configured => _base.isNotEmpty;
  static const _timeout = Duration(seconds: 30);

  /// Called once at sign-in: trade the Google ID token for the app pass.
  Future<({String token, int expiresAt})> createSession(String idToken) async {
    if (!configured) throw const ApiError(0, 'not_configured', '這個版本還沒設定後端網址');
    http.Response resp;
    try {
      resp = await _http
          .post(Uri.parse('$_base/api/v1/session'), headers: {'Authorization': 'Bearer $idToken'})
          .timeout(_timeout);
    } catch (e) {
      AppLog.warn('api.network_error', {'path': '/api/v1/session', 'type': e.runtimeType.toString()});
      throw const ApiError(0, 'network', '無法連線到伺服器，請確認網路後再試');
    }
    Map<String, dynamic> json;
    try {
      json = (jsonDecode(utf8.decode(resp.bodyBytes)) as Map).cast<String, dynamic>();
    } catch (_) {
      json = {};
    }
    AppLog.info('api.response', {'path': '/api/v1/session', 'status': resp.statusCode, 'code': json['code'] as String?});
    final token = json['token'];
    final exp = json['expires_at'];
    if (resp.statusCode != 200 || token is! String || exp is! int) {
      throw ApiError(resp.statusCode, (json['code'] as String?) ?? 'http_${resp.statusCode}',
          (json['error'] as String?) ?? '伺服器回應錯誤（${resp.statusCode}）');
    }
    return (token: token, expiresAt: exp);
  }

  Future<Map<String, dynamic>> _post(String path, Object body, {bool retried = false}) async {
    if (!configured) throw const ApiError(0, 'not_configured', '這個版本還沒設定後端網址');
    final a = auth;
    if (a == null) throw const NotSignedIn();
    final token = await a.backendToken();
    http.Response resp;
    try {
      resp = await _http
          .post(Uri.parse('$_base$path'),
              headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
              body: utf8.encode(jsonEncode(body)))
          .timeout(_timeout);
    } catch (e) {
      AppLog.warn('api.network_error', {'path': path, 'type': e.runtimeType.toString()});
      throw const ApiError(0, 'network', '無法連線到伺服器，請確認網路後再試');
    }
    if (resp.statusCode == 401 && !retried) {
      // The pass was refused: drop it and try once more (exchanged again if this launch's Google ID
      // token is still fresh; otherwise backendToken throws NotSignedIn and the user signs in again).
      await a.invalidateBackendToken();
      return _post(path, body, retried: true);
    }
    Map<String, dynamic> json;
    try {
      json = (jsonDecode(utf8.decode(resp.bodyBytes)) as Map).cast<String, dynamic>();
    } catch (_) {
      json = {};
    }
    AppLog.info('api.response', {'path': path, 'status': resp.statusCode, 'code': json['code'] as String?});
    if (resp.statusCode >= 400) {
      throw ApiError(resp.statusCode, (json['code'] as String?) ?? 'http_${resp.statusCode}',
          (json['error'] as String?) ?? '伺服器回應錯誤（${resp.statusCode}）');
    }
    return json;
  }

  /// Daily check: minimum version, announcement, font list.
  Future<Map<String, dynamic>> check({required String appVersion, String? fontsVersion}) => _post(
      '/api/v1/check', {'app_version': appVersion, 'platform': Platform.isIOS ? 'ios' : 'android', 'fonts_version': fontsVersion});

  Future<Map<String, dynamic>> feedback(Map<String, Object?> body) => _post('/api/v1/feedback', body);
}
