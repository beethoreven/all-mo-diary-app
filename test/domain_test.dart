import 'dart:ui' as ui;

import 'package:allmodiary/core/text.dart';
import 'package:allmodiary/core/time.dart';
import 'package:allmodiary/domain/calendar.dart';
import 'package:allmodiary/domain/diary.dart';
import 'package:allmodiary/domain/search.dart';
import 'package:allmodiary/services/image_service.dart';
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

  group('search (spec §5)', () {
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

  group('image target size (spec §6.2)', () {
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
}
