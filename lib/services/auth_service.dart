import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import '../core/env.dart';
import '../core/log.dart';
import '../core/time.dart';

/// Drive scopes, asked for only when a cloud feature needs them (as the privacy policy promises).
abstract final class DriveScopes {
  /// Only this app's own hidden area: diary sync, the export key.
  static const appData = 'https://www.googleapis.com/auth/drive.appdata';

  /// Only files this app created or the user picked: exports, images in the cloud.
  static const file = 'https://www.googleapis.com/auth/drive.file';

  static const all = [appData, file];
}

class SignedInUser {
  const SignedInUser({required this.sub, required this.email, this.name, this.photoUrl});

  final String sub;
  final String email;
  final String? name;
  final String? photoUrl;
}

class NotSignedIn implements Exception {
  const NotSignedIn();

  @override
  String toString() => '請先用 Google 帳號登入';
}

class DriveNotAuthorized implements Exception {
  const DriveNotAuthorized();

  @override
  String toString() => '需要雲端硬碟的權限';
}

/// 登入狀態。
///
/// - signedOut:沒有記住任何帳號。
/// - signedIn:記住了帳號,而且能拿到後端的通行證(手上的還有效,或這次登入的 ID Token 還能換一張)。
/// - sessionExpired:記住了帳號(雲端硬碟照常能用),但通行證已經失效、也沒有能換新的 ID Token,
///   要使用者重新按一次登入,後端的功能(每日檢查、意見回饋)才能用。
///   例如很久沒開 App 讓通行證過期,或後端拒絕了這張通行證。
enum AuthState { signedOut, signedIn, sessionExpired }

/// Trades a Google ID token for the app pass (ApiClient.createSession → POST /diary/api/v1/session).
typedef SessionExchange = Future<({String token, int expiresAt})> Function(String idToken);

/// Where the sign-in is remembered (the app uses Store's settings table; tests use memory).
abstract class AuthStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

/// Google 登入。登入要撐過「關掉 App 再打開」，只有按「登出」才登出。
///
/// - **登入一次就記住**:使用者按「登入」後,記住是哪個帳號,並用 Google 的 ID Token 跟後端換一張
///   App 的通行證(router-backend apps/all_mo_diary/auth.py)存在手機上。之後開 App 直接是登入狀態,
///   後端請求都帶通行證;只有按「登出」才登出。
///   ★ 不在開 App 時請系統「自動登入」:系統常常不肯(原因不公開),這時 Google 的登入外掛會自己
///     改跳選帳號畫面,使用者按掉就變成沒登入;每次重開 App 都可能這樣。
/// - 登入時只要求基本資料(Email、名稱、頭像);雲端硬碟權限在開啟雲端功能或第一次匯出、
///   匯入時才要求,用 Google 的授權 API 拿,不需要先「自動登入」。
/// - Android 上用系統的帳號選擇畫面(Credential Manager),不開瀏覽器(google_sign_in 7)。
class AuthService extends ChangeNotifier {
  AuthService(this._storage, {GoogleSignIn? signIn}) : _signIn = signIn ?? GoogleSignIn.instance;

  final AuthStorage _storage;
  final GoogleSignIn _signIn;

  /// 換通行證的方法,建立服務時接上(ApiClient 也要用 AuthService,所以不能在建構時給)。
  /// 沒有設定後端的版本是 null,這時不會有「登入已過期」。
  SessionExchange? exchange;

  SignedInUser? _user;
  String? _appToken;
  DateTime? _appTokenExpiry;

  /// 這次開 App 之後按登入拿到的 Google ID Token(約一小時過期);只用來換通行證。
  String? _idToken;
  DateTime? _idTokenExpiry;
  bool _initialized = false;

  static const _keyUser = 'auth_user';
  static const _keyToken = 'auth_app_token';
  static const _keyTokenExpiry = 'auth_app_token_exp';

  SignedInUser? get user => _user;

  /// 記住了帳號(雲端硬碟用這個判斷)。後端的功能要看 [state]。
  bool get signedIn => _user != null;

