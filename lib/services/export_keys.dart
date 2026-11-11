import 'dart:convert';
import 'dart:typed_data';

import '../core/log.dart';
import '../core/text.dart';
import 'drive_store.dart';
import 'export_crypto.dart';

class ExportKey {
  const ExportKey(this.id, this.bytes, this.createdAt);

  final String id;
  final List<int> bytes;
  final int createdAt;
}

/// 匯出檔的金鑰（照抄 mama-fufood 的 export_keys.dart）:
///
/// - 一個 Google 帳號一把,256 位元亂數,存在該帳號雲端硬碟的 App 專用區;我們拿不到。
/// - 建立前一定先查有沒有既有的;**只有雲端硬碟明確回答「沒有」才建立**,讀取失敗
///   (例如斷網)一律當作錯誤,不能因此另產生一把。
/// - 防呆:兩支手機剛好同時第一次匯出、各自建立了一把時,兩把都保留;之後一律用
///   建立時間最早的那把(一樣就比金鑰代號)。匯入時依檔頭的金鑰代號找,使用者不用分。
class ExportKeys {
  ExportKeys(this.cloud);

  final CloudStore cloud;
  static const prefix = 'amd_key_';

  Future<List<CloudFile>> _list() async => [
        for (final f in await cloud.listAppData(prefix))
          if (f.name.startsWith(prefix) && f.name.endsWith('.json')) f,
      ];

  Future<ExportKey> _read(CloudFile f) async {
    final j = (jsonDecode(utf8.decode(await cloud.readAppData(f.id))) as Map).cast<String, Object?>();
    final bytes = base64.decode(j['key'] as String);
    if (bytes.length != 32) throw const FormatException('金鑰檔的格式不對');
    return ExportKey(j['key_id'] as String, bytes, j['created_at'] as int);
  }

  ExportKey _earliest(List<ExportKey> keys) {
    keys.sort((a, b) => a.createdAt != b.createdAt ? a.createdAt.compareTo(b.createdAt) : a.id.compareTo(b.id));
    return keys.first;
  }

  /// 匯出用:有就用最早的那把;雲端硬碟明確回答沒有才建立。
  Future<ExportKey> getOrCreate() async {
    final existing = await _list(); // 失敗會丟例外,不會往下建立新的
    if (existing.isNotEmpty) {
      return _earliest([for (final f in existing) await _read(f)]);
    }
    final key = ExportKey(newId(), AmdCrypto.randomBytes(32), DateTime.now().toUtc().millisecondsSinceEpoch);
    final body = Uint8List.fromList(utf8.encode(jsonEncode({'key_id': key.id, 'key': base64.encode(key.bytes), 'created_at': key.createdAt})));
    await cloud.createAppData('$prefix${key.id}.json', body, props: {'c': '${key.createdAt}'});
    AppLog.info('export.key_created');
    // 再查一次:萬一另一支手機同時也建了一把,大家都改用最早的那把。
    final after = await _list();
    return _earliest([for (final f in after) await _read(f)]);
  }

  /// 匯入用:依檔頭的金鑰代號找;找不到回 null(代表帳號不對)。
  Future<ExportKey?> find(String keyId) async {
    for (final f in await _list()) {
      if (f.name == '$prefix$keyId.json') return _read(f);
    }
    return null;
  }
}
