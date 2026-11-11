import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:allmodiary/core/time.dart';
import 'package:allmodiary/data/database.dart';
import 'package:allmodiary/data/store.dart';
import 'package:allmodiary/domain/diary.dart';
import 'package:allmodiary/services/auth_service.dart';
import 'package:allmodiary/services/drive_store.dart';
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

/// One simulated phone: its own database and folders, the shared fake cloud, a signed-in account.
class _Phone {
  _Phone._(this.store, this.sync, this.dir);

  final Store store;
  final SyncEngine sync;
  final Directory dir;

  static Future<_Phone> create(FakeCloud cloud, {String sub = 'u1'}) async {
    final dir = Directory.systemTemp.createTempSync('amd_sync_');
    final store = Store(AppDb(NativeDatabase.memory()),
        imagesDir: Directory('${dir.path}/images'), cacheDir: Directory('${dir.path}/cache'));
    final storage = _MemoryStorage()
      ..values['auth_user'] = jsonEncode({'sub': sub, 'email': '$sub@example.com', 'name': null, 'photo': null});
    final auth = AuthService(storage);
    await auth.init();
    return _Phone._(store, SyncEngine(store: store, auth: auth, cloud: ({required interactive}) => cloud), dir);
  }

  Future<void> dispose() async {
    await store.db.close();
    dir.deleteSync(recursive: true);
  }
}

