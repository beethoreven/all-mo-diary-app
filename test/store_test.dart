import 'dart:convert';
import 'dart:io';

import 'package:allmodiary/core/time.dart';
import 'package:allmodiary/data/database.dart';
import 'package:allmodiary/data/store.dart';
import 'package:allmodiary/domain/diary.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Store store;
  late Directory images;

  setUp(() {
    images = Directory.systemTemp.createTempSync('amd_images_');
    store = Store(AppDb(NativeDatabase.memory()), imagesDir: images);
  });

  tearDown(() async {
    await store.db.close();
    images.deleteSync(recursive: true);
  });

  const nov10 = Day(2026, 11, 10);
  const nov11 = Day(2026, 11, 11);

  DiaryInput input(Day day, String title, {String? id, String body = DiaryBody.empty}) =>
      DiaryInput(id: id, day: day, title: title, body: body);

  test('saves a diary and finds it by day', () async {
    final d = await store.save(input(nov10, '  第一天  '));
    expect(d.title, '第一天');
    expect((await store.diaryOn(nov10))!.id, d.id);
  });

  test('one diary per day', () async {
    await store.save(input(nov10, 'A'));
    expect(() => store.save(input(nov10, 'B')), throwsA(isA<InputProblem>()));
  });

  test('moving a diary onto a day that has one is refused', () async {
    await store.save(input(nov10, 'A'));
    final b = await store.save(input(nov11, 'B'));
    expect(() => store.save(input(nov10, 'B', id: b.id)), throwsA(isA<InputProblem>()));
  });

  test('title is required and at most 20 characters', () async {
    expect(() => store.save(input(nov10, '   ')), throwsA(isA<InputProblem>()));
    expect(() => store.save(input(nov10, '一' * 21)), throwsA(isA<InputProblem>()));
    await store.save(input(nov10, '一' * 20));
  });

  test('deleting frees the day and leaves a tombstone', () async {
    final a = await store.save(input(nov10, 'A'));
    await store.delete(a.id);
    expect(await store.diaryOn(nov10), isNull);
    await store.save(input(nov10, 'again'));
    final rows = await store.db.select(store.db.diaries).get();
    expect(rows.where((r) => r.deleted), hasLength(1));
  });

  test('saving drops the draft', () async {
    final key = Store.newDraftKey(nov10);
    await store.saveDraft(key: key, day: nov10, title: 't', body: DiaryBody.empty);
    expect(await store.draft(key), isNotNull);
    await store.save(input(nov10, 't'), draftKey: key);
    expect(await store.draft(key), isNull);
  });

  test('month and prefix queries are oldest first', () async {
    await store.save(input(nov11, 'B'));
    await store.save(input(nov10, 'A'));
    await store.save(input(const Day(2026, 12, 1), 'C'));
    final month = await store.watchMonth(2026, 11).first;
    expect(month.map((d) => d.title), ['A', 'B']);
    final year = await store.watchPrefix('2026-').first;
    expect(year.map((d) => d.title), ['A', 'B', 'C']);
  });

  test('image cleanup keeps referenced and fresh files, deletes old orphans', () async {
    File img(String id, {bool old = true}) {
      final f = store.imageFile(id)..writeAsBytesSync([1, 2, 3]);
      if (old) f.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
      return f;
    }

    final kept = img('kept');
    final orphan = img('orphan');
    final fresh = img('fresh', old: false);
    final inDraft = img('draft');
    final body = '[{"insert":{"diary_image":"${const ImageRef('kept', 1, 1).encode().replaceAll('"', r'\"')}"}},{"insert":"\\n"}]';
    final draftBody = body.replaceAll('kept', 'draft');
    await store.saveDraft(key: 'new:2026-11-12', day: const Day(2026, 11, 12), title: '', body: draftBody);
    // Saving runs the cleanup too.
    await store.save(input(nov10, 'with image', body: body));
    expect(kept.existsSync(), isTrue);
    expect(inDraft.existsSync(), isTrue);
    expect(fresh.existsSync(), isTrue);
    expect(orphan.existsSync(), isFalse);
  });

  test('video cleanup: a used video and its cover stay, an unused video goes, a half-made one is left alone', () async {
    final old = DateTime.now().subtract(const Duration(hours: 2));
    File aged(File f, {DateTime? at}) {
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync([1, 2, 3]);
      f.setLastModifiedSync(at ?? old);
      return f;
    }

    final used = aged(store.videoFile('v-used')), cover = aged(store.imageFile('c-used'));
    final orphan = aged(store.videoFile('v-orphan'));
    final working = aged(File('${store.videoFile('v-new').path}.part'), at: DateTime.now());
    final abandoned = aged(File('${store.videoFile('v-dead').path}.part'));
    await store.addVideo('v-used');
    await store.addVideo('v-orphan');
    const ref = VideoRef(id: 'v-used', coverId: 'c-used', width: 10, height: 10, durationMs: 1000);
    final body = jsonEncode([
      {'insert': {DiaryBody.videoType: ref.encode()}},
      {'insert': '\n'},
    ]);
    final d = await store.save(input(nov10, 'with video', body: body));
    expect(used.existsSync(), isTrue);
    expect(cover.existsSync(), isTrue);
    expect(orphan.existsSync(), isFalse);
    expect(await store.mediaRow('v-orphan'), isNull);
    expect(working.existsSync(), isTrue, reason: 'a video being shrunk right now');
    expect(abandoned.existsSync(), isFalse, reason: 'left by an app closed while shrinking');

    await store.delete(d.id);
    expect(used.existsSync(), isFalse);
    expect(cover.existsSync(), isFalse);
    expect(await store.counts(), containsPair('videos', 0));
  });

  test('deleting a diary removes its images (once old enough)', () async {
    final f = store.imageFile('x')..writeAsBytesSync([1]);
    f.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
    final body = '[{"insert":{"diary_image":"${const ImageRef('x', 1, 1).encode().replaceAll('"', r'\"')}"}},{"insert":"\\n"}]';
    final d = await store.save(input(nov10, 'img', body: body));
    expect(f.existsSync(), isTrue);
    await store.delete(d.id);
    expect(f.existsSync(), isFalse);
  });
}
