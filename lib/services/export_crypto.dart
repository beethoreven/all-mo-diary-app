import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 匯出檔(.amd)的檔頭與加密（照抄 mama-fufood 的 export_crypto.dart，只換了識別字）。
///
///     ALLMOD | 檔頭長度(4 位元組,大端序)| 檔頭 JSON | 加密的段落……
///
/// - 內容切成每段 1 MiB,每段用 AES-256-GCM 個別加密(不用一次載入記憶體,也能發現截斷)。
/// - 每段的隨機數 = 檔頭的 nonce_prefix(8 位元組)+ 段號(4 位元組,大端序)。
/// - 驗證資料 = 整段檔頭 + 1 個位元組(最後一段是 1,其餘是 0):改了檔頭任何一個字、
///   調換或截掉段落,都解不開。
abstract final class AmdCrypto {
  static const magic = 'ALLMOD';
  static const cipherName = 'AES-256-GCM-1MiB';
  static const segment = 1024 * 1024;
  static const _tag = 16;
  static final _aes = AesGcm.with256bits();

  static Uint8List randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  /// 檔頭(不加密,都不是個資)。
  static Uint8List buildHeader(AmdHeader header) {
    final json = utf8.encode(jsonEncode(header.toJson()));
    final out = BytesBuilder()
      ..add(ascii.encode(magic))
      ..add((ByteData(4)..setUint32(0, json.length)).buffer.asUint8List())
      ..add(json);
    return out.takeBytes();
  }

  /// 讀檔頭。開頭不是 ALLMOD 回 null(「這不是全心日記的匯出檔」)。
  static Future<(AmdHeader, Uint8List)?> readHeader(File file) async {
    final raf = await file.open();
    try {
      final head = await raf.read(10);
      if (head.length < 10 || ascii.decode(head.sublist(0, 6), allowInvalid: true) != magic) return null;
      final len = ByteData.sublistView(head, 6, 10).getUint32(0);
      if (len <= 0 || len > 64 * 1024) return null;
      final json = await raf.read(len);
      if (json.length != len) return null;
      try {
        final header = AmdHeader.fromJson((jsonDecode(utf8.decode(json)) as Map).cast<String, Object?>());
        return (header, Uint8List.fromList([...head, ...json]));
      } catch (_) {
        return null;
      }
    } finally {
      await raf.close();
    }
  }

  static Uint8List _nonce(Uint8List prefix, int index) =>
      Uint8List.fromList([...prefix, ...(ByteData(4)..setUint32(0, index)).buffer.asUint8List()]);

  static List<int> _aad(Uint8List header, bool last) => [...header, last ? 1 : 0];

  /// 加密 plain(zip)寫成 .amd。
  static Future<void> encryptFile({required File plain, required File out, required AmdHeader header, required List<int> key}) async {
    final secret = SecretKey(key);
    final headerBytes = buildHeader(header);
    final prefix = base64.decode(header.noncePrefix);
    final input = await plain.open();
    final sink = out.openWrite();
    try {
      sink.add(headerBytes);
      final total = await input.length();
      var index = 0;
      var offset = 0;
      do {
        final chunk = await input.read(segment);
        offset += chunk.length;
        final last = offset >= total;
        final box = await _aes.encrypt(chunk, secretKey: secret, nonce: _nonce(Uint8List.fromList(prefix), index), aad: _aad(headerBytes, last));
        sink
          ..add(box.cipherText)
          ..add(box.mac.bytes);
        index++;
        if (last) break;
      } while (true);
      await sink.flush();
    } finally {
      await input.close();
      await sink.close();
    }
  }

  /// 解密 .amd 寫成 plain。任何一段解不開丟 AmdCorrupted(「檔案損壞或被改過」)。
  static Future<void> decryptFile({required File amd, required File out, required List<int> key}) async {
    final parsed = await readHeader(amd);
    if (parsed == null) throw const AmdCorrupted();
    final (header, headerBytes) = parsed;
    final secret = SecretKey(key);
    final prefix = Uint8List.fromList(base64.decode(header.noncePrefix));
    if (prefix.length != 8) throw const AmdCorrupted();
    final raf = await amd.open();
    final sink = out.openWrite();
    try {
      final total = await raf.length();
      var pos = headerBytes.length;
      await raf.setPosition(pos);
      var index = 0;
      if (pos >= total) throw const AmdCorrupted();
      while (pos < total) {
        final take = min(segment + _tag, total - pos);
        if (take < _tag) throw const AmdCorrupted();
        final data = await raf.read(take);
        pos += data.length;
        final last = pos >= total;
        try {
          final clear = await _aes.decrypt(
            SecretBox(data.sublist(0, data.length - _tag), nonce: _nonce(prefix, index), mac: Mac(data.sublist(data.length - _tag))),
            secretKey: secret,
            aad: _aad(headerBytes, last),
          );
          sink.add(clear);
        } on SecretBoxAuthenticationError {
          throw const AmdCorrupted();
        }
        index++;
      }
      await sink.flush();
    } finally {
      await raf.close();
      await sink.close();
    }
  }
}

class AmdHeader {
  const AmdHeader({
    required this.formatVersion,
    required this.appVersion,
    required this.exportedAt,
    required this.keyId,
    this.cipher = AmdCrypto.cipherName,
    required this.noncePrefix,
  });

  factory AmdHeader.fromJson(Map<String, Object?> j) => AmdHeader(
        formatVersion: j['format_version'] as int,
        appVersion: j['app_version'] as String,
        exportedAt: j['exported_at'] as String,
        keyId: j['key_id'] as String,
        cipher: j['cipher'] as String,
        noncePrefix: j['nonce_prefix'] as String,
      );

  final int formatVersion;
  final String appVersion;
  final String exportedAt;
  final String keyId;
  final String cipher;
  final String noncePrefix;

  Map<String, Object?> toJson() => {
        'format_version': formatVersion,
        'app_version': appVersion,
        'exported_at': exportedAt,
        'key_id': keyId,
        'cipher': cipher,
        'nonce_prefix': noncePrefix,
      };
}

class AmdCorrupted implements Exception {
  const AmdCorrupted();

  @override
  String toString() => '檔案損壞或被修改過，無法匯入。';
}
