import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:allmodiary/domain/font_catalog.dart';
import 'package:allmodiary/services/font_licenses.dart';
import 'package:allmodiary/services/font_manager.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A cmap table with one format 12 subtable mapping [ranges] (inclusive, glyph ids from 1).
ByteData cmap12(List<(int, int)> ranges) {
  final b = BytesBuilder();
  void u16(int v) => b.add([v >> 8 & 0xff, v & 0xff]);
  void u32(int v) => b.add([v >> 24 & 0xff, v >> 16 & 0xff, v >> 8 & 0xff, v & 0xff]);
  u16(0);
  u16(1); // one encoding record
  u16(3);
  u16(10);
  u32(12); // subtable right after the header
  u16(12);
  u16(0);
  u32(16 + ranges.length * 12);
  u32(0);
  u32(ranges.length);
  var glyph = 1;
  for (final (s, e) in ranges) {
    u32(s);
    u32(e);
    u32(glyph);
    glyph += e - s + 1;
  }
  return ByteData.sublistView(b.toBytes());
}

/// A cmap with one format 4 subtable for a single segment [start]..[end] (plus the 0xFFFF end segment).
ByteData cmap4(int start, int end) {
  final b = BytesBuilder();
  void u16(int v) => b.add([v >> 8 & 0xff, v & 0xff]);
  void u32(int v) => b.add([v >> 24 & 0xff, v >> 16 & 0xff, v >> 8 & 0xff, v & 0xff]);
  u16(0);
  u16(1);
  u16(3);
  u16(1);
  u32(12);
  u16(4);
  u16(32); // length
  u16(0);
  u16(4); // segCountX2 (2 segments)
  u16(0);
  u16(0);
  u16(0);
  u16(end);
  u16(0xFFFF); // endCode
  u16(0); // reservedPad
  u16(start);
  u16(0xFFFF); // startCode
  u16((1 - start) & 0xFFFF);
  u16(1); // idDelta
  u16(0);
  u16(0); // idRangeOffset
  return ByteData.sublistView(b.toBytes());
}

