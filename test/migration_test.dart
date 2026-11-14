import 'package:allmodiary/data/database.dart';
import 'package:allmodiary/data/store.dart';
import 'package:allmodiary/domain/diary.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

/// The tables as earlier versions of the app created them (copied from the databases they made).
const _diaries =
    'CREATE TABLE "diaries" ("id" TEXT NOT NULL, "day" TEXT NOT NULL, "title" TEXT NOT NULL, "body" TEXT NOT NULL, '
    '"body_plain" TEXT NOT NULL, "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, '
    '"deleted" INTEGER NOT NULL DEFAULT 0 CHECK ("deleted" IN (0, 1)), '
    '"dirty" INTEGER NOT NULL DEFAULT 1 CHECK ("dirty" IN (0, 1)), PRIMARY KEY ("id"))';
const _drafts =
    'CREATE TABLE "drafts" ("key" TEXT NOT NULL, "diary_id" TEXT NULL, "day" TEXT NOT NULL, "title" TEXT NOT NULL, '
    '"body" TEXT NOT NULL, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("key"))';
const _settings = 'CREATE TABLE "settings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"))';
const _index = 'CREATE UNIQUE INDEX diaries_one_per_day ON diaries (day) WHERE deleted = 0';

/// Schema version 2 (app 1.0.0): images only.
const _imagesV2 =
    'CREATE TABLE "images" ("id" TEXT NOT NULL, "has_local" INTEGER NOT NULL DEFAULT 1 CHECK ("has_local" IN (0, 1)), '
    '"cloud_file_id" TEXT NULL, "cloud_md5" TEXT NULL, "created_at" INTEGER NOT NULL, PRIMARY KEY ("id"))';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Store open(void Function(dynamic raw) setup) {
    final db = AppDb(NativeDatabase.memory(setup: setup));
    return Store(db, imagesDir: Directory.systemTemp);
  }

  test('a database from app 1.0.0 keeps its images, and the cloud switch stays on, after the update', () async {
    final store = open((raw) {
      for (final sql in [_diaries, _drafts, _settings, _imagesV2, _index]) {
        raw.execute(sql);
      }
      raw.execute("INSERT INTO images (id, has_local, cloud_file_id, cloud_md5, created_at) "
          "VALUES ('on-phone', 1, NULL, NULL, 10), ('in-cloud', 0, 'drive-1', 'abc', 20)");
      raw.execute("INSERT INTO settings (key, value) VALUES ('sync_images', '1'), ('user_name', '小明')");
      raw.execute('PRAGMA user_version = 2');
    });
    addTearDown(store.db.close);

    final rows = {for (final r in await store.mediaRows()) r.id: r};
    expect(rows.keys, {'on-phone', 'in-cloud'});
    expect(rows.values.map((r) => r.kind).toSet(), {MediaKind.image.code}, reason: 'everything stored before was an image');
    expect((rows['in-cloud']!.hasLocal, rows['in-cloud']!.cloudFileId, rows['in-cloud']!.cloudMd5), (false, 'drive-1', 'abc'));
    expect(rows['on-phone']!.hasLocal, isTrue);

    expect(await store.getSetting('sync_media'), '1');
    expect(await store.getSetting('sync_images'), isNull);
    expect(await store.getSetting('user_name'), '小明');

    // The updated app can store a video next to them.
    await store.addVideo('v1');
    expect((await store.mediaRow('v1'))!.kind, MediaKind.video.code);
    final tables = await store.db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get();
    expect(tables.map((r) => r.data['name']), isNot(contains('images')));
  });

  test('a database from before the cloud (no table of images yet) updates too', () async {
    final store = open((raw) {
      for (final sql in [_diaries, _drafts, _settings, _index]) {
        raw.execute(sql);
      }
      raw.execute('PRAGMA user_version = 1');
    });
    addTearDown(store.db.close);
    expect(await store.mediaRows(), isEmpty);
    await store.addImage('i1');
    await store.addVideo('v1');
    expect((await store.mediaRows()).map((r) => r.kind).toSet(), {'image', 'video'});
  });

  test('a new install has the same tables', () async {
    final store = open((raw) {});
    addTearDown(store.db.close);
    await store.addVideo('v1');
    expect((await store.mediaRow('v1'))!.hasLocal, isTrue);
  });
}
