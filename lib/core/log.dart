import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'constants.dart';

/// 手機上的結構化記錄檔（照抄 mama-fufood 的 core/log.dart；全心日記規格 §10）。只存在 App 私有空間,
/// 不會自動上傳;使用者主動送出「遇到問題」的意見回饋時才附上。
///
/// ★ 白名單寫法:只收事件代碼、數字與選項值,不收自由文字;錯誤訊息先遮蔽再截斷。
///   不記日記的標題、內文與使用者名稱。
/// - 同一個錯誤連續重複時只記一筆加上次數,避免錯誤迴圈把一週的記錄洗掉。
/// - 只保留 7 天;記錄檔總共 2 MB 上限,超過時先刪最舊的。
/// - debug 版印出所有等級;release 版只記 info 以上,也不印到 logcat。
abstract final class AppLog {
  static Directory? _dir;
  static final List<String> _pending = [];
  static String? _lastKey;
  static int _repeat = 0;
  static Future<void> _writing = Future.value();

  /// 遮蔽用的使用者名稱（「名字的日記」的那個名字，逐字比對）。
  static String? userName;

  /// 遮蔽用的 Google 帳號顯示名稱(通常是本名;登入、登出時由 AuthService 設定)。
  static String? accountName;

  static final _safeValue = RegExp(r'^[A-Za-z0-9_.:\-/]{0,48}$');

  static Future<void> init(String noBackupDir) async {
    final dir = Directory(p.join(noBackupDir, 'diagnostics'));
    await dir.create(recursive: true);
    _dir = dir;
    await _prune();
    final pending = List<String>.of(_pending);
    _pending.clear();
    for (final line in pending) {
      _append(line);
    }
  }

  static Directory? get directory => _dir;

  static void debug(String code, [Map<String, Object?> fields = const {}]) {
    if (kDebugMode) _log('debug', code, fields);
  }

  static void info(String code, [Map<String, Object?> fields = const {}]) => _log('info', code, fields);

  static void warn(String code, [Map<String, Object?> fields = const {}]) => _log('warn', code, fields);

  static void error(String code, Object error, [StackTrace? stack, Map<String, Object?> fields = const {}]) {
    _log('error', code, {
      ...fields,
      'type': error.runtimeType.toString(),
      'msg': redact(error.toString()),
      if (stack != null) 'stack': _shortStack(stack),
    }, allowText: true);
  }

  static void _log(String level, String code, Map<String, Object?> fields, {bool allowText = false}) {
    final clean = <String, Object?>{};
    fields.forEach((k, v) {
      if (v == null || v is num || v is bool) {
        clean[k] = v;
      } else if (v is String && (allowText || _safeValue.hasMatch(v))) {
        clean[k] = v;
      } else if (v is Enum) {
        clean[k] = v.name;
      }
      // 其他型別(自由文字、物件)一律不記。
    });
    final key = '$level|$code|${jsonEncode(clean)}';
    if (key == _lastKey) {
      _repeat += 1;
      return;
    }
    if (_repeat > 0) {
      _emit('info', 'log.repeat', {'n': _repeat});
      _repeat = 0;
    }
    _lastKey = key;
    _emit(level, code, clean);
  }

  static void _emit(String level, String code, Map<String, Object?> fields) {
    final line = jsonEncode({'t': DateTime.now().toUtc().toIso8601String(), 'lv': level, 'c': code, ...fields});
    if (kDebugMode) debugPrint('[amd] $line');
    if (_dir == null) {
      if (_pending.length < 500) _pending.add(line);
      return;
    }
    _append(line);
  }

  static void _append(String line) {
    final dir = _dir!;
    _writing = _writing.then((_) async {
      final day = DateTime.now().toUtc().toIso8601String().substring(0, 10).replaceAll('-', '');
      final file = File(p.join(dir.path, 'log-$day.jsonl'));
      await file.writeAsString('$line\n', mode: FileMode.append, flush: false);
    }).catchError((Object _) {});
  }