void main() {
  test('format 12: missing characters are found, spaces ignored', () {
    final c = CharCoverage.fromCmap(cmap12([(0x20, 0x7e), (0x4e00, 0x4e10)]));
    expect(c.has('A'.codeUnitAt(0)), isTrue);
    expect(c.has(0x4e00), isTrue);
    expect(c.missingIn('Hi 一 日記 日'), ['日', '記']);
  });

  test('format 4 (BMP) is read too', () {
    final c = CharCoverage.fromCmap(cmap4(0x41, 0x5a));
    expect(c.missingIn('AZa'), ['a']);
  });

  test('installing verifies the SHA-256 of the decompressed font', () async {
    final dir = Directory.systemTemp.createTempSync('amd_fonts_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final font = Uint8List.fromList([...'OTTO'.codeUnits, ...List.generate(5000, (i) => i % 256)]);
    final gz = gzip.encode(font);
    final client = MockClient.streaming((req, _) async => http.StreamedResponse(Stream.value(gz), 200));
    final manager = FontManager(dir, client: client);
    FontInfo info(String sha) => FontInfo(
        id: 7,
        name: '測試',
        sort: 0,
        disabled: false,
        licensed: true,
        downloadUrl: 'https://example/font.otf.gz',
        downloadBytes: gz.length,
        downloadSha256: '',
        fontBytes: font.length,
        fontSha256: sha);

    await expectLater(manager.install(info('0' * 64)), throwsA(isA<FontProblem>()));
    expect(await manager.isInstalled(info('0' * 64)), isFalse, reason: 'a bad download is never kept');

    final good = info(sha256.convert(font).toString());
    await manager.install(good);
    expect(await manager.isInstalled(good), isTrue);
    expect(await manager.file(good).readAsBytes(), font);
    await manager.uninstall(good);
    expect(await manager.isInstalled(good), isFalse);
  });

  test('a second install of a font being installed waits for the first, not returning at once', () async {
    final dir = Directory.systemTemp.createTempSync('amd_fonts_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final font = Uint8List.fromList([...'OTTO'.codeUnits, ...List.generate(5000, (i) => i % 256)]);
    final gz = gzip.encode(font);
    final release = Completer<void>();
    var requests = 0;
    final client = MockClient.streaming((req, _) async {
      requests++;
      await release.future;
      return http.StreamedResponse(Stream.value(gz), 200);
    });
    final manager = FontManager(dir, client: client);
    final f = FontInfo(
        id: 8,
        name: '測試',
        sort: 0,
        disabled: false,
        licensed: true,
        downloadUrl: 'https://example/font.otf.gz',
        downloadBytes: gz.length,
        downloadSha256: '',
        fontBytes: font.length,
        fontSha256: sha256.convert(font).toString());
    final first = manager.install(f);
    var secondDone = false;
    final second = manager.install(f).then((_) => secondDone = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(manager.isInstalling(f), isTrue);
    expect(secondDone, isFalse, reason: 'the page would say 「已安裝」 while it is still downloading');
    release.complete();
    await first;
    await second;
    expect(await manager.isInstalled(f), isTrue);
    expect(manager.isInstalling(f), isFalse);
    expect(requests, 1, reason: 'one download');
  });

  test('half-downloaded files from a closed app are removed at start-up', () async {
    final dir = Directory.systemTemp.createTempSync('amd_fonts_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/3.otf.part').writeAsBytesSync([1, 2, 3]);
    File('${dir.path}/3.otf').writeAsBytesSync([4]);
    await FontManager(dir).cleanupPartials();
    expect(File('${dir.path}/3.otf.part').existsSync(), isFalse);
    expect(File('${dir.path}/3.otf').existsSync(), isTrue);
  });

  test('the font list keeps the admin order and finds fonts by family', () {
    final catalog = FontCatalog.decode('{"version":"20261111","content":{"fonts":['
        '{"id":2,"name":"B","sort":2},{"id":1,"name":"A","sort":1}]}}');
    expect(catalog.fonts.map((f) => f.name), ['A', 'B']);
    expect(catalog.byFamily('amdfont2')!.name, 'B');
    expect(FontCatalog.decode('garbage').fonts, isEmpty);
  });

  // The statement the CNS11643 font site asks products to show for its fonts.
  const kaiSource = '來源：數位發展部，CNS11643中文標準交換碼全字庫網站，https://www.cns11643.gov.tw';

  test('a font carries its source and licence statement; a list published without the key still reads', () {
    final catalog = FontCatalog.decode(jsonEncode({
      'version': '20261124000000',
      'content': {
        'fonts': [
          {'id': 1, 'name': '全字庫正楷體', 'sort': 1, 'licensed': true, 'attribution': '  $kaiSource\n'},
          {'id': 2, 'name': '沒有這個欄位的清單', 'sort': 2, 'licensed': true, 'font_bytes': 200},
          {'id': 3, 'name': '欄位不是文字', 'sort': 3, 'attribution': 5},
        ],
      },
    }));
    expect(catalog.fonts.map((f) => f.attribution), [kaiSource, '', '']);
    expect(catalog.fonts[1].licensed, isTrue, reason: 'the keys read before are read the same way');
    expect(catalog.fonts[1].fontBytes, 200);
  });

  test('the licence page lists each font that has a statement, under its name and line by line', () async {
    const notice = 'Copyright 2021 The Example Project Authors\n\n  SIL Open Font License 1.1  ';
    final catalog = FontCatalog.decode(jsonEncode({
      'version': '20261124000000',
      'content': {
        'fonts': [
          {'id': 1, 'name': '全字庫正楷體', 'sort': 1, 'attribution': kaiSource},
          {'id': 2, 'name': '不需要說明的字體', 'sort': 2},
          {'id': 3, 'name': '兩行說明的字體', 'sort': 3, 'attribution': notice},
        ],
      },
    }));
    final entries = await fontLicenses(() async => catalog).toList();
    expect(entries.map((e) => e.packages.single), ['全字庫正楷體', '兩行說明的字體']);
    expect(entries[0].paragraphs.map((p) => p.text), [kaiSource]);
    expect(entries[1].paragraphs.map((p) => p.text),
        ['Copyright 2021 The Example Project Authors', 'SIL Open Font License 1.1']);
    expect(await fontLicenses(() async => FontCatalog.empty).toList(), isEmpty);
  });

  test('a font list that cannot be read leaves the other licences on the page', () async {
    // The licence page shows a failing source's error instead of every licence, so this one must
    // end quietly; the registry then still delivers what the other sources give.
    LicenseRegistry.reset();
    addTearDown(LicenseRegistry.reset);
    LicenseRegistry.addLicense(() => Stream.value(const LicenseEntryWithLineBreaks(['Noto Sans TC'], 'SIL Open Font License')));
    LicenseRegistry.addLicense(() => fontLicenses(() async => throw StateError('the database is closed')));
    final entries = await LicenseRegistry.licenses.toList();
    expect(entries.map((e) => e.packages.single), ['Noto Sans TC']);
  });
}
