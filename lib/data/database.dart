import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// The local database. Diaries always live on the phone first; the cloud holds a copy when sync is on.
///
/// - A diary has a UUID and a last-modified stamp; deleting marks it (a tombstone) so a later
///   sync can't bring it back from another phone.
/// - The file is files/db/diary.sqlite. Android auto-backup only backs up that folder
///   (android/app/src/main/res/xml/); images are too big for its 25 MB cap.

/// One diary. At most one live (not deleted) diary per day: a partial unique index enforces it.
@DataClassName('DiaryRow')
class Diaries extends Table {
  TextColumn get id => text()();

  /// The day it belongs to, 2026-11-10 (Taiwan calendar day).
  TextColumn get day => text()();
  TextColumn get title => text()();

  /// The body as a Quill Delta (JSON). Images are embeds that name a file in files/images/.
  TextColumn get body => text()();

  /// The body's plain text, kept for search so search never parses JSON.
  TextColumn get bodyPlain => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// Changed since the last upload (for cloud sync later).
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Unsaved writing, kept every few seconds so a killed app loses nothing.
/// Never synced, never shown on the calendar.
@DataClassName('DraftRow')
class Drafts extends Table {
  /// 'new:2026-11-10' for a new diary, 'edit:' + the diary id for editing an existing one.
  TextColumn get key => text()();
  TextColumn get diaryId => text().nullable()();
  TextColumn get day => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Where each diary image is: the file `files/images/<id>.jpg` on the phone, a copy in the
/// user's Drive folder 「全心日記/圖片」, or both. With 「圖片存到雲端」 on, the phone's copy is deleted
/// once the cloud copy's MD5 matches; showing it later downloads it to the cache.
@DataClassName('ImageRow')
class Images extends Table {
  TextColumn get id => text()();
  BoolColumn get hasLocal => boolean().withDefault(const Constant(true))();
  TextColumn get cloudFileId => text().nullable()();
  TextColumn get cloudMd5 => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Diaries, Drafts, Settings, Images])
class AppDb extends _$AppDb {
  AppDb(super.e);

  factory AppDb.open() => AppDb(driftDatabase(
        name: 'diary',
        native: DriftNativeOptions(databasePath: () async {
          final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'db'));
          await dir.create(recursive: true);
          return p.join(dir.path, 'diary.sqlite');
        }),
      ));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // One live diary per day. Deleted ones stay as tombstones and don't count.
          await customStatement('CREATE UNIQUE INDEX diaries_one_per_day ON diaries (day) WHERE deleted = 0');
        },
        onUpgrade: (m, from, to) async {
          // Version 2 (cloud): the images table. Existing image files get rows on first use
          // (Store.adoptImageFiles), so nothing written by version 1 is lost.
          if (from < 2) await m.createTable(images);
        },
      );
}
