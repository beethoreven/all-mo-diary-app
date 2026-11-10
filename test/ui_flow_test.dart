import 'dart:io';

import 'package:allmodiary/app.dart';
import 'package:allmodiary/core/time.dart';
import 'package:allmodiary/data/database.dart';
import 'package:allmodiary/data/store.dart';
import 'package:allmodiary/domain/diary.dart';
import 'package:allmodiary/state/providers.dart';
import 'package:allmodiary/ui/editor/toolbar.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Now" in tests: 2026-11-11 12:00 in Taipei, whatever the computer's time zone.
final fixedNow = DateTime.utc(2026, 11, 11, 4);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory images;

  setUp(() {
    TimeRules.now = () => fixedNow;
    images = Directory.systemTemp.createTempSync('amd_ui_');
  });

  tearDown(() {
    TimeRules.now = DateTime.now;
    images.deleteSync(recursive: true);
  });

  Future<Store> pumpApp(WidgetTester tester, {String? name = '小明', List<DiaryInput> diaries = const []}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = Store(AppDb(NativeDatabase.memory()), imagesDir: images);
    await tester.runAsync(() async {
      if (name != null) await store.setSetting(Keys.userName, name);
      for (final d in diaries) {
        await store.save(d);
      }
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [storeProvider.overrideWithValue(store)],
      child: const DiaryApp(),
    ));
    await settle(tester);
    return store;
  }

  appTest('first launch asks for a name, then shows「名字的日記」and the tabs', (tester) async {
    await pumpApp(tester, name: null);
    expect(find.text('設定名字'), findsOneWidget);
    await tester.tap(find.text('設定名字'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '  小美  ');
    await tester.pump();
    await tester.tap(find.text('確定'));
    await settle(tester);
    expect(find.text('小美的日記'), findsOneWidget);
    for (final tab in ['行事曆', '篩選', '搜尋', '即將推出']) {
      expect(find.text(tab), findsOneWidget);
    }
  });

  appTest('tap an empty day → write → save → view; the calendar shows 日記', (tester) async {
    final store = await pumpApp(tester);
    expect(find.text('日記'), findsNothing);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^2026/11/11（三），沒有日記$')));
    await settle(tester);
    expect(find.text('2026/11/11（三）'), findsOneWidget);
    expect(find.text('儲存'), findsOneWidget);
    expect(find.byType(DiaryToolbar), findsOneWidget);

    // No title → refused.
    await tester.tap(find.text('儲存'));
    await settle(tester);
    expect(find.text('請輸入標題'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '標題'), '下雨天');
    await tester.tap(find.text('儲存'));
    await settle(tester);
    expect(find.text('編輯'), findsOneWidget);
    expect(find.text('刪除'), findsOneWidget);
    expect(find.byType(DiaryToolbar), findsNothing);

    await tester.tap(find.text('返回'));
    await settle(tester);
    expect(find.text('日記'), findsOneWidget);
    final saved = await tester.runAsync(() => store.diaryOn(const Day(2026, 11, 11)));
    expect(saved!.title, '下雨天');
  });

  appTest('cancel with something written asks first', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^2026/11/11')));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, '標題'), 'x');
    await tester.tap(find.text('取消'));
    await settle(tester);
    expect(find.text('要放棄這篇還沒儲存的日記嗎？'), findsOneWidget);
    await tester.tap(find.text('放棄'));
    await settle(tester);
    expect(find.text('小明的日記'), findsOneWidget);
  });

  appTest('delete needs a confirm and then typing 刪除日記', (tester) async {
    final store = await pumpApp(tester, diaries: [
      DiaryInput(day: const Day(2026, 11, 5), title: '要刪的', body: DiaryBody.empty),
    ]);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^2026/11/05（四），有日記$')));
    await settle(tester);
    await tester.tap(find.text('刪除'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, '刪除'));
    await settle(tester);
    final confirm = find.widgetWithText(FilledButton, '刪除');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '刪除日記');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await settle(tester);
    expect(find.text('小明的日記'), findsOneWidget);
    expect(await tester.runAsync(() => store.diaryOn(const Day(2026, 11, 5))), isNull);
  });

  appTest('search: blank asks for text; results list oldest first; nothing → 沒有結果', (tester) async {
    await pumpApp(tester, diaries: [
      DiaryInput(day: const Day(2026, 11, 9), title: 'An Apple', body: DiaryBody.empty),
      DiaryInput(day: const Day(2026, 11, 2), title: 'apple pie', body: DiaryBody.empty),
    ]);
    await tester.tap(find.text('搜尋'));
    await settle(tester);
    await tester.tap(find.byTooltip('搜尋'));
    await settle(tester);
    expect(find.text('請輸入要搜尋的文字'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '搜尋文字'), ' APPLE ');
    await tester.tap(find.byTooltip('搜尋'));
    await settle(tester);
    final first = tester.getTopLeft(find.text('apple pie')).dy;
    final second = tester.getTopLeft(find.text('An Apple')).dy;
    expect(first, lessThan(second));

    await tester.enterText(find.widgetWithText(TextField, '搜尋文字'), 'banana');
    await tester.tap(find.byTooltip('搜尋'));
    await settle(tester);
    expect(find.text('沒有結果'), findsOneWidget);
  });

  appTest('filter tab lists this year by default and shows 沒有結果 for an empty month', (tester) async {
    await pumpApp(tester, diaries: [
      DiaryInput(day: const Day(2026, 3, 1), title: '三月', body: DiaryBody.empty),
    ]);
    await tester.tap(find.text('篩選'));
    await settle(tester);
    // Year, 「月：不指定」 and 「日：不指定」 fit on one line on a 360 dp wide phone.
    final rowY = tester.getCenter(find.text('2026 年').last).dy;
    expect(tester.getCenter(find.text('月：不指定')).dy, rowY);
    expect(tester.getCenter(find.text('日：不指定')).dy, rowY);
    expect(find.text('三月'), findsOneWidget);
    expect(find.text('2026/03/01（日）'), findsOneWidget);
    await tester.tap(find.text('月：不指定'));
    await settle(tester);
    await tester.tap(find.text('4 月'));
    await settle(tester);
    expect(find.text('沒有結果'), findsOneWidget);
  });

  appTest('the ⋮ menu opens the terms and the privacy policy', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('更多'));
    await settle(tester);
    await tester.tap(find.text('隱私權政策'));
    await settle(tester);
    expect(find.textContaining('你寫的日記與圖片只存在你的手機'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await settle(tester);
    await tester.tap(find.byTooltip('更多'));
    await settle(tester);
    await tester.tap(find.text('使用者條款'));
    await settle(tester);
    expect(find.textContaining('歡迎使用「全心日記」'), findsOneWidget);
  });

}

/// testWidgets plus the drift clean-up: drift schedules a zero-length timer when its streams are
/// cancelled, so the app is unmounted and that timer run inside the test, then the database closed.
void appTest(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    await body(tester);
    final store = ProviderScope.containerOf(tester.element(find.byType(DiaryApp)), listen: false).read(storeProvider);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(store.db.close);
  });
}

/// Pumps frames while letting real async work (the database) finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
}
