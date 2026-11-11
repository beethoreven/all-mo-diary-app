import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:path/path.dart' as p;

import '../core/constants.dart';
import '../core/log.dart';
import '../core/text.dart';
import '../core/time.dart';
import '../data/store.dart';
import '../domain/font_catalog.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'daily_check.dart';
import 'diagnostics.dart';
import 'platform.dart';
import 'sync_engine.dart';

enum FeedbackKind {
  problem('problem', '遇到問題'),
  suggestion('suggestion', '提供建議');

  const FeedbackKind(this.code, this.label);

  final String code;
  final String label;
}

class FeedbackDraft {
  FeedbackDraft({required this.kind, required this.description, required this.body, required this.items});

  final FeedbackKind kind;
  final String description;

  /// 要送出的完整內容(按下送出當下凍結)。
  final Map<String, Object?> body;

  /// 確認畫面列出的項目(類別、主要數值、記錄檔大小)。
  final List<(String, String)> items;

  String get id => body['id'] as String;
}

class FeedbackOutcome {
  const FeedbackOutcome({required this.id, required this.sent});

  final String id;

  /// false:沒網路或伺服器暫時不能用,已放進待送清單。
  final bool sent;
}

/// 意見回饋（照抄 mama-fufood；全心日記規格 §10）。使用者沒有按送出,我們什麼都不收。
///
/// - 「遇到問題」附上手機狀態、雲端狀態、最近 7 天的記錄檔與 logcat 摘錄;
///   「提供建議」只附基本資訊。
/// - 按「送出」後先顯示確認畫面,使用者按「確認送出」才送。
/// - 送出失敗:連同凍結的快照放進待送清單,之後每次開 App 自動重送(每天最多 5 次),
///   最多保留 30 天;每天最多送出 3 則(和伺服器一致)。
class FeedbackService {
  FeedbackService({
    required this.store,
    required this.api,
    required this.auth,
    required this.diagnostics,
    required this.appVersion,
    required this.buildNumber,
    required this.fonts,
  });

  final Store store;
  final ApiClient api;
  final AuthService auth;
  final Diagnostics diagnostics;
  final String Function() appVersion;
  final String Function() buildNumber;

  /// The font list version, for the snapshot.
  final Future<FontCatalog> Function() fonts;

  static String _offset(int minutes) {
    final sign = minutes < 0 ? '-' : '+';
    final abs = minutes.abs();
    return '$sign${(abs ~/ 60).toString().padLeft(2, '0')}:${(abs % 60).toString().padLeft(2, '0')}';
  }

  static const _sentDayKey = 'feedback_day';
  static const _sentCountKey = 'feedback_count';
  static const _retryDayKey = 'feedback_retry_day';
  static const _retryCountKey = 'feedback_retry_count';

  Directory get _queueDir => Directory(p.join(diagnostics.noBackupDir, 'feedback_queue'));

  Future<int> usedToday() async {
    final today = '${TimeRules.today()}';
    if (await store.getSetting(_sentDayKey) != today) return 0;
    return int.tryParse(await store.getSetting(_sentCountKey) ?? '') ?? 0;
  }

  Future<void> _countOne() async {
    final today = '${TimeRules.today()}';
    final used = await usedToday();
    await store.setSetting(_sentDayKey, today);
    await store.setSetting(_sentCountKey, '${used + 1}');
  }

  Future<Map<String, Object?>> _settingsSummary() async {
    final s = await store.allSettings();
    final counts = await store.counts();
    return {
      'week_start': s[Keys.weekStart] ?? 'monday',
      'theme': s[Keys.theme] ?? 'system',
      'sync_diaries': s[SyncKeys.diaries] == '1',
      'sync_images': s[SyncKeys.images] == '1',
      'signed_in': auth.signedIn,
      ...counts,
    };
  }

