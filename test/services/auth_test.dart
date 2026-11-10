import 'dart:convert';
import 'dart:io';

import 'package:allmodiary/data/database.dart';
import 'package:allmodiary/data/store.dart';
import 'package:allmodiary/state/providers.dart';
import 'package:drift/native.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:allmodiary/services/auth_service.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _MemoryStorage implements AuthStorage {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async => value == null ? values.remove(key) : values[key] = value;
}

class _FakePlatform extends GoogleSignInPlatform with MockPlatformInterfaceMixin {
  final requests = <AuthorizationRequestDetails>[];
  bool granted = true;
  int lightweightCalls = 0;

  @override
  Future<void> init(InitParameters params) async {}

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(AttemptLightweightAuthenticationParameters params) {
    lightweightCalls++;
    return Future.value(null);
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) => throw UnimplementedError();

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async {
    requests.add(params.request);
    return granted || params.request.promptIfUnauthorized
        ? const ClientAuthorizationTokenData(accessToken: 'drive-at')
        : null;
  }

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async => null;

  @override
  Future<void> clearAuthorizationToken(ClearAuthorizationTokenParams params) async {}

  @override
  Future<void> signOut(SignOutParams params) async {}

  @override
  Future<void> disconnect(DisconnectParams params) async {}
}

/// 登入一次就記住:開 App 不請系統「自動登入」(那會在系統不肯時跳出選帳號畫面)。
/// 沿用 mama-fufood 的 test/services/auth_test.dart(同一套 AuthService)。
void main() {
  late _MemoryStorage storage;
  late _FakePlatform platform;

  setUp(() {
    storage = _MemoryStorage();
    platform = _FakePlatform();
    GoogleSignInPlatform.instance = platform;
  });

  Future<AuthService> restored({String? token, DateTime? expiry}) async {
    storage.values['auth_user'] = jsonEncode({'sub': 'u1', 'email': 'me@example.com', 'name': '小明', 'photo': null});
    if (token != null) {
      storage.values['auth_app_token'] = token;
      storage.values['auth_app_token_exp'] = '${expiry!.millisecondsSinceEpoch ~/ 1000}';
    }
    final auth = AuthService(storage);
    await auth.init();
    return auth;
  }

  test('重開 App:記住的帳號直接是登入狀態，不會請系統自動登入', () async {
    final auth = await restored(token: 'amd1.a.b', expiry: DateTime.now().toUtc().add(const Duration(days: 100)));
    expect(auth.signedIn, isTrue);
    expect(auth.user!.email, 'me@example.com');
    expect(platform.lightweightCalls, 0);
    expect(await auth.backendToken(), 'amd1.a.b');
  });

  test('沒登入過:不是登入狀態，後端請求要先登入', () async {
    final auth = AuthService(storage);
    await auth.init();
    expect(auth.signedIn, isFalse);
    expect(auth.backendToken, throwsA(isA<NotSignedIn>()));
  });

  test('通行證快過期或被後端拒絕:用這次登入的 ID Token 換一張；換不到就請使用者重新登入', () async {
    final auth = await restored(token: 'amd1.old', expiry: DateTime.now().toUtc().add(const Duration(hours: 2)));
    var exchanged = 0;
    auth.exchange = (idToken) async {
      exchanged++;
      return (
        token: 'amd1.new',
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 180)).millisecondsSinceEpoch ~/ 1000,
      );
    };
    // 這次開 App 沒按登入,手上沒有 ID Token:換不到新的,先用手上還沒過期的那張。
    expect(await auth.backendToken(), 'amd1.old');
    expect(exchanged, 0);
    auth.debugSetIdToken('google-id', DateTime.now().toUtc().add(const Duration(minutes: 30)));
    expect(await auth.backendToken(), 'amd1.new');
    expect(exchanged, 1);
    expect(storage.values['auth_app_token'], 'amd1.new', reason: '換到的通行證要存起來,下次開 App 還在');

    await auth.invalidateBackendToken();
    expect(storage.values.containsKey('auth_app_token'), isFalse);
  });

  SessionExchange neverCalled() =>
      (_) async => fail('不該換通行證');

  group('登入已過期(記住了帳號,但通行證拿不到)', () {
    test('重開 App 時通行證已過期、手上沒有 ID Token:是「登入已過期」，不是未登入，也不請系統自動登入', () async {
      storage.values['auth_user'] = jsonEncode({'sub': 'u1', 'email': 'me@example.com', 'name': null, 'photo': null});
      storage.values['auth_app_token'] = 'amd1.old';
      storage.values['auth_app_token_exp'] =
          '${DateTime.now().toUtc().subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000}';
      final auth = AuthService(storage)..exchange = neverCalled();
      final seen = <AuthState>[];
      auth.addListener(() => seen.add(auth.state));
      await auth.init();
      expect(auth.state, AuthState.sessionExpired);
      expect(seen, [AuthState.sessionExpired], reason: '通知畫面時通行證要已經讀回來,不能先通知一個不對的狀態');
      expect(auth.signedIn, isTrue, reason: '帳號還記得,雲端硬碟照常能用');
      expect(platform.lightweightCalls, 0);
      await expectLater(auth.backendToken(), throwsA(isA<NotSignedIn>()));
      expect(await auth.driveAccessToken(interactive: false), 'drive-at');
    });

    test('重開 App 時通行證還有效:直接是登入狀態，畫面只收到一次正確的通知', () async {
      storage.values['auth_user'] = jsonEncode({'sub': 'u1', 'email': 'me@example.com', 'name': null, 'photo': null});
      storage.values['auth_app_token'] = 'amd1.ok';
      storage.values['auth_app_token_exp'] =
          '${DateTime.now().toUtc().add(const Duration(days: 100)).millisecondsSinceEpoch ~/ 1000}';
      final auth = AuthService(storage)..exchange = neverCalled();
      final seen = <AuthState>[];
      auth.addListener(() => seen.add(auth.state));
      await auth.init();
      expect(seen, [AuthState.signedIn]);
    });

    test('後端拒絕通行證(401):通知畫面變成「登入已過期」；重新登入拿到 ID Token 後恢復', () async {
      final auth = await restored(token: 'amd1.a.b', expiry: DateTime.now().toUtc().add(const Duration(days: 100)));
      auth.exchange = (_) async => (
        token: 'amd1.new',
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 180)).millisecondsSinceEpoch ~/ 1000,
      );
      expect(auth.state, AuthState.signedIn);
      var notified = 0;
      auth.addListener(() => notified++);
      await auth.invalidateBackendToken();
      expect(auth.state, AuthState.sessionExpired);
      expect(notified, 1);

      auth.debugSetIdToken('google-id', DateTime.now().toUtc().add(const Duration(minutes: 30)));
      expect(auth.state, AuthState.signedIn);
      expect(await auth.backendToken(), 'amd1.new');
    });

    test('backendToken 發現拿不到通行證時通知畫面', () async {
      final auth = await restored();
      auth.exchange = neverCalled();
      var notified = 0;
      auth.addListener(() => notified++);
      await expectLater(auth.backendToken(), throwsA(isA<NotSignedIn>()));
      expect(notified, 1);
    });

    test('沒有設定後端的版本:沒有通行證也算登入，不會顯示登入已過期', () async {
      final auth = await restored();
      expect(auth.exchange, isNull);
      expect(auth.state, AuthState.signedIn);
    });

    test('換新通行證失敗(連不上後端)時，手上還沒過期的先繼續用', () async {
      final auth = await restored(token: 'amd1.old', expiry: DateTime.now().toUtc().add(const Duration(hours: 2)));
      auth.exchange = (_) async => throw Exception('offline');
      auth.debugSetIdToken('google-id', DateTime.now().toUtc().add(const Duration(minutes: 30)));
      expect(await auth.backendToken(), 'amd1.old');
    });

    test('登出後是未登入', () async {
      final auth = await restored();
      auth.exchange = neverCalled();
      expect(auth.state, AuthState.sessionExpired);
      await auth.signOut();
      expect(auth.state, AuthState.signedOut);
    });
  });

  test('每日檢查附的新通行證會換上', () async {
    final auth = await restored(token: 'amd1.old', expiry: DateTime.now().toUtc().add(const Duration(days: 100)));
    await auth.renewBackendToken(
      'amd1.renewed',
      DateTime.now().toUtc().add(const Duration(days: 180)).millisecondsSinceEpoch ~/ 1000,
    );
    expect(await auth.backendToken(), 'amd1.renewed');
  });

  test('登出:帳號與通行證都清掉', () async {
    final auth = await restored(token: 'amd1.a.b', expiry: DateTime.now().toUtc().add(const Duration(days: 100)));
    await auth.signOut();
    expect(auth.signedIn, isFalse);
    expect(storage.values, isEmpty);
  });

  test('雲端硬碟授權:指定記住的帳號，不跳畫面；沒有授權時只有使用者按按鈕才跳', () async {
    final auth = await restored();
    expect(await auth.driveAccessToken(interactive: false), 'drive-at');
    expect(platform.requests.single.userId, 'u1');
    expect(platform.requests.single.email, 'me@example.com');
    expect(platform.requests.single.promptIfUnauthorized, isFalse);

    platform.granted = false;
    expect(() => auth.driveAccessToken(interactive: false), throwsA(isA<DriveNotAuthorized>()));
    expect(await auth.driveAccessToken(interactive: true), 'drive-at');
    expect(platform.requests.last.promptIfUnauthorized, isTrue);
    expect(platform.lightweightCalls, 0);
  });

  test('重開測試（App 真正用的儲存：資料庫的設定表）：新的 AuthService 直接是登入狀態，不呼叫自動登入', () async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final store = Store(db, imagesDir: Directory.systemTemp);
    final storeStorage = StoreAuthStorage(store);
    await storeStorage.write(
      'auth_user',
      jsonEncode({'sub': 'u1', 'email': 'me@example.com', 'name': null, 'photo': null}),
    );
    await storeStorage.write('auth_app_token', 'amd1.x.y');
    await storeStorage.write(
      'auth_app_token_exp',
      '${DateTime.now().toUtc().add(const Duration(days: 100)).millisecondsSinceEpoch ~/ 1000}',
    );
    // "Restart": a brand-new service over the same database.
    final auth = AuthService(storeStorage)..exchange = (_) async => fail('不該換通行證');
    await auth.init();
    expect(auth.state, AuthState.signedIn);
    expect(await auth.backendToken(), 'amd1.x.y');
    expect(platform.lightweightCalls, 0);
    await auth.signOut();
    expect(await store.getSetting('auth_user'), isNull);
    expect(await store.getSetting('auth_app_token'), isNull);
  });
}
