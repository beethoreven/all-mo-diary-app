import 'dart:io';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../core/text.dart';
import '../core/time.dart';
import '../domain/diary.dart';
import '../domain/search.dart';
import 'database.dart';

/// Setting keys.
abstract final class Keys {
  static const userName = 'user_name';
  static const weekStart = 'week_start'; // 'monday' (default) | 'sunday'
  static const theme = 'theme'; // 'system' (default) | 'light' | 'dark'
}

/// A user-facing reason a save was refused.
class InputProblem implements Exception {
  const InputProblem(this.message);

  final String message;

  @override
  String toString() => message;
}

/// All reads and writes of local data go through here.
class Store {
  Store(this.db, {required this.imagesDir});

  final AppDb db;

  /// files/images/: one JPEG per image id.
  final Directory imagesDir;

  static const _uuid = Uuid();

  static String newId() => _uuid.v4();

  // ── Settings ───────────────────────────────────────────────

  Stream<Map<String, String>> watchSettings() =>
      db.select(db.settings).watch().map((rows) => {for (final r in rows) r.key: r.value});

  Future<String?> getSetting(String key) async =>
      (await (db.select(db.settings)..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setSetting(String key, String value) =>
      db.into(db.settings).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));

  // ── Diaries ────────────────────────────────────────────────

  Diary _diary(DiaryRow r) => Diary(
        id: r.id,
        day: Day.parse(r.day),
        title: r.title,
        body: r.body,
        bodyPlain: r.bodyPlain,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
      );

  SimpleSelectStatement<$DiariesTable, DiaryRow> _alive() =>
      db.select(db.diaries)..where((t) => t.deleted.equals(false));

  /// Live diaries whose day starts with [prefix] ('2026-', '2026-11-', '2026-11-10'), oldest first.
  Stream<List<Diary>> watchPrefix(String prefix) => (_alive()
        ..where((t) => t.day.like('$prefix%'))
        ..orderBy([(t) => OrderingTerm.asc(t.day)]))
      .watch()
      .map((rows) => rows.map(_diary).toList());

  Stream<List<Diary>> watchMonth(int year, int month) => watchPrefix(DayFilter(year: year, month: month).prefix);

  Stream<List<Diary>> watchAll() =>
      (_alive()..orderBy([(t) => OrderingTerm.asc(t.day)])).watch().map((rows) => rows.map(_diary).toList());

  Stream<Diary?> watchById(String id) =>
      (_alive()..where((t) => t.id.equals(id))).watchSingleOrNull().map((r) => r == null ? null : _diary(r));

  Future<Diary?> byId(String id) async {
    final r = await (_alive()..where((t) => t.id.equals(id))).getSingleOrNull();
    return r == null ? null : _diary(r);
  }

  Future<Diary?> diaryOn(Day day) async {
    final r = await (_alive()..where((t) => t.day.equals(day.toString()))).getSingleOrNull();
    return r == null ? null : _diary(r);
  }

  /// Saves a new or edited diary and drops its draft. Throws [InputProblem] when the title is
  /// missing or too long, or another diary already has that day (spec §2, §6).
  Future<Diary> save(DiaryInput input, {String? draftKey}) async {
    final title = TextRules.clean(input.title);
    if (title.isEmpty) throw const InputProblem('請輸入標題');
    if (TextRules.length(title) > Limits.titleMaxChars) {
      throw const InputProblem('標題最多 ${Limits.titleMaxChars} 個字');
    }
    final now = TimeRules.nowMs();
    final id = input.id ?? newId();
    await db.transaction(() async {
      final other = await diaryOn(input.day);
      if (other != null && other.id != id) throw const InputProblem('這天已經有日記了');
      final plain = DiaryBody.plainText(input.body);
      if (input.id == null) {
        await db.into(db.diaries).insert(DiariesCompanion.insert(
              id: id,
              day: input.day.toString(),
              title: title,
              body: input.body,
              bodyPlain: plain,
              createdAt: now,
              updatedAt: now,
            ));
      } else {
        final n = await (db.update(db.diaries)..where((t) => t.id.equals(id) & t.deleted.equals(false))).write(
          DiariesCompanion(
            day: Value(input.day.toString()),
            title: Value(title),
            body: Value(input.body),
            bodyPlain: Value(plain),
            updatedAt: Value(now),
            dirty: const Value(true),
          ),
        );
        if (n == 0) throw const InputProblem('這篇日記已經被刪除了');
      }
      if (draftKey != null) await deleteDraft(draftKey);
    });
    await cleanupImages();
    return (await (db.select(db.diaries)..where((t) => t.id.equals(id))).map(_diary).getSingle());
  }

  /// Deletes a diary: marks it deleted (kept as a tombstone for sync) and removes its images.
  Future<void> delete(String id) async {
    await (db.update(db.diaries)..where((t) => t.id.equals(id))).write(DiariesCompanion(
      deleted: const Value(true),
      dirty: const Value(true),
      updatedAt: Value(TimeRules.nowMs()),
      body: const Value(DiaryBody.empty),
      bodyPlain: const Value(''),
    ));
    await deleteDraft('edit:$id');
    await cleanupImages();
  }

  // ── Drafts ─────────────────────────────────────────────────

  static String newDraftKey(Day day) => 'new:$day';

  static String editDraftKey(String diaryId) => 'edit:$diaryId';

  Future<void> saveDraft({required String key, String? diaryId, required Day day, required String title, required String body}) =>
      db.into(db.drafts).insertOnConflictUpdate(DraftsCompanion.insert(
            key: key,
            diaryId: Value(diaryId),
            day: day.toString(),
            title: title,
            body: body,
            updatedAt: TimeRules.nowMs(),
          ));

  Future<DraftRow?> draft(String key) => (db.select(db.drafts)..where((t) => t.key.equals(key))).getSingleOrNull();

  Future<List<DraftRow>> drafts() => (db.select(db.drafts)..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).get();

  Future<void> deleteDraft(String key) => (db.delete(db.drafts)..where((t) => t.key.equals(key))).go();

  // ── Images ─────────────────────────────────────────────────

  File imageFile(String id) => File('${imagesDir.path}/$id.jpg');

  /// Deletes image files no live diary or draft refers to. Files touched in the last minute are
  /// kept: the editor may hold a just-picked image that isn't in a draft yet.
  Future<void> cleanupImages() async {
    if (!await imagesDir.exists()) return;
    final used = <String>{};
    for (final r in await _alive().get()) {
      used.addAll(DiaryBody.imageIds(r.body));
    }
    for (final d in await db.select(db.drafts).get()) {
      used.addAll(DiaryBody.imageIds(d.body));
    }
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    await for (final entity in imagesDir.list()) {
      if (entity is! File || !entity.path.endsWith('.jpg')) continue;
      final id = entity.uri.pathSegments.last.replaceAll('.jpg', '');
      if (used.contains(id)) continue;
      if ((await entity.lastModified()).isAfter(cutoff)) continue;
      await entity.delete();
    }
  }
}