  AuthState get state {
    if (_user == null) return AuthState.signedOut;
    if (exchange == null || _validAppToken != null || _usableIdToken != null) return AuthState.signedIn;
    return AuthState.sessionExpired;
  }

  /// 手上還沒過期的通行證。
  String? get _validAppToken {
    final token = _appToken, expiry = _appTokenExpiry;
    return token != null && expiry != null && expiry.isAfter(TimeRules.now().toUtc()) ? token : null;
  }

  /// 這次開 App 按登入拿到、還沒過期的 Google ID Token。
  String? get _usableIdToken {
    final token = _idToken, expiry = _idTokenExpiry;
    return token != null && (expiry == null || expiry.isAfter(TimeRules.now().toUtc())) ? token : null;
  }

  /// 開 App 時呼叫:讀回記住的帳號與通行證,並準備好 Google 登入(不跳任何畫面)。
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final raw = await _storage.read(_keyUser);
      if (raw != null) {
        final m = (jsonDecode(raw) as Map).cast<String, Object?>();
        final user = SignedInUser(
            sub: m['sub']! as String,
            email: m['email']! as String,
            name: m['name'] as String?,
            photoUrl: m['photo'] as String?);
        // 通行證先讀回來再通知畫面:先通知的話,畫面會在讀到通行證前算出「登入已過期」。
        _appToken = await _storage.read(_keyToken);
        final exp = int.tryParse(await _storage.read(_keyTokenExpiry) ?? '');
        _appTokenExpiry = exp == null ? null : DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
        _setUser(user);
      }
      AppLog.info(_user != null ? 'auth.restored' : 'auth.restore_none', {'token': _appToken != null, 'state': state.name});
    } catch (e, st) {
      AppLog.error('auth.restore_failed', e, st);
    }
    if (!Env.googleConfigured) return;
    try {
      await _signIn.initialize(serverClientId: Env.webClientId);
    } catch (e, st) {
      AppLog.error('auth.init_failed', e, st);
    }
  }

  void _setUser(SignedInUser? user) {
    _user = user;
    // The account's display name (usually a real name) is masked in diagnostic logs.
    AppLog.accountName = user?.name;
    notifyListeners();
  }

  static DateTime? _expiryOf(String jwt) {
    try {
      final body = jwt.split('.')[1];
      final json = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(body)))) as Map;
      return DateTime.fromMillisecondsSinceEpoch((json['exp'] as int) * 1000, isUtc: true);
    } catch (_) {
      return null;
    }
  }

  /// 使用者按下登入:選帳號 → 記住帳號 → 換通行證(連不上後端也算登入成功,之後要用時再換)。
  Future<SignedInUser> signIn() async {
    if (!Env.googleConfigured) throw StateError('這個版本還沒設定 Google 登入');
    await init();
    final account = await _signIn.authenticate();
    final user = SignedInUser(sub: account.id, email: account.email, name: account.displayName, photoUrl: account.photoUrl);
    await _storage.write(
        _keyUser, jsonEncode({'sub': user.sub, 'email': user.email, 'name': user.name, 'photo': user.photoUrl}));
    if (_user?.sub != user.sub) await _saveAppToken(null, null);
    _idToken = account.authentication.idToken;
    _idTokenExpiry = _idToken == null ? null : _expiryOf(_idToken!);
    _setUser(user);
    AppLog.info('auth.signed_in');
    try {
      await _exchange();
    } catch (e) {
      AppLog.warn('auth.exchange_failed', {'type': e.runtimeType.toString()});
    }
    return user;
  }

  Future<void> signOut() async {
    try {
      if (Env.googleConfigured) await _signIn.signOut();
    } catch (e) {
      AppLog.warn('auth.signout_failed', {'type': e.runtimeType.toString()});
    } finally {
      await _storage.write(_keyUser, null);
      await _saveAppToken(null, null);
      _idToken = null;
      _idTokenExpiry = null;
      _setUser(null);
      AppLog.info('auth.signed_out');
    }
  }

  Future<void> _saveAppToken(String? token, int? expiresAt) async {
    _appToken = token;
    _appTokenExpiry = expiresAt == null ? null : DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000, isUtc: true);
    await _storage.write(_keyToken, token);
    await _storage.write(_keyTokenExpiry, expiresAt?.toString());
  }

  /// 測試用:模擬「這次開 App 有按登入、手上有一張 ID Token」(真的登入要經過 Google 的畫面)。
  @visibleForTesting
  void debugSetIdToken(String idToken, DateTime expiry) {
    _idToken = idToken;
    _idTokenExpiry = expiry;
  }

  /// 用這次登入拿到的 ID Token 換通行證。ID Token 已經過期就沒辦法換,要使用者重新登入。
  Future<String> _exchange() async {
    final idToken = _usableIdToken;
    final fn = exchange;
    if (idToken == null || fn == null) throw const NotSignedIn();
    final result = await fn(idToken);
    await _saveAppToken(result.token, result.expiresAt);
    AppLog.info('auth.session_created');
    return result.token;
  }

  /// 給後端的通行證。手上沒有(或快過期)就用這次登入的 ID Token 換一張;快過期但換不到時先用手上的。
  /// 完全拿不到就丟 NotSignedIn(這時 [state] 是 sessionExpired),呼叫端請使用者重新登入。
  /// **不會**自己跳任何畫面。
  Future<String> backendToken() async {
    if (_user == null) throw const NotSignedIn();
    final current = _validAppToken;
    final expiry = _appTokenExpiry;
    if (current != null && expiry!.isAfter(TimeRules.now().toUtc().add(const Duration(days: 1)))) return current;
    if (_usableIdToken == null) {
      if (current != null) return current;
      AppLog.warn('auth.session_expired');
      notifyListeners();
      throw const NotSignedIn();
    }
    try {
      return await _exchange();
    } catch (_) {
      // 換新的失敗(例如連不上後端),手上的還沒過期就先用。
      if (current != null) return current;
      rethrow;
    }
  }

  /// 後端在每日檢查的回應裡附了一張新的通行證(舊的發出超過 30 天):換上新的。
  Future<void> renewBackendToken(String token, int expiresAt) async {
    if (_user == null) return;
    await _saveAppToken(token, expiresAt);
    AppLog.info('auth.session_renewed');
  }

  /// 後端回 401(通行證無效或過期):丟掉,下次 backendToken() 會試著重換,換不到就要重新登入。
  Future<void> invalidateBackendToken() async {
    await _saveAppToken(null, null);
    notifyListeners();
  }

  AuthorizationRequestDetails _driveRequest(bool prompt) => AuthorizationRequestDetails(
      scopes: DriveScopes.all, userId: _user?.sub, email: _user?.email, promptIfUnauthorized: prompt);

  /// 雲端硬碟的存取權杖。interactive = true 時,沒有權限會跳出 Google 的授權畫面
  /// (只能在使用者按下按鈕時用);false 時沒有權限就丟 DriveNotAuthorized。
  /// 用記住的帳號(編號與 Email)指定要哪個帳號的授權,不需要先「自動登入」。
  Future<String> driveAccessToken({required bool interactive}) async {
    if (_user == null) throw const NotSignedIn();
    await init();
    final platform = GoogleSignInPlatform.instance;
    var tokens = await platform.clientAuthorizationTokensForScopes(
        ClientAuthorizationTokensForScopesParameters(request: _driveRequest(false)));
    if (tokens == null) {
      if (!interactive) throw const DriveNotAuthorized();
      tokens = await platform.clientAuthorizationTokensForScopes(
          ClientAuthorizationTokensForScopesParameters(request: _driveRequest(true)));
      if (tokens == null) throw const DriveNotAuthorized();
      AppLog.info('auth.drive_authorized');
    }
    return tokens.accessToken;
  }

  /// 雲端硬碟回 401 時呼叫:這張存取權杖已經失效,讓系統下次給新的。
  Future<void> dropDriveToken(String accessToken) async {
    await GoogleSignInPlatform.instance.clearAuthorizationToken(ClearAuthorizationTokenParams(accessToken: accessToken));
  }
}
