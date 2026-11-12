import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:allmodiary/app.dart';
import 'package:allmodiary/core/time.dart';
import 'package:allmodiary/data/database.dart';
import 'package:allmodiary/data/store.dart';
import 'package:allmodiary/domain/diary.dart';
import 'package:allmodiary/services/api_client.dart';
import 'package:allmodiary/services/auth_service.dart';
import 'package:allmodiary/services/diagnostics.dart';
import 'package:allmodiary/services/sync_engine.dart';
import 'package:allmodiary/state/providers.dart';
import 'package:allmodiary/ui/editor/toolbar.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'services/fake_cloud.dart';

/// "Now" in tests: 2026-11-11 12:00 in Taipei, whatever the computer's time zone.
final fixedNow = DateTime.utc(2026, 11, 11, 4);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory images;

  setUp(() {
    GoogleSignInPlatform.instance = _NoGooglePlatform();
    TimeRules.now = () => fixedNow;
    images = Directory.systemTemp.createTempSync('amd_ui_');
  });

  tearDown(() {
    TimeRules.now = DateTime.now;
    images.deleteSync(recursive: true);
  });

  Future<Store> pumpApp(
    WidgetTester tester, {
    String? name = '小明',
    List<DiaryInput> diaries = const [],
    bool signedIn = false,
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = Store(AppDb(NativeDatabase.memory()), imagesDir: images);
    final auth = AuthService(StoreAuthStorage(store));
    await tester.runAsync(() async {
      if (name != null) await store.setSetting(Keys.userName, name);
      for (final d in diaries) {
        await store.save(d);
      }
      if (signedIn) {
        await store.setSetting('auth_user', jsonEncode({'sub': 'u1', 'email': 'me@example.com', 'name': '小明'}));
      }
      await auth.init();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          authServiceProvider.overrideWithValue(auth),
          diagnosticsProvider.overrideWithValue(Diagnostics(store)..noBackupDir = images.path),
          // No backend in UI tests: the daily check and feedback stay off the network.
          apiClientProvider.overrideWithValue(ApiClient(baseUrl: '')),
          ...overrides,
        ],
        child: const AllMoDiaryApp(),
      ),
    );
    await settle(tester);
    return store;
  }

  appTest('first launch asks for a name, then shows「名字的日記」and the tabs', (tester) async {
    await pumpApp(tester, name: null);
    expect(find.text('設定名字'), findsOneWidget);
    // Start fresh, or bring earlier diaries back.
    expect(find.text('從匯出檔匯入'), findsOneWidget);
    expect(find.text('從雲端取回'), findsOneWidget);
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
    final store = await pumpApp(
      tester,
      diaries: [DiaryInput(day: const Day(2026, 11, 5), title: '要刪的', body: DiaryBody.empty)],
    );
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
    await pumpApp(
      tester,
      diaries: [
        DiaryInput(day: const Day(2026, 11, 9), title: 'An Apple', body: DiaryBody.empty),
        DiaryInput(day: const Day(2026, 11, 2), title: 'apple pie', body: DiaryBody.empty),
      ],
    );
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
    await pumpApp(
      tester,
      diaries: [DiaryInput(day: const Day(2026, 3, 1), title: '三月', body: DiaryBody.empty)],
    );
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

  appTest('signed out shows the Google sign-in button', (tester) async {
    await pumpApp(tester);
    expect(find.byTooltip('用 Google 帳號登入'), findsOneWidget);
  });

  appTest('a remembered account is signed in on launch (restart test at the UI level)', (tester) async {
    await pumpApp(tester, signedIn: true);
    expect(find.byTooltip('用 Google 帳號登入'), findsNothing);
    expect(find.byTooltip('me@example.com'), findsOneWidget);
    expect((GoogleSignInPlatform.instance as _NoGooglePlatform).lightweightCalls, 0);
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

  appTest('an export still running after leaving the page: opened again, it shows that and offers no second run',
      (tester) async {
    await pumpApp(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(AllMoDiaryApp)), listen: false);
    final service = container.read(exportServiceProvider);
    expect(service.begin('正在匯出，請勿關閉 App'), isTrue); // started on an earlier visit to the page
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await settle(tester);
    await tester.tap(find.text('匯入/匯出'));
    // A spinner is showing, so no pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    Finder button(String label) =>
        find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
    expect(find.text('正在匯出，請勿關閉 App…'), findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(button('匯出')).onPressed, isNull);
    expect(tester.widget<ButtonStyleButton>(button('匯入')).onPressed, isNull);
    expect(service.begin('正在讀取匯出檔'), isFalse, reason: 'one export or import at a time');
    service.end();
    await tester.pump();
    expect(tester.widget<ButtonStyleButton>(button('匯出')).onPressed, isNotNull);
  });

  Override syncWith(FakeCloud cloud) => syncEngineProvider.overrideWith((ref) {
        final engine = SyncEngine(
            store: ref.watch(storeProvider), auth: ref.watch(authServiceProvider), cloud: ({required interactive}) => cloud);
        ref.onDispose(engine.dispose);
        return engine;
      });

  appTest('first launch → 從雲端取回: the name and the diaries come back, then the main screen opens', (tester) async {
    GoogleSignInPlatform.instance = FakeGoogle(); // Drive access granted
    final cloud = FakeCloud();
    final at = fixedNow.millisecondsSinceEpoch;
    Uint8List json(Object v) => Uint8List.fromList(utf8.encode(jsonEncode(v)));
    await tester.runAsync(() async {
      await cloud.createAppData('amd_profile.json', json({'v': 1, 'user_name': '小美'}), props: {'u': '$at'});
      await cloud.createAppData(
          'amd_diary_d1.json',
          json({'v': 1, 'id': 'd1', 'day': '2026-11-10', 'title': '雲端的日記', 'body': DiaryBody.empty,
            'created_at': at, 'updated_at': at, 'deleted': false}),
          props: {'u': '$at', 'd': '0', 'day': '2026-11-10'});
    });
    final store = await pumpApp(tester, name: null, signedIn: true, overrides: [syncWith(cloud)]);
    await tester.tap(find.text('從雲端取回'));
    await settle(tester);
    expect(find.text('小美的日記'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^2026/11/10（二），有日記$')), findsOneWidget);
    expect(await tester.runAsync(() => store.getSetting(SyncKeys.diaries)), '1', reason: 'sync stays on');
  });

  appTest('first launch → 從雲端取回 with nothing in the cloud: says so and stays on the first page', (tester) async {
    GoogleSignInPlatform.instance = FakeGoogle();
    await pumpApp(tester, name: null, signedIn: true, overrides: [syncWith(FakeCloud())]);
    await tester.tap(find.text('從雲端取回'));
    await settle(tester);
    expect(find.textContaining('雲端上沒有找到之前同步的日記'), findsOneWidget);
    await tester.tap(find.text('好'));
    await settle(tester);
    expect(find.text('設定名字'), findsOneWidget);
  });
}

/// testWidgets plus the drift clean-up: drift schedules a zero-length timer when its streams are
/// cancelled, so the app is unmounted and that timer run inside the test, then the database closed.
void appTest(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    await body(tester);
    final store = ProviderScope.containerOf(tester.element(find.byType(AllMoDiaryApp)), listen: false).read(storeProvider);
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
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

/// No real Google in tests; counts silent sign-in attempts, which the app must never make on launch.
class _NoGooglePlatform extends GoogleSignInPlatform with MockPlatformInterfaceMixin {
  int lightweightCalls = 0;

  @override
  Future<void> init(InitParameters params) async {}

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(AttemptLightweightAuthenticationParameters params) {
    lightweightCalls++;
    return Future.value(null);
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) => throw UnimplementedError();

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async => null;

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async => null;

  @override
  Future<void> clearAuthorizationToken(ClearAuthorizationTokenParams params) async {}

  @override
  Future<void> signOut(SignOutParams params) async {}

  @override
  Future<void> disconnect(DisconnectParams params) async {}
}