  Map<String, Object?> _display() {
    final view = PlatformDispatcher.instance.views.first;
    final ratio = view.devicePixelRatio;
    return {
      'width_dp': (view.physicalSize.width / ratio).round(),
      'height_dp': (view.physicalSize.height / ratio).round(),
      'density': ratio,
      'font_scale': PlatformDispatcher.instance.textScaleFactor,
      'dark_mode': PlatformDispatcher.instance.platformBrightness == Brightness.dark,
      'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
    };
  }

  Future<Map<String, Object?>> _cloudState() async {
    final s = await store.allSettings();
    var drive = 'unknown';
    if (auth.signedIn) {
      try {
        await auth.driveAccessToken(interactive: false);
        drive = 'granted';
      } catch (_) {
        drive = 'not_granted';
      }
    }
    return {
      'same_account_as_sync': auth.user?.sub != null && auth.user?.sub == s[SyncKeys.account],
      'drive_scopes': drive,
      'last_sync_ok': s[SyncKeys.lastOk],
      'last_sync_error': s[SyncKeys.lastError],
      'last_check_at': s[CheckKeys.lastAt],
      'last_check_ok_day': s[CheckKeys.lastOkDay],
      'check_fail_count': s[CheckKeys.failCount],
    };
  }

  /// 組出這次要送出的內容(按下「送出」時呼叫,內容從這一刻凍結)。
  Future<FeedbackDraft> prepare(FeedbackKind kind, String description) async {
    final device = await PlatformInfo.device();
    final summary = await _settingsSummary();
    final snapshot = <String, Object?>{
      'settings': summary,
      'fonts_version': (await store.getSetting(CheckKeys.fonts)) == null ? null : (await fonts()).version,
      'display': _display(),
      'device': device,
    };
    String? attachment;
    var logBytes = 0;
    if (kind == FeedbackKind.problem) {
      snapshot['state'] = await PlatformInfo.state();
      snapshot['cloud'] = await _cloudState();
      final bundle = await _logBundle();
      attachment = base64.encode(bundle);
      logBytes = bundle.length;
    }
    final now = TimeRules.now();
    final body = <String, Object?>{
      'id': newId(),
      'kind': kind.code,
      'description': description.trim(),
      'device_time': '${now.toIso8601String().split('.').first}${_offset(now.timeZoneOffset.inMinutes)}',
      'install_id': await diagnostics.installId(),
      'app_version': appVersion(),
      'build_number': buildNumber(),
      'device_model': '${device['manufacturer'] ?? ''} ${device['model'] ?? ''}'.trim(),
      'os_version': 'Android ${device['release'] ?? ''} (API ${device['sdk'] ?? ''})',
      'snapshot': snapshot,
      'attachment': attachment,
    };
    final items = <(String, String)>[
      ('類型', kind.label),
      ('描述', '${TextRules.length(description.trim())} 字'),
      ('你的 Email', '從登入的 Google 帳號取得，用來回覆你'),
      ('App 版本', '${appVersion()}(${buildNumber()})'),
      ('手機', '${body['device_model']},${body['os_version']}'),
      ('設定摘要', '日記 ${summary['diaries']} 篇、圖片 ${summary['images']} 張（只有數量，不含日記的標題與內容）'),
      if (kind == FeedbackKind.problem) ...[
        ('手機狀態', '剩餘空間、電量、網路類型等'),
        ('雲端狀態', '同步是否成功、最後一次檢查的結果'),
        ('記錄檔', '最近 7 天的使用記錄與當機資訊，壓縮後 ${(logBytes / 1024).toStringAsFixed(1)} KB；不含日記的標題與內容'),
      ],
    ];
    return FeedbackDraft(kind: kind, description: description, body: body, items: items);
  }

