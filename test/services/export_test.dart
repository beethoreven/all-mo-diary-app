import 'dart:convert';
import 'dart:io';

import 'package:allmodiary/core/time.dart';
import 'package:allmodiary/data/database.dart';
import 'package:allmodiary/data/store.dart';
import 'package:allmodiary/domain/diary.dart';
import 'package:allmodiary/services/auth_service.dart';
import 'package:allmodiary/services/export_service.dart';
import 'package:allmodiary/services/sync_engine.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import 'fake_cloud.dart';

class _MemoryStorage implements AuthStorage {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async => value == null ? values.remove(key) : values[key] = value;
}

class _Phone {
  _Phone(this.store, this.export, this.dir);

  final Store store;
  final ExportService export;
  final Directory dir;

  static Future<_Phone> create(FakeCloud cloud) async {
    final dir = Directory.systemTemp.createTempSync('amd_export_');
    final store = Store(AppDb(NativeDatabase.memory()),
        imagesDir: Directory('${dir.path}/images'), cacheDir: Directory('${dir.path}/cache'));
    final storage = _MemoryStorage()
      ..values['auth_user'] = jsonEncode({'sub': 'u1', 'email': 'u1@example.com', 'name': null, 'photo': null});
    final auth = AuthService(storage);
    await auth.init();
    FakeCloud factory({required bool interactive}) => cloud;
    final sync = SyncEngine(store: store, auth: auth, cloud: factory);
    return _Phone(store, ExportService(store: store, sync: sync, appVersion: () => '0.1.0', cloud: factory), dir);
  }

  Future<void> dispose() async {
    await store.db.close();
    dir.deleteSync(recursive: true);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FakeCloud cloud;
  late _Phone a, b;
  const day = Day(2026, 11, 11);

  setUp(() async {
    GoogleSignInPlatform.instance = FakeGoogle();
    cloud = FakeCloud();
    a = await _Phone.create(cloud);
    b = await _Phone.create(cloud);
  });

  tearDown(() async {
    await a.dispose();
    await b.dispose();
  });

  Future<File> exportFrom(_Phone p) async {
    final name = await p.export.export(Directory('${p.dir.path}/tmp'));
    final entry = cloud.files.values.singleWhere((f) => f.name == name);
    expect(name, startsWith('全心日記_匯出_'));
    final file = File('${p.dir.path}/$name')..writeAsBytesSync(entry.bytes);
    return file;
  }

  test('export → import on another phone brings back diaries, images and the name', () async {
    await a.store.setSetting(Keys.userName, '小明');
    final imageId = Store.newId();
    final img = a.store.imageFile(imageId);
    await img.parent.create(recursive: true);
    await img.writeAsBytes(List.generate(3000, (i) => i % 200));
    await a.store.addImage(imageId);
    final body = jsonEncode([
      {'insert': '有圖\n'},
      {'insert': {DiaryBody.imageType: ImageRef(imageId, 10, 10).encode()}},
      {'insert': '\n'},
    ]);
    await a.store.save(DiaryInput(day: day, title: '圖文', body: body));
    await a.store.save(DiaryInput(day: day.addDays(1), title: '第二篇', body: DiaryBody.empty));

    final file = await exportFrom(a);
    expect(utf8.decode(file.readAsBytesSync().sublist(0, 6)), 'ALLMOD');

    final opened = await b.export.open(file, Directory('${b.dir.path}/tmp'));
    final result = await b.export.apply(opened.data, opened.images, ImportConflict.keepPhone);
    expect(result.added, 2);
    expect(result.images, 1);
    expect((await b.store.diaryOn(day))!.title, '圖文');
    expect(await b.store.imageFile(imageId).readAsBytes(), List.generate(3000, (i) => i % 200));
    expect(await b.store.getSetting(Keys.userName), '小明');
  });

  test('a day that already has another diary: keep the phone one, or replace it', () async {
    await a.store.save(DiaryInput(day: day, title: '匯出的', body: DiaryBody.empty));
    final file = await exportFrom(a);
    await b.store.save(DiaryInput(day: day, title: '手機上的', body: DiaryBody.empty));
    final opened = await b.export.open(file, Directory('${b.dir.path}/tmp'));
    expect(await b.export.conflicts(opened.data), [day]);
    expect((await b.export.apply(opened.data, opened.images, ImportConflict.keepPhone)).kept, 1);
    expect((await b.store.diaryOn(day))!.title, '手機上的');
    expect((await b.export.apply(opened.data, opened.images, ImportConflict.useImported)).replaced, 1);
    expect((await b.store.diaryOn(day))!.title, '匯出的');
  });

  test('a file from another Google account, a tampered file, and a non-export file are refused', () async {
    await a.store.save(DiaryInput(day: day, title: 'x', body: DiaryBody.empty));
    final file = await exportFrom(a);

    final bytes = file.readAsBytesSync();
    final tampered = File('${b.dir.path}/t.amd')..writeAsBytesSync([...bytes]..[bytes.length - 5] ^= 1);
    await expectLater(b.export.open(tampered, Directory('${b.dir.path}/tmp')),
        throwsA(isA<ExportProblem>().having((e) => e.message, 'message', contains('損壞'))));

    final other = File('${b.dir.path}/other.txt')..writeAsStringSync('hello');
    await expectLater(b.export.open(other, Directory('${b.dir.path}/tmp')), throwsA(isA<ExportProblem>()));

    cloud.files.removeWhere((_, f) => f.name.startsWith('amd_key_'));
    await expectLater(b.export.open(file, Directory('${b.dir.path}/tmp')),
        throwsA(isA<ExportProblem>().having((e) => e.message, 'message', contains('帳號'))));
  });
}