String bodyWithImage(String id) =>
    jsonEncode([
      {'insert': '有圖\n'},
      {'insert': {DiaryBody.imageType: ImageRef(id, 10, 10).encode()}},
      {'insert': '\n'},
    ]);

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

  test('a diary written on one phone reaches the other, edits and deletions follow', () async {
    final d = await a.store.save(DiaryInput(day: day, title: '第一篇', body: DiaryBody.empty));
    await a.sync.setDiariesOn(true);
    expect(a.sync.state, SyncState.ok);
    expect(cloud.files.values.where((f) => f.name.startsWith('amd_diary_')), hasLength(1));

    await b.sync.setDiariesOn(true);
    expect((await b.store.diaryOn(day))!.title, '第一篇');

    await b.store.save(DiaryInput(id: d.id, day: day, title: '改過了', body: DiaryBody.empty));
    await b.sync.syncNow();
    await a.sync.syncNow();
    expect((await a.store.diaryOn(day))!.title, '改過了');

    await a.store.delete(d.id);
    await a.sync.syncNow();
    await b.sync.syncNow();
    expect(await b.store.diaryOn(day), isNull, reason: 'a deletion is a tombstone, so it reaches the other phone');
    final tombstone = utf8.decode(cloud.files.values.singleWhere((f) => f.name.startsWith('amd_diary_')).bytes);
    expect(tombstone, isNot(contains('改過了')), reason: 'the copy left in Drive keeps no title or text');
  });

  test('the user name syncs, newer wins', () async {
    await a.store.setSetting(Keys.userName, '小明');
    await a.store.setSetting(SyncKeys.profileUpdatedAt, '${TimeRules.nowMs()}');
    await a.sync.setDiariesOn(true);
    await b.sync.setDiariesOn(true);
    expect(await b.store.getSetting(Keys.userName), '小明');
  });

  test('offline: the sync fails with a message and nothing on the phone is lost', () async {
    await a.store.save(DiaryInput(day: day, title: '離線', body: DiaryBody.empty));
    await a.sync.setDiariesOn(true);
    cloud.offline = true;
    await a.store.save(DiaryInput(day: day.addDays(1), title: '第二篇', body: DiaryBody.empty));
    await a.sync.syncNow();
    expect(a.sync.state, SyncState.error);
    expect(a.sync.lastError, isNotNull);
    expect((await a.store.diaryOn(day.addDays(1)))!.title, '第二篇');
    cloud.offline = false;
    await a.sync.syncNow();
    expect(cloud.files.values.where((f) => f.name.startsWith('amd_diary_')), hasLength(2));
  });

  Future<String> addImage(_Phone p) async {
    final id = Store.newId();
    final f = p.store.imageFile(id);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(List.generate(2000, (i) => i % 251));
    await p.store.addImage(id);
    return id;
  }

  test('images go to the cloud, the phone copy is freed after the MD5 matches, another phone downloads it', () async {
    final id = await addImage(a);
    await a.store.save(DiaryInput(day: day, title: '圖', body: bodyWithImage(id)));
    await a.sync.setDiariesOn(true);
    await a.sync.setImagesOn(true);
    expect(cloud.files.values.where((f) => f.name == '$id.jpg'), hasLength(1));
    expect(await a.store.imageFile(id).exists(), isFalse, reason: 'freed on the phone');
    expect((await a.store.image(id))!.hasLocal, isFalse);
    expect(await a.sync.resolveImage(id), isNotNull, reason: 'still shows (cached copy)');

    await b.sync.setDiariesOn(true);
    final shown = await b.sync.resolveImage(id);
    expect(shown, isNotNull);
    expect(await shown!.readAsBytes(), List.generate(2000, (i) => i % 251));
  });

  test('an image is shown from the cloud only while it can be fetched; offline it is null, not a hang', () async {
    final id = await addImage(a);
    await a.store.save(DiaryInput(day: day, title: '圖', body: bodyWithImage(id)));
    await a.sync.setDiariesOn(true);
    await a.sync.setImagesOn(true);
    await b.sync.setDiariesOn(true);
    cloud.offline = true;
    expect(await b.sync.resolveImage(id), isNull);
    cloud.offline = false;
    expect(await b.sync.resolveImage(id), isNotNull);
  });

  test('turning images off brings every image back to the phone first', () async {
    final id = await addImage(a);
    await a.store.save(DiaryInput(day: day, title: '圖', body: bodyWithImage(id)));
    await a.sync.setDiariesOn(true);
    await a.sync.setImagesOn(true);
    await a.store.cachedImageFile(id).delete();
    await a.sync.setImagesOn(false);
    expect(await a.store.imageFile(id).exists(), isTrue);
    expect((await a.store.image(id))!.hasLocal, isTrue);
    expect(await a.sync.imagesOn, isFalse);
  });

  test('a sync pass started while turning images off waits, so no image ends up only in the cloud', () async {
    final first = await addImage(a), second = await addImage(a);
    await a.store.save(DiaryInput(day: day, title: '一', body: bodyWithImage(first)));
    await a.store.save(DiaryInput(day: day.addDays(1), title: '二', body: bodyWithImage(second)));
    await a.sync.setDiariesOn(true);
    await a.sync.setImagesOn(true);
    for (final id in [first, second]) {
      await a.store.cachedImageFile(id).delete(); // so turning off has to download them
    }
    final gate = Completer<void>();
    var downloads = 0;
    cloud.beforeDownload = (_) async {
      if (++downloads == 2) await gate.future; // hold the second download open
    };
    final off = a.sync.setImagesOn(false);
    while (downloads < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    // One image is back on the phone, the other still downloading: now a pass starts (returning to
    // the app, the retry timer, saving a diary). It must not free the image just brought back.
    await a.sync.syncNow();
    gate.complete();
    await off;
    while (a.sync.state == SyncState.running) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(await a.sync.imagesOn, isFalse);
    for (final id in [first, second]) {
      expect(await a.store.imageFile(id).exists(), isTrue, reason: 'image $id must be on the phone');
      expect((await a.store.image(id))!.hasLocal, isTrue);
    }
  });

  test('turning images off with a download that breaks part-way leaves no half file on the phone', () async {
    final id = await addImage(a);
    await a.store.save(DiaryInput(day: day, title: '圖', body: bodyWithImage(id)));
    await a.sync.setDiariesOn(true);
    await a.sync.setImagesOn(true);
    await a.store.cachedImageFile(id).delete();
    cloud.failDownloadsHalfway = true;
    await expectLater(a.sync.setImagesOn(false), throwsA(isA<CloudError>()));
    expect(await a.store.imageFile(id).exists(), isFalse,
        reason: 'a half file at the real path would be shown and exported instead of the cloud copy');
    expect(await a.sync.imagesOn, isTrue, reason: 'stays on until every image is back');
    cloud.failDownloadsHalfway = false;
    await a.sync.setImagesOn(false);
    expect(await a.store.imageFile(id).readAsBytes(), List.generate(2000, (i) => i % 251));
  });

  test('showing a diary whose image is not in the cloud never creates folders in Drive', () async {
    final id = await addImage(a); // images stay on phone A only (images switch off)
    await a.store.save(DiaryInput(day: day, title: '圖', body: bodyWithImage(id)));
    await a.sync.setDiariesOn(true);
    await b.sync.setDiariesOn(true);
    expect(await b.sync.resolveImage(id), isNull);
    expect(cloud.folders, isEmpty);
  });

  test('an image no diary uses any more is removed from the cloud', () async {
    final id = await addImage(a);
    final d = await a.store.save(DiaryInput(day: day, title: '圖', body: bodyWithImage(id)));
    await a.sync.setDiariesOn(true);
    await a.sync.setImagesOn(true);
    await a.store.save(DiaryInput(id: d.id, day: day, title: '圖拿掉了', body: DiaryBody.empty));
    await a.sync.syncNow();
    expect(cloud.files.values.where((f) => f.name == '$id.jpg'), isEmpty);
    expect(await a.store.image(id), isNull);
  });

  test('a different account than the one the cloud data belongs to stops the sync with a message', () async {
    await a.sync.setDiariesOn(true);
    final other = await _Phone.create(cloud, sub: 'u2');
    addTearDown(other.dispose);
    await other.store.setSetting(SyncKeys.diaries, '1');
    await other.store.setSetting(SyncKeys.account, 'u1');
    await other.sync.syncNow();
    expect(other.sync.state, SyncState.error);
    expect(other.sync.lastError, contains('帳號'));
  });
}