  /// 刪掉超過 7 天的檔案,並維持總大小在 2 MB 以內(先刪最舊的)。
  static Future<void> _prune() async {
    final dir = _dir;
    if (dir == null) return;
    final cutoff = DateTime.now().subtract(Timing.logRetention);
    final files = <File>[];
    await for (final e in dir.list()) {
      if (e is File) files.add(e);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    var total = 0;
    final keep = <File>[];
    for (final f in files) {
      final stat = await f.stat();
      if (stat.modified.isBefore(cutoff)) {
        await f.delete();
      } else {
        keep.add(f);
        total += stat.size;
      }
    }
    while (total > Timing.logMaxBytes && keep.length > 1) {
      final oldest = keep.removeAt(0);
      total -= await oldest.length();
      await oldest.delete();
    }
  }

  /// 最近 7 天的記錄(送意見回饋用)。
  static Future<List<Map<String, Object?>>> recent() async {
    await _writing;
    final dir = _dir;
    if (dir == null) return const [];
    await _prune();
    final files = [await for (final e in dir.list()) if (e is File && e.path.endsWith('.jsonl')) e]
      ..sort((a, b) => a.path.compareTo(b.path));
    final out = <Map<String, Object?>>[];
    for (final f in files) {
      for (final line in await f.readAsLines()) {
        try {
          out.add((jsonDecode(line) as Map).cast<String, Object?>());
        } catch (_) {}
      }
    }
    return out;
  }

  static Future<int> sizeBytes() async {
    final dir = _dir;
    if (dir == null) return 0;
    var total = 0;
    await for (final e in dir.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  static String _shortStack(StackTrace stack) =>
      stack.toString().split('\n').where((l) => l.trim().isNotEmpty).take(25).map(redact).join('\n');

  static final _email = RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}');
  static final _jwt = RegExp(r'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+');
  static final _token = RegExp(r'\b(?:ya29|1//)[A-Za-z0-9_\-.]+');
  static final _bearer = RegExp(r'(Bearer\s+)\S+', caseSensitive: false);
  static final _query = RegExp(r'(https?://[^\s?#"]+)\?[^\s"]*');
  static final _quoted = RegExp(r'"[^"]{1,200}"|「[^」]{1,200}」|' r"'[^']{1,200}'");
  // 台灣的手機(09xx 或 +886 9xx)與市話(0x 開頭、可加括號),數字間可以有空白或連字號。
  static final _phone = RegExp(r'(?<![\w+])(?:\+886[-\s]?9|09)\d{2}[-\s]?\d{3}[-\s]?\d{3}(?!\d)|'
      r'(?<![\w(])\(?0\d{1,2}\)?[-\s]?\d{3,4}[-\s]?\d{4}(?!\d)');
  // Android ID 這類 16 位十六進位的裝置識別碼。
  static final _deviceId = RegExp(r'\b[0-9a-fA-F]{16}\b');
  static final _fileName = RegExp(r'[^\s/\\:"]+\.(amd|otf|ttf|gz|jpg|jpeg|png|json|zip|sqlite)\b', caseSensitive: false);
  static final _ip = RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}\b');
  // 雲端硬碟的檔案編號這類長字串;紀錄的 UUID 保留(除錯需要),所以排除 UUID 的形狀。
  // 前後都要是整段字串的邊界(不能接在字母、數字、- 後面),否則 UUID 第一段之後的 27 個字會被當成檔案編號。
  static final _driveId = RegExp(r'(?<![\w-])(?![0-9a-fA-F]{8}-[0-9a-fA-F]{4}-)[A-Za-z0-9_\-]{25,}(?![\w-])');

  /// 遮蔽個人資料與憑證(SPEC 第 10 節「個人資料與遮蔽」),再截斷到 300 字。
  static String redact(String text) {
    var t = text;
    final user = userName?.trim() ?? '';
    if (user.characters.length >= 2) t = t.replaceAll(user, '[姓名]');
    final account = accountName?.trim() ?? '';
    // 一個字的名稱太容易誤傷其他文字,兩個字以上才比對。
    if (account.characters.length >= 2) t = t.replaceAll(account, '[姓名]');
    t = t
        .replaceAll(_jwt, '[token]')
        .replaceAll(_token, '[token]')
        .replaceAllMapped(_bearer, (m) => '${m[1]}[token]')
        .replaceAll(_email, '[email]')
        .replaceAllMapped(_query, (m) => '${m[1]}?[…]')
        .replaceAllMapped(_fileName, (m) => '[檔名].${m[1]}')
        .replaceAll(_quoted, '"[文字]"')
        .replaceAll(_ip, '[ip]')
        .replaceAll(_phone, '[電話]')
        .replaceAll(_deviceId, '[id]')
        .replaceAll(_driveId, '[id]');
    return t.length > 300 ? '${t.substring(0, 300)}…' : t;
  }
}
