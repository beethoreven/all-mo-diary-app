import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/env.dart';
import '../core/log.dart';

class ApiError implements Exception {
  const ApiError(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  bool get isNetwork => status == 0;

  @override
  String toString() => message;
}

/// Calls to the diary backend (router-backend, mounted at /diary). Same shape as mama-fufood's
/// ApiClient; the daily check and feedback calls (which carry the app pass and retry once on 401)
/// arrive with those features.
class ApiClient {
  /// [baseUrl] is for tests only; the app always uses Env.apiBase.
  ApiClient({http.Client? client, String? baseUrl})
      : _http = client ?? http.Client(),
        _base = baseUrl ?? Env.apiBase;

  final http.Client _http;
  final String _base;

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
}
