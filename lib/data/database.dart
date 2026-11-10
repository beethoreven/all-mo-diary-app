import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// The local database. Diaries always live on the phone first; cloud sync comes later (spec §8).
///
/// - A diary has a UUID and a last-modified stamp; deleting marks it (a tombstone) so a later
///   sync can't bring it back from another phone (mama-fufood's lesson).
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

  /// The body's plain text, kept for search (spec §5) so search never parses JSON.
  TextColumn get bodyPlain => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// Changed since the last upload (for cloud sync later).
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Unsaved writing, kept every few seconds so a killed app loses nothing (spec §6, auto draft).
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

@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Diaries, Drafts, Settings])
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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // One live diary per day (spec §2). Deleted ones stay as tombstones and don't count.
          await customStatement('CREATE UNIQUE INDEX diaries_one_per_day ON diaries (day) WHERE deleted = 0');
        },
      );
}
