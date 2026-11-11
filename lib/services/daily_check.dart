import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/log.dart';
import '../core/time.dart';
import '../data/store.dart';
import '../domain/font_catalog.dart';
import 'api_client.dart';
import 'auth_service.dart';

abstract final class CheckKeys {
  static const lastOkDay = 'check_last_ok_day';
  static const lastAt = 'check_last_at';
  static const failDay = 'check_fail_day';
  static const failCount = 'check_fail_count';
  static const failAt = 'check_fail_at';
  static const checksLeft = 'check_left';
  static const forceMin = 'force_min_version';
  static const forceReason = 'force_reason';
  static const forceUrl = 'force_url';
  static const announcement = 'announcement';
  static const announcementSeen = 'announcement_seen';

  /// The font list as received: {"version": ..., "content": {"fonts": [...]}}.
  static const fonts = 'fonts_release';
}

class ForceUpdate {
  const ForceUpdate({required this.minVersion, required this.reason, required this.url});

  final String minVersion;
  final String reason;
  final String url;
}

/// The daily check: once signed in, on opening the app it checks
/// once a Taiwan day for the minimum app version, an announcement and the font list. Failures retry
/// at least 2 hours apart, at most 5 times a day. App 設定 can also check by hand (sharing the server's
/// 10 a day).
class DailyCheckService extends ChangeNotifier {
  DailyCheckService({required this.store, required this.auth, required this.api, required this.appVersion});

  final Store store;
  final AuthService auth;
  final ApiClient api;
  final String Function() appVersion;
  bool _running = false;

  static int compareVersions(String a, String b) {
    List<int> parts(String v) => v.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }

  /// This version is older than the minimum set in the admin console → forced update (with the reason).
  Future<ForceUpdate?> forceUpdate() async {
    final min = await store.getSetting(CheckKeys.forceMin);
    if (min == null || compareVersions(appVersion(), min) >= 0) return null;
    return ForceUpdate(
      minVersion: min,
      reason: await store.getSetting(CheckKeys.forceReason) ?? '',
      url: await store.getSetting(CheckKeys.forceUrl) ?? '',
    );
  }

  Future<FontCatalog> fontCatalog() async => FontCatalog.decode(await store.getSetting(CheckKeys.fonts));

  /// On opening the app or returning to it.
  Future<void> maybeRun() async {
    // With an expired pass the check would only fail and burn retries; it resumes after signing in.
    if (!api.configured || auth.state != AuthState.signedIn) return;
    final today = '${TimeRules.today()}';
    // While blocked by a forced update, check on every launch: the minimum may have been lowered.
    final forced = await forceUpdate() != null;
    if (!forced && await store.getSetting(CheckKeys.lastOkDay) == today) return;
    if (await store.getSetting(CheckKeys.failDay) == today) {
      final count = int.tryParse(await store.getSetting(CheckKeys.failCount) ?? '') ?? 0;
      final at = int.tryParse(await store.getSetting(CheckKeys.failAt) ?? '') ?? 0;
      if (count >= Timing.dailyCheckRetriesPerDay) return;
      if (DateTime.now().millisecondsSinceEpoch - at < Timing.dailyCheckRetryGap.inMilliseconds) return;
    }
    try {
      await run();
    } catch (_) {
      // The failure is recorded; tried again on a later launch.
    }
  }

  /// One check (also the manual one). Returns a message for the user.
  Future<String> run() async {
    if (_running) return '正在檢查中';
    _running = true;
    final today = '${TimeRules.today()}';
    try {
      final current = await fontCatalog();
      final res = await api.check(appVersion: appVersion(), fontsVersion: current.version);
      var fontsUpdated = false;
      final fonts = res['fonts'];
      if (fonts is Map && fonts['status'] == 'updated' && fonts['content'] is Map) {
        await store.setSetting(CheckKeys.fonts, jsonEncode({'version': fonts['version'], 'content': fonts['content']}));
        fontsUpdated = true;
      }
      if (res['force_update'] == true) {
        await store.setSetting(CheckKeys.forceMin, res['min_app_version'] as String?);
        await store.setSetting(CheckKeys.forceReason, res['force_reason'] as String? ?? '');
        await store.setSetting(CheckKeys.forceUrl, res['update_url'] as String? ?? '');
      } else {
        await store.setSetting(CheckKeys.forceMin, null);
      }
      final announcement = (res['announcement'] as String? ?? '').trim();
      await store.setSetting(CheckKeys.announcement, announcement.isEmpty ? null : announcement);
      await store.setSetting(CheckKeys.lastOkDay, today);
      await store.setSetting(CheckKeys.lastAt, '${DateTime.now().millisecondsSinceEpoch}');
      await store.setSetting(CheckKeys.checksLeft, '${res['checks_left'] ?? ''}');
      // A fresh pass when the old one is over 30 days old.
      final renewed = res['session_token'];
      final renewedExp = res['session_expires_at'];
      if (renewed is String && renewedExp is int) await auth.renewBackendToken(renewed, renewedExp);
      AppLog.info('check.ok', {'fonts_updated': fontsUpdated, 'force': res['force_update'] == true});
      notifyListeners();
      return fontsUpdated ? '已更新字體清單' : '已是最新';
    } on ApiError catch (e) {
      AppLog.warn('check.failed', {'status': e.status, 'code': e.code});
      if (e.isDailyLimit) {
        await store.setSetting(CheckKeys.checksLeft, '0');
        await store.setSetting(CheckKeys.failDay, today);
        await store.setSetting(CheckKeys.failCount, '${Timing.dailyCheckRetriesPerDay}');
        notifyListeners();
        return '今天的檢查次數已經用完，明天會自動恢復';
      }
      await _noteFailure(today);
      return e.isNotReady ? '暫時無法檢查，請稍後再試' : e.message;
    } on NotSignedIn {
      return auth.signedIn ? '登入已過期，請重新登入 Google 帳號' : '請先用 Google 帳號登入';
    } catch (e, st) {
      AppLog.error('check.error', e, st);
      await _noteFailure(today);
      return '檢查失敗，請稍後再試';
    } finally {
      _running = false;
    }
  }

  /// The announcement if it hasn't been shown yet; marks it shown.
  Future<String?> takeAnnouncement() async {
    final text = await store.getSetting(CheckKeys.announcement);
    if (text == null || text == await store.getSetting(CheckKeys.announcementSeen)) return null;
    await store.setSetting(CheckKeys.announcementSeen, text);
    return text;
  }

  Future<void> _noteFailure(String today) async {
    final sameDay = await store.getSetting(CheckKeys.failDay) == today;
    final count = sameDay ? (int.tryParse(await store.getSetting(CheckKeys.failCount) ?? '') ?? 0) : 0;
    await store.setSetting(CheckKeys.failDay, today);
    await store.setSetting(CheckKeys.failCount, '${count + 1}');
    await store.setSetting(CheckKeys.failAt, '${DateTime.now().millisecondsSinceEpoch}');
  }
}
