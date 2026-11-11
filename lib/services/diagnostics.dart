import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/constants.dart';
import '../core/log.dart';
import '../core/text.dart';
import '../data/store.dart';
import 'platform.dart';

/// 安裝 ID 與「上次意外關閉」的偵測(SPEC 第 10 節)。
class Diagnostics {
  Diagnostics(this.store);

  final Store store;
  late final String noBackupDir;
  String? _installId;

  static const _crashSeenKey = 'crash_seen_at';
  static const _crashPromptKey = 'crash_prompt_at';

  Future<void> init() async {
    noBackupDir = await PlatformInfo.noBackupDir();
    await AppLog.init(noBackupDir);
  }

  /// App 第一次開啟時在手機上產生的隨機碼,只在送出意見回饋時附上;
  /// 放在不會被自動備份的資料夾,重新安裝就會換一個(用來看出是否重新安裝過)。
  Future<String> installId() async {
    final cached = _installId;
    if (cached != null) return cached;
    final f = File(p.join(noBackupDir, 'install_id'));
    if (await f.exists()) {
      final v = (await f.readAsString()).trim();
      if (isUuid4(v)) return _installId = v;
    }
    final id = newId();
    await f.writeAsString(id, flush: true);
    return _installId = id;
  }

  /// 上次是不是意外關閉(當機、無回應、原生層當機)。看過的不再算;一天最多提示一次。
  Future<Map<String, Object?>?> unexpectedExit() async {
    try {
      final native = await PlatformInfo.takeNativeCrash();
      if (native != null) {
        AppLog.warn('diag.native_crash_file');
        await File(p.join(noBackupDir, 'last_native_crash.txt')).writeAsString(native.length > FeedbackSpec.traceMaxBytes
            ? native.substring(0, FeedbackSpec.traceMaxBytes)
            : native);
      }
      final exits = await PlatformInfo.exitReasons();
      final seen = int.tryParse(await store.getSetting(_crashSeenKey) ?? '') ?? 0;
      final bad = exits.where((e) => (e['timestamp'] as int? ?? 0) > seen && e['abnormal'] == true).toList();
      if (exits.isNotEmpty) {
        final newest = exits.map((e) => e['timestamp'] as int? ?? 0).reduce((a, b) => a > b ? a : b);
        if (newest > seen) await store.setSetting(_crashSeenKey, '$newest');
      }
      for (final e in bad) {
        AppLog.warn('diag.unexpected_exit', {'reason': e['reason'] as String?, 'status': e['status'] as int?});
      }
      if (bad.isEmpty && native == null) return null;
      final last = int.tryParse(await store.getSetting(_crashPromptKey) ?? '') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last < Timing.crashPromptGap.inMilliseconds) return null;
      await store.setSetting(_crashPromptKey, '$now');
      return bad.isEmpty ? {'reason': 'native_crash'} : bad.first;
    } catch (e, st) {
      AppLog.error('diag.exit_check_failed', e, st);
      return null;
    }
  }
}
