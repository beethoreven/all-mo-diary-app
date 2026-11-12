import 'dart:convert';
import 'dart:io';

import 'package:allmodiary/data/database.dart';
import 'package:allmodiary/data/store.dart';
import 'package:allmodiary/services/api_client.dart';
import 'package:allmodiary/services/auth_service.dart';
import 'package:allmodiary/services/daily_check.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemoryStorage implements AuthStorage {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async => value == null ? values.remove(key) : values[key] = value;
}

/// Every check uses one of the day's checks; the app says how many are left, so repeated
/// 「已是最新」 answers are visibly new and the last ones aren't spent unawares.
void main() {
  late Store store;
  late Directory images;
  late int left;

  setUp(() {
    images = Directory.systemTemp.createTempSync('amd_check_');
    store = Store(AppDb(NativeDatabase.memory()), imagesDir: images);
    left = 3;
  });

  tearDown(() async {
    await store.db.close();
    images.deleteSync(recursive: true);
  });

  Future<DailyCheckService> service() async {
    final storage = _MemoryStorage()
      ..values['auth_user'] = jsonEncode({'sub': 'u1', 'email': 'me@example.com', 'name': '小明', 'photo': null})
      ..values['auth_app_token'] = 'amd1.a.b'
      ..values['auth_app_token_exp'] =
          '${DateTime.now().toUtc().add(const Duration(days: 100)).millisecondsSinceEpoch ~/ 1000}';
    final auth = AuthService(storage);
    await auth.init();
    // Like the server: each check takes one; with none left it answers 429.
    final api = ApiClient(
      baseUrl: 'https://backend.test/all-mo-diary',
      client: MockClient((req) async {
        if (left == 0) {
          return http.Response.bytes(utf8.encode(jsonEncode({'code': 'daily_limit', 'error': '今天的檢查次數已經用完，明天會自動恢復'})), 429);
        }
        left--;
        return http.Response(
            jsonEncode({
              'min_app_version': '0.1.0',
              'force_update': false,
              'force_reason': '',
              'update_url': '',
              'announcement': '',
              'checks_left': left,
              'fonts': {'status': 'none'},
            }),
            200);
      }),
    )..auth = auth;
    return DailyCheckService(store: store, auth: auth, api: api, appVersion: () => '1.0.0');
  }

  test('each check says how many checks are left today', () async {
    final check = await service();
    expect(await check.run(), '已是最新（今天還可以檢查 2 次）');
    expect(await check.checksLeftToday(), 2);
    expect(await check.run(), '已是最新（今天還可以檢查 1 次）');
    expect(await check.run(), '已是最新（今天還可以檢查 0 次）');
    expect(await check.run(), '今天的檢查次數已經用完，明天會自動恢復');
    expect(await check.checksLeftToday(), 0);
  });

  test("yesterday's count says nothing today", () async {
    final check = await service();
    await check.run();
    await store.setSetting(CheckKeys.checksLeftDay, '2000-01-01');
    expect(await check.checksLeftToday(), isNull);
  });
}