  /// 記錄檔、logcat 摘錄、上次結束原因,壓縮後 ≤ 1 MB(超過就從最舊的記錄開始捨棄)。
  Future<List<int>> _logBundle() async {
    var logs = await AppLog.recent();
    final logcat = AppLog.redact(await PlatformInfo.logcat(FeedbackSpec.logcatLines));
    final exits = await PlatformInfo.exitReasons();
    final crashFile = File(p.join(diagnostics.noBackupDir, 'last_native_crash.txt'));
    final nativeCrash = await crashFile.exists() ? AppLog.redact(await crashFile.readAsString()) : null;
    while (true) {
      final bytes = gzip.encode(utf8.encode(jsonEncode({
        'logs': logs,
        'logcat': logcat,
        'exit_reasons': [
          for (final e in exits) {...e, if (e['trace'] is String) 'trace': AppLog.redact(e['trace'] as String)},
        ],
        'native_crash': nativeCrash,
      })));
      if (bytes.length <= FeedbackSpec.uploadMaxCompressed || logs.isEmpty) return bytes;
      logs = logs.sublist(logs.length ~/ 4);
    }
  }

  /// 確認送出。沒有網路(或伺服器暫時不能用)就放進待送清單。
  Future<FeedbackOutcome> submit(FeedbackDraft draft) async {
    if (await usedToday() >= Limits.feedbackPerDay) {
      throw const ApiError(429, 'daily_limit', '今天的意見回饋已經送了 ${Limits.feedbackPerDay} 則，明天會自動恢復');
    }
    try {
      final res = await api.feedback(draft.body);
      await _countOne();
      AppLog.info('feedback.sent', {'kind': draft.kind.code});
      return FeedbackOutcome(id: res['id'] as String? ?? draft.id, sent: true);
    } on ApiError catch (e) {
      if (e.isNetwork || e.isNotReady || e.status >= 500) {
        await _enqueue(draft.body);
        await _countOne();
        return FeedbackOutcome(id: draft.id, sent: false);
      }
      rethrow;
    } on NotSignedIn {
      await _enqueue(draft.body);
      await _countOne();
      return FeedbackOutcome(id: draft.id, sent: false);
    }
  }

  Future<void> _enqueue(Map<String, Object?> body) async {
    await _queueDir.create(recursive: true);
    final f = File(p.join(_queueDir.path, '${body['id']}.json'));
    await f.writeAsString(jsonEncode({'queued_at': DateTime.now().millisecondsSinceEpoch, 'body': body}), flush: true);
    AppLog.info('feedback.queued');
  }

  /// 開 App 時呼叫:重送待送清單。回傳過期(超過 30 天)被刪掉的則數。
  Future<int> retryQueued() async {
    if (!await _queueDir.exists()) return 0;
    final today = '${TimeRules.today()}';
    var tries = await store.getSetting(_retryDayKey) == today ? int.tryParse(await store.getSetting(_retryCountKey) ?? '') ?? 0 : 0;
    var expired = 0;
    final files = [await for (final e in _queueDir.list()) if (e is File && e.path.endsWith('.json')) e];
    for (final f in files) {
      Map<String, Object?> item;
      try {
        item = (jsonDecode(await f.readAsString()) as Map).cast<String, Object?>();
      } catch (_) {
        await f.delete();
        continue;
      }
      final queuedAt = item['queued_at'] as int? ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - queuedAt > const Duration(days: Limits.feedbackQueueDays).inMilliseconds) {
        await f.delete();
        expired++;
        AppLog.info('feedback.expired');
        continue;
      }
      // 登入已過期時先不重送(一定失敗,還會用掉今天的次數);重新登入之後會繼續。
      if (auth.state != AuthState.signedIn || tries >= Limits.feedbackRetriesPerDay) continue;
      tries++;
      await store.setSetting(_retryDayKey, today);
      await store.setSetting(_retryCountKey, '$tries');
      try {
        await api.feedback((item['body'] as Map).cast<String, Object?>());
        await f.delete();
        AppLog.info('feedback.resent');
      } on ApiError catch (e) {
        if (e.status == 400 || e.status == 409 || e.status == 413) {
          await f.delete(); // 伺服器不收的內容,重送也沒用
        }
        if (e.isDailyLimit) break;
      } on NotSignedIn {
        // 這時才發現通行證拿不到:這次不算,等重新登入。
        tries--;
        await store.setSetting(_retryCountKey, '$tries');
        break;
      } catch (_) {
        break;
      }
    }
    return expired;
  }
}
