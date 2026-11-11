import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../core/log.dart';
import '../domain/font_catalog.dart';

class FontProblem implements Exception {
  const FontProblem(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Fonts downloaded from the font list (spec §9, §11.1).
///
/// - Files live in `files/fonts/<id>.otf`. The download is the `.otf.gz` on the GitHub Release; it is
///   decompressed while downloading and hashed, and only kept when the SHA-256 matches the list.
/// - A font is loaded into memory (Flutter's FontLoader) only when something needs it — never all
///   installed fonts at start-up: one font can be ~56 MB.
/// - Which characters a font has comes from its `cmap` table, read without loading the whole file.
class FontManager extends ChangeNotifier {
  FontManager(this.dir, {http.Client? client}) : _http = client ?? http.Client();

  final Directory dir;
  final http.Client _http;
  final Set<String> _loaded = {};
  final Map<String, Future<void>> _loading = {};
  final Map<int, CharCoverage> _coverage = {};
  final Set<int> _installing = {};

  /// Installs larger than this ask first (spec §11.1).
  static const askAboveBytes = 50 * 1024 * 1024;

  File file(FontInfo f) => File('${dir.path}/${f.id}.otf');

  Future<bool> isInstalled(FontInfo f) => file(f).exists();

  bool isInstalling(FontInfo f) => _installing.contains(f.id);

  Future<void> install(FontInfo f) async {
    if (f.disabled || f.downloadUrl.isEmpty) throw const FontProblem('這個字體目前不能安裝');
    if (_installing.contains(f.id)) return;
    _installing.add(f.id);
    notifyListeners();
    final target = file(f);
    final tmp = File('${target.path}.part');
    try {
      await dir.create(recursive: true);
      final req = http.Request('GET', Uri.parse(f.downloadUrl));
      final resp = await _http.send(req).timeout(const Duration(seconds: 60));
      if (resp.statusCode != 200) throw FontProblem('下載失敗（${resp.statusCode}），請稍後再試');
      final digest = _DigestSink();
      final hasher = sha256.startChunkedConversion(digest);
      final sink = tmp.openWrite();
      try {
        await for (final chunk in resp.stream.transform(gzip.decoder).timeout(const Duration(seconds: 60))) {
          hasher.add(chunk);
          sink.add(chunk);
        }
      } finally {
        await sink.close();
        hasher.close();
      }
      if (digest.value.toString() != f.fontSha256) {
        AppLog.warn('font.hash_mismatch', {'font': f.id});
        throw const FontProblem('下載的檔案不完整，請再試一次');
      }
      await tmp.rename(target.path);
      AppLog.info('font.installed', {'font': f.id, 'bytes': f.fontBytes});
    } on FontProblem {
      rethrow;
    } catch (e) {
      AppLog.warn('font.install_failed', {'font': f.id, 'type': e.runtimeType.toString()});
      throw const FontProblem('下載失敗，請確認網路後再試');
    } finally {
      if (await tmp.exists()) await tmp.delete();
      _installing.remove(f.id);
      notifyListeners();
    }
  }

  Future<void> uninstall(FontInfo f) async {
    final target = file(f);
    if (await target.exists()) await target.delete();
    _coverage.remove(f.id);
    AppLog.info('font.removed', {'font': f.id});
    notifyListeners();
    // A loaded font stays usable until the app restarts (Flutter can't unload fonts); diaries that use
    // it then show the default font and say the font isn't installed (spec §9.1).
  }

  /// Loads an installed font so text can use [FontInfo.family]. Returns false when it isn't installed.
  Future<bool> ensureLoaded(FontInfo f) async {
    if (_loaded.contains(f.family)) return true;
    final target = file(f);
    if (!await target.exists()) return false;
    await _loading.putIfAbsent(f.family, () async {
      final bytes = await target.readAsBytes();
      final loader = FontLoader(f.family)..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      _loaded.add(f.family);
    }).whenComplete(() {
      _loading.remove(f.family);
    });
    return true;
  }

  /// The characters [f] has. Read from the installed file's cmap table.
  Future<CharCoverage?> coverage(FontInfo f) async {
    final cached = _coverage[f.id];
    if (cached != null) return cached;
    final target = file(f);
    if (!await target.exists()) return null;
    try {
      final c = await CharCoverage.read(target);
      _coverage[f.id] = c;
      return c;
    } catch (e) {
      AppLog.warn('font.cmap_unreadable', {'font': f.id, 'type': e.runtimeType.toString()});
      return null;
    }
  }

  /// The built-in default family, for text that isn't in a downloaded font.
  static const defaultFamily = EditorSpec.defaultFontFamily;
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// The set of code points a font maps to a glyph, as sorted inclusive ranges.
class CharCoverage {
  CharCoverage(this._starts, this._ends);

  final List<int> _starts;
  final List<int> _ends;

  bool has(int codePoint) {
    var lo = 0, hi = _starts.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (codePoint < _starts[mid]) {
        hi = mid - 1;
      } else if (codePoint > _ends[mid]) {
        lo = mid + 1;
      } else {
        return true;
      }
    }
    return false;
  }

  /// Characters in [text] this font doesn't have (spaces and line breaks ignored), in order, unique.
  List<String> missingIn(String text) {
    final out = <String>[];
    final seen = <int>{};
    for (final rune in text.runes) {
      if (rune <= 0x20 || rune == 0xFFFC || seen.contains(rune)) continue;
      seen.add(rune);
      if (!has(rune)) out.add(String.fromCharCode(rune));
    }
    return out;
  }

  /// Reads the cmap of an OpenType/TrueType file without loading the whole file.
  static Future<CharCoverage> read(File file) async {
    final raf = await file.open();
    try {
      Future<ByteData> at(int offset, int length) async {
        await raf.setPosition(offset);
        final bytes = await raf.read(length);
        if (bytes.length < length) throw const FormatException('truncated font');
        return ByteData.sublistView(bytes);
      }

      final head = await at(0, 12);
      final numTables = head.getUint16(4);
      final dir = await at(12, numTables * 16);
      int? cmapOffset, cmapLength;
      for (var i = 0; i < numTables; i++) {
        final tag = String.fromCharCodes([for (var k = 0; k < 4; k++) dir.getUint8(i * 16 + k)]);
        if (tag == 'cmap') {
          cmapOffset = dir.getUint32(i * 16 + 8);
          cmapLength = dir.getUint32(i * 16 + 12);
        }
      }
      if (cmapOffset == null || cmapLength == null) throw const FormatException('no cmap');
      return fromCmap(await at(cmapOffset, cmapLength));
    } finally {
      await raf.close();
    }
  }

  /// Parses a cmap table: prefers the full-Unicode format 12 subtable, else the BMP format 4 one.
  @visibleForTesting
  static CharCoverage fromCmap(ByteData cmap) {
    final count = cmap.getUint16(2);
    int? f12, f4;
    for (var i = 0; i < count; i++) {
      final platform = cmap.getUint16(4 + i * 8), encoding = cmap.getUint16(6 + i * 8);
      final offset = cmap.getUint32(8 + i * 8);
      final format = cmap.getUint16(offset);
      final unicode = platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10));
      if (!unicode) continue;
      if (format == 12) f12 ??= offset;
      if (format == 4) f4 ??= offset;
    }
    final starts = <int>[], ends = <int>[];
    void add(int s, int e) {
      if (starts.isNotEmpty && s <= ends.last + 1) {
        if (e > ends.last) ends[ends.length - 1] = e;
      } else {
        starts.add(s);
        ends.add(e);
      }
    }

    if (f12 != null) {
      final groups = cmap.getUint32(f12 + 12);
      final list = <List<int>>[];
      for (var g = 0; g < groups; g++) {
        final base = f12 + 16 + g * 12;
        final s = cmap.getUint32(base), e = cmap.getUint32(base + 4), glyph = cmap.getUint32(base + 8);
        list.add([glyph == 0 ? s + 1 : s, e]); // glyph 0 is "missing"
      }
      list.sort((a, b) => a[0].compareTo(b[0]));
      for (final r in list) {
        if (r[0] <= r[1]) add(r[0], r[1]);
      }
    } else if (f4 != null) {
      final segX2 = cmap.getUint16(f4 + 6);
      final seg = segX2 ~/ 2;
      final endBase = f4 + 14, startBase = endBase + segX2 + 2, deltaBase = startBase + segX2, rangeBase = deltaBase + segX2;
      for (var i = 0; i < seg; i++) {
        final end = cmap.getUint16(endBase + i * 2), start = cmap.getUint16(startBase + i * 2);
        final delta = cmap.getInt16(deltaBase + i * 2), rangeOffset = cmap.getUint16(rangeBase + i * 2);
        if (start == 0xFFFF) continue;
        int? runStart;
        for (var c = start; c <= end; c++) {
          int glyph;
          if (rangeOffset == 0) {
            glyph = (c + delta) & 0xFFFF;
          } else {
            final addr = rangeBase + i * 2 + rangeOffset + 2 * (c - start);
            glyph = addr + 1 < cmap.lengthInBytes ? cmap.getUint16(addr) : 0;
            if (glyph != 0) glyph = (glyph + delta) & 0xFFFF;
          }
          if (glyph != 0) {
            runStart ??= c;
          } else if (runStart != null) {
            add(runStart, c - 1);
            runStart = null;
          }
        }
        if (runStart != null) add(runStart, end);
      }
    }
    return CharCoverage(starts, ends);
  }
}
