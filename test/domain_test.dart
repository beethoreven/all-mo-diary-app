import 'dart:convert';
import 'dart:ui' as ui;

import 'package:allmodiary/core/text.dart';
import 'package:allmodiary/core/time.dart';
import 'package:allmodiary/domain/calendar.dart';
import 'package:allmodiary/domain/diary.dart';
import 'package:allmodiary/domain/search.dart';
import 'package:allmodiary/domain/trim.dart';
import 'package:allmodiary/services/image_service.dart';
import 'package:allmodiary/services/video_service.dart';
import 'package:flutter_test/flutter_test.dart';

Diary diary(String day, String title, String plain) => Diary(
      id: day,
      day: Day.parse(day),
      title: title,
      body: DiaryBody.empty,
      bodyPlain: plain,
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  group('Day', () {
    test('label is 2026/11/10（二）', () {
      expect(const Day(2026, 11, 10).label, '2026/11/10（二）');
      expect(const Day(2026, 1, 4).label, '2026/01/04（日）');
    });

    test('today is the Taiwan date whatever the phone time zone', () {
      // 2026-11-10 17:30 UTC is already 11-11 01:30 in Taipei.
      TimeRules.now = () => DateTime.utc(2026, 11, 10, 17, 30);
      addTearDown(() => TimeRules.now = DateTime.now);
      expect(TimeRules.today(), const Day(2026, 11, 11));
    });
  });

  test('month grid starts on Monday or Sunday', () {
    // 2026-11-01 is a Sunday.
    expect(monthGrid(2026, 11, weekStartsMonday: true).first.indexOf(const Day(2026, 11, 1)), 6);
    expect(monthGrid(2026, 11, weekStartsMonday: false).first.first, const Day(2026, 11, 1));
  });

  group('DiaryBody', () {
    const body = '[{"insert":"Hello "},{"insert":"World","attributes":{"bold":true}},{"insert":"\\n"},'
        '{"insert":{"diary_image":"{\\"id\\":\\"img1\\",\\"w\\":10,\\"h\\":20}"}},{"insert":"bye\\n"}]';

    test('plain text skips images and the closing newline', () {
      expect(DiaryBody.plainText(body), 'Hello World\nbye');
    });

    test('finds image ids', () {
      expect(DiaryBody.imageIds(body), {'img1'});
    });

    test('content check', () {
      expect(DiaryBody.hasContent(DiaryBody.empty), isFalse);
      expect(DiaryBody.hasContent('[{"insert":"  \\n"}]'), isFalse);
      expect(DiaryBody.hasContent(body), isTrue);
    });

    test('a broken body reads as empty instead of throwing', () {
      expect(DiaryBody.plainText('not json'), '');
      expect(DiaryBody.imageIds('{"x":1}'), isEmpty);
    });
  });

  group('search', () {
    final diaries = [
      diary('2026-11-03', 'An Apple a day', 'nothing here'),
      diary('2026-11-01', 'Rainy', 'I ate an apple pie'),
      diary('2026-11-02', 'AnApple', 'joined words'),
    ];

    test('ignores case, trims the ends, keeps the middle space, oldest first', () {
      final found = searchDiaries(diaries, '  an APPLE ', SearchScope.all)!;
      expect(found.map((d) => d.day.toString()), ['2026-11-01', '2026-11-03']);
    });

    test('scope title / body', () {
      expect(searchDiaries(diaries, 'apple', SearchScope.title)!.map((d) => d.title), ['AnApple', 'An Apple a day']);
      expect(searchDiaries(diaries, 'apple', SearchScope.body)!.map((d) => d.title), ['Rainy']);
    });

    test('blank query means "ask for text", not "everything"', () {
      expect(searchDiaries(diaries, '   ', SearchScope.all), isNull);
    });
  });

  test('filter prefixes', () {
    expect(const DayFilter(year: 2026).prefix, '2026-');
    expect(const DayFilter(year: 2026, month: 3).prefix, '2026-03-');
    expect(const DayFilter(year: 2026, month: 3, day: 9).prefix, '2026-03-09');
  });

  test('text rules count an emoji as one character and drop control characters', () {
    expect(TextRules.length('日記👨‍👩‍👧'), 3);
    expect(TextRules.clean(' a\nb\tc '), 'abc');
  });

  group('image target size', () {
    const screen = ui.Size(1080, 2400);

    test('height is a third of the screen, ratio kept', () {
      expect(ImageService.targetSize(4000, 3000, screen), (width: 1067, height: 800));
    });

    test('too wide → width is the screen width', () {
      expect(ImageService.targetSize(8000, 2000, screen), (width: 1080, height: 270));
    });

    test('a small picture is not enlarged', () {
      expect(ImageService.targetSize(300, 200, screen), (width: 300, height: 200));
    });
  });

  group('video', () {
    const screen = ui.Size(1080, 2400);
    const ref = VideoRef(id: 'v1', coverId: 'c1', width: 1080, height: 608, durationMs: 83000);
    String bodyWith(String embedType, String data) => jsonEncode([
          {'insert': '前\n'},
          {'insert': {embedType: data}},
          {'insert': '\n'},
        ]);

    test('a video embed round-trips, and a broken one is ignored', () {
      final back = VideoRef.tryParse(ref.encode())!;
      expect((back.id, back.coverId, back.width, back.height, back.durationMs), ('v1', 'c1', 1080, 608, 83000));
      expect(VideoRef.tryParse('not json'), isNull);
      expect(VideoRef.tryParse('{"id":"v","cover":"c","w":0,"h":10,"ms":1}'), isNull, reason: 'a size of 0 can\'t be drawn');
      expect(VideoRef.tryParse('{"id":"v","w":10,"h":10,"ms":1}'), isNull, reason: 'no cover');
    });

    test('an id that could not be a file name is refused (ids become part of a file path)', () {
      for (final bad in ['../../db/diary', 'a/b', r'a\b', '', 'a.b', 'x' * 65, 'id with space']) {
        expect(DiaryBody.isFileId(bad), isFalse, reason: bad);
        expect(ImageRef.tryParse(ImageRef(bad, 10, 10).encode()), isNull, reason: bad);
        expect(VideoRef.tryParse(VideoRef(id: bad, coverId: 'c', width: 1, height: 1, durationMs: 1).encode()), isNull);
        expect(VideoRef.tryParse(VideoRef(id: 'v', coverId: bad, width: 1, height: 1, durationMs: 1).encode()), isNull);
      }
      // What the app generates (a UUID) and what older tests use.
      expect(DiaryBody.isFileId('3f2a9c1e-7b4d-4e1a-9c3b-5d6e7f809a1b'), isTrue);
      expect(ImageRef.tryParse(const ImageRef('kept', 10, 10).encode()), isNotNull);
      expect(ImageRef.tryParse(const ImageRef('kept', 0, 10).encode()), isNull, reason: 'a size of 0 can\'t be drawn');
    });

    test('a body with a video needs the video and its cover; the cover counts as an image', () {
      final body = bodyWith(DiaryBody.videoType, ref.encode());
      expect(DiaryBody.videoIds(body), {'v1'});
      expect(DiaryBody.imageIds(body), {'c1'});
      expect(DiaryBody.mediaIds(body), {'v1', 'c1'});
      expect(DiaryBody.plainText(body), '前\n');
      final onlyVideo = jsonEncode([
        {'insert': {DiaryBody.videoType: ref.encode()}},
        {'insert': '\n'},
      ]);
      expect(DiaryBody.hasContent(onlyVideo), isTrue);
      expect(DiaryBody.hasContent(DiaryBody.empty), isFalse);
    });

    test('stored like an image would be: a third of the screen tall, or screen-wide; even height; never enlarged', () {
      // 1920×1080 → 1080×608 (screen-wide).
      expect(VideoService.target(1920, 1080, screen).height, 608);
      // Upright 1080×1920 → 450×800.
      expect(VideoService.target(1080, 1920, screen).height, 800);
      // 300×201 stays as it is, but encoders need an even height.
      expect(VideoService.target(300, 201, screen).height, 200);
    });

    test('bitrate follows the stored size, with a floor', () {
      expect(VideoService.target(1920, 1080, screen).bitrate, closeTo(1970000, 20000));
      expect(VideoService.target(1080, 1920, screen).bitrate, closeTo(1080000, 20000));
      expect(VideoService.target(320, 240, screen).bitrate, 400000);
    });

    test('only a video longer than two minutes needs trimming', () {
      PickedVideo of(int ms) => PickedVideo(uri: 'content://x', durationMs: ms, width: 10, height: 10);
      expect(of(120000).needsTrim, isFalse);
      expect(of(120001).needsTrim, isTrue);
    });

    test('lengths read as minutes:seconds', () {
      expect(clockText(0), '0:00');
      expect(clockText(65400), '1:05');
      expect(clockText(120000), '2:00');
      expect(clockText(754000), '12:34');
    });
  });

  group('trim window', () {
    const minute = 60000;

    test('starts as the first two minutes', () {
      final w = TrimWindow.initial(10 * minute);
      expect((w.startMs, w.endMs), (0, 2 * minute));
    });

    test('moving the start later shortens the part; earlier than two minutes before the end drags the end along', () {
      var w = TrimWindow.initial(10 * minute).withEnd(6 * minute);
      expect((w.startMs, w.endMs), (4 * minute, 6 * minute));
      w = w.withStart(5 * minute);
      expect((w.startMs, w.endMs), (5 * minute, 6 * minute));
      w = w.withStart(1 * minute);
      expect((w.startMs, w.endMs), (1 * minute, 3 * minute));
    });

    test('moving the end past two minutes drags the start along', () {
      final w = TrimWindow.initial(10 * minute).withEnd(9 * minute);
      expect((w.startMs, w.endMs), (7 * minute, 9 * minute));
    });

    test('never shorter than a second, never outside the video', () {
      var w = TrimWindow.initial(10 * minute).withStart(2 * minute);
      expect(w.lengthMs, 1000);
      expect((w.startMs, w.endMs), (2 * minute - 1000 + 1000, 2 * minute + 1000));
      w = TrimWindow.initial(10 * minute).withStart(20 * minute);
      expect((w.startMs, w.endMs), (10 * minute - 1000, 10 * minute));
      w = TrimWindow.initial(10 * minute).withEnd(-5);
      expect((w.startMs, w.endMs), (0, 1000));
      w = TrimWindow.initial(10 * minute).withEnd(99 * minute);
      expect((w.startMs, w.endMs), (8 * minute, 10 * minute));
    });
  });
}
