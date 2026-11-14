import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:allmodiary/app.dart';
import 'package:allmodiary/core/time.dart';
import 'package:allmodiary/data/database.dart';
import 'package:allmodiary/data/store.dart';
import 'package:allmodiary/domain/diary.dart';
import 'package:allmodiary/services/api_client.dart';
import 'package:allmodiary/services/auth_service.dart';
import 'package:allmodiary/services/diagnostics.dart';
import 'package:allmodiary/services/sync_engine.dart';
import 'package:allmodiary/services/video_service.dart';
import 'package:allmodiary/state/providers.dart';
import 'package:allmodiary/ui/editor/toolbar.dart';
import 'package:allmodiary/ui/editor/video_player_page.dart';
import 'package:allmodiary/ui/editor/video_trim_page.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'fake_video_player.dart';
import 'services/fake_cloud.dart';
import 'services/fake_video.dart';

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
    expect(find.textContaining('你寫的日記、圖片與影片只存在你的手機'), findsOneWidget);
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

  group('videos', () {
    late FakeVideoPlatform phone;
    late FakeVideoPlayerPlatform player;
    const short = PickedVideo(uri: 'content://picker/short', durationMs: 83000, width: 1920, height: 1080);
    const long = PickedVideo(uri: 'content://picker/long', durationMs: 600000, width: 1920, height: 1080);

    setUp(() {
      phone = FakeVideoPlatform();
      player = FakeVideoPlayerPlatform();
      VideoPlayerPlatform.instance = player;
    });

    Override videosWith() =>
        videoServiceProvider.overrideWith((ref) => VideoService(ref.watch(storeProvider), platform: phone));

    /// The toolbar is one row that scrolls sideways; 「加上影片」 is near its end.
    Future<void> tapAddVideo(WidgetTester tester) async {
      final button = find.byIcon(Icons.videocam_outlined);
      await tester.scrollUntilVisible(button, 120,
          scrollable: find.descendant(of: find.byType(DiaryToolbar), matching: find.byType(Scrollable)));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await settle(tester);
    }

    /// Opens a new diary for 11/11 and presses 「加上影片」.
    Future<Store> pressAddVideo(WidgetTester tester) async {
      final store = await pumpApp(tester, overrides: [videosWith()]);
      await tester.tap(find.bySemanticsLabel(RegExp(r'^2026/11/11（三），沒有日記$')));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, '標題'), '有影片的一天');
      await tapAddVideo(tester);
      return store;
    }

    Future<String> savedBody(WidgetTester tester, Store store) async =>
        (await tester.runAsync(() => store.diaryOn(const Day(2026, 11, 11))))!.body;

    appTest('a video of two minutes or less is shrunk right away and shows as its cover with its length', (tester) async {
      phone.picked = short;
      final store = await pressAddVideo(tester);
      expect(find.byType(VideoTrimPage), findsNothing);
      expect(find.text('正在處理影片'), findsNothing, reason: 'the dialog closes when the work is done');
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('1:23'), findsOneWidget);
      expect((phone.startMs, phone.endMs, phone.height), (null, null, 608));

      await tester.tap(find.text('儲存'));
      await settle(tester);
      expect(find.text('編輯'), findsOneWidget);
      expect(find.text('1:23'), findsOneWidget, reason: 'still there when viewing');
      final body = await savedBody(tester, store);
      final id = DiaryBody.videoIds(body).single;
      expect(await tester.runAsync(() => store.videoFile(id).exists()), isTrue);
      expect(await tester.runAsync(() => store.imageFile(DiaryBody.imageIds(body).single).exists()), isTrue);
    });

    appTest('a longer video goes through the trim screen; the chosen part is what gets stored', (tester) async {
      phone.picked = long;
      final store = await pumpApp(tester, overrides: [videosWith()]);
      await tester.tap(find.bySemanticsLabel(RegExp(r'^2026/11/11（三），沒有日記$')));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, '標題'), '長影片');
      await tapAddVideo(tester);

      expect(find.byType(VideoTrimPage), findsOneWidget);
      expect(find.textContaining('這段影片長 10:00，日記裡的影片最長 2:00'), findsOneWidget);
      expect(find.text('留下的長度：2:00'), findsOneWidget);
      expect(phone.out, isNull, reason: 'nothing is shrunk before the part is chosen');
      expect(player.opened.single.uri, 'content://picker/long', reason: 'the preview plays the original where it is');

      // One second later at both ends: start first (the part gets shorter), then the end.
      await tester.tap(find.byTooltip('開始往後 1 秒'));
      await tester.pump();
      expect(find.text('留下的長度：1:59'), findsOneWidget);
      await tester.tap(find.byTooltip('結束往後 1 秒'));
      await tester.pump();
      expect(find.text('留下的長度：2:00'), findsOneWidget);
      await tester.tap(find.text('確定'));
      await settle(tester);

      expect(find.byType(VideoTrimPage), findsNothing);
      expect((phone.startMs, phone.endMs), (1000, 121000));
      expect(find.text('2:00'), findsOneWidget);
      await tester.tap(find.text('儲存'));
      await settle(tester);
      expect(DiaryBody.videoIds(await savedBody(tester, store)), hasLength(1));
    });

    appTest('backing out of the trim screen adds nothing', (tester) async {
      phone.picked = long;
      await pressAddVideo(tester);
      await tester.tap(find.descendant(of: find.byType(VideoTrimPage), matching: find.text('取消')));
      await settle(tester);
      expect(find.byType(VideoTrimPage), findsNothing);
      expect(phone.out, isNull);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      expect(find.text('儲存'), findsOneWidget, reason: 'back in the editor');
    });

    appTest('the work can be cancelled from its dialog, and then nothing is added', (tester) async {
      phone
        ..picked = short
        ..hold = Completer<void>();
      final store = await pressAddVideo(tester);
      expect(find.text('正在處理影片'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      // The buttons behind the dialog are off while it works.
      expect(tester.widget<ButtonStyleButton>(find.widgetWithText(FilledButton, '儲存')).onPressed, isNull);

      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('取消')));
      await settle(tester);
      expect(phone.cancels, 1);
      expect(find.text('正在處理影片'), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      expect(find.text('加入影片沒有成功，請再試一次'), findsNothing, reason: 'cancelling is not a failure');
      expect(tester.widget<ButtonStyleButton>(find.widgetWithText(FilledButton, '儲存')).onPressed, isNotNull);
      expect(await tester.runAsync(() async => (await store.mediaRows()).length), 0);
    });

    appTest('a video the phone can\'t shrink says so and adds nothing', (tester) async {
      phone
        ..picked = short
        ..failWith = const VideoProblem('ERROR_CODE_DECODING_FORMAT_UNSUPPORTED');
      await pressAddVideo(tester);
      expect(find.text('加入影片沒有成功，請再試一次'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      expect(tester.widget<ButtonStyleButton>(find.widgetWithText(FilledButton, '儲存')).onPressed, isNotNull);
    });

    appTest('while an earlier video is still being shrunk, another can\'t be started', (tester) async {
      phone.picked = short;
      final store = await pumpApp(tester, overrides: [videosWith()]);
      final videos = ProviderScope.containerOf(tester.element(find.byType(AllMoDiaryApp)), listen: false)
          .read(videoServiceProvider);
      // As if started from a screen that has since been left.
      phone.hold = Completer<void>();
      Future<VideoRef>? earlier;
      await tester.runAsync(() async {
        earlier = videos.add(short, const Size(1080, 2400));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.tap(find.bySemanticsLabel(RegExp(r'^2026/11/11（三），沒有日記$')));
      await settle(tester);
      await tapAddVideo(tester);
      expect(find.text('上一段影片還在處理，請稍後再試'), findsOneWidget);
      expect(find.text('正在處理影片'), findsNothing);
      phone.hold!.complete();
      await tester.runAsync(() => earlier!);
      expect(await tester.runAsync(() async => (await store.mediaRows()).length), 2);
    });

    appTest('backing out of the picker does nothing', (tester) async {
      phone.picked = null;
      await pressAddVideo(tester);
      expect(phone.out, isNull);
      expect(find.text('正在處理影片'), findsNothing);
      expect(tester.widget<ButtonStyleButton>(find.widgetWithText(FilledButton, '儲存')).onPressed, isNotNull);
    });

    /// A saved diary for 11/10 holding one video whose files are on the phone.
    Future<(Store, VideoRef)> pumpWithVideoDiary(WidgetTester tester) async {
      const ref = VideoRef(id: 'v1', coverId: 'c1', width: 1080, height: 608, durationMs: 4000);
      final body = jsonEncode([
        {'insert': '看影片\n'},
        {'insert': {DiaryBody.videoType: ref.encode()}},
        {'insert': '\n'},
      ]);
      final store = await pumpApp(tester,
          diaries: [DiaryInput(day: const Day(2026, 11, 10), title: '有影片', body: body)], overrides: [videosWith()]);
      await tester.runAsync(() async {
        await store.videoFile(ref.id).create(recursive: true);
        await store.imageFile(ref.coverId).create(recursive: true);
        await store.addVideo(ref.id);
        await store.addImage(ref.coverId);
      });
      await tester.tap(find.bySemanticsLabel(RegExp(r'^2026/11/10（二），有日記$')));
      await settle(tester);
      return (store, ref);
    }

    appTest('tapping the cover plays the video over the whole screen; the screen may turn, and stays on', (tester) async {
      final orientations = <List<String>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientations.add((call.arguments as List).cast<String>());
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final (store, ref) = await pumpWithVideoDiary(tester);
      expect(find.text('0:04'), findsOneWidget);
      orientations.clear();

      // The play mark lets touches through to the cover under it.
      await tester.tap(find.byIcon(Icons.play_arrow_rounded), warnIfMissed: false);
      await settle(tester);
      expect(find.byType(VideoPlayerPage), findsOneWidget);
      expect(player.opened.single.uri, Uri.file(store.videoFile(ref.id).path).toString());
      expect(player.playing.values.single, isTrue, reason: 'starts playing by itself');
      expect(orientations.last, contains('DeviceOrientation.landscapeLeft'));
      expect(phone.screenOn.last, isTrue);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.pause_rounded));
      await settle(tester);
      expect(player.playing.values.single, isFalse);
      expect(phone.screenOn.last, isFalse, reason: 'a paused video lets the screen switch off as usual');

      await tester.tap(find.byTooltip('返回'));
      await settle(tester);
      expect(find.byType(VideoPlayerPage), findsNothing);
      expect(orientations.last, ['DeviceOrientation.portraitUp']);
      expect(player.disposed, 1);
      expect(find.text('編輯'), findsOneWidget, reason: 'back on the diary');
    });

    appTest('a video that is only in the cloud with no way to fetch it says it needs the network', (tester) async {
      final (store, ref) = await pumpWithVideoDiary(tester);
      await tester.runAsync(() => store.videoFile(ref.id).delete());
      // The play mark lets touches through to the cover under it.
      await tester.tap(find.byIcon(Icons.play_arrow_rounded), warnIfMissed: false);
      await settle(tester);
      expect(find.textContaining('需要網路才能播放這段影片'), findsOneWidget);
      expect(player.opened, isEmpty);
      await tester.tap(find.byTooltip('返回'));
      await settle(tester);
    });
  });

  appTest('something a newer app put in a diary shows as a notice and survives editing', (tester) async {
    final body = jsonEncode([
      {'insert': '前面\n'},
      {'insert': {'diary_hologram': '{"id":"h1"}'}},
      {'insert': '\n'},
    ]);
    final store =
        await pumpApp(tester, diaries: [DiaryInput(day: const Day(2026, 11, 10), title: '未來', body: body)]);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^2026/11/10（二），有日記$')));
    await settle(tester);
    expect(find.text('這裡的內容要更新 App 才能顯示'), findsOneWidget);
    await tester.tap(find.text('編輯'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, '標題'), '未來改過');
    await tester.tap(find.text('儲存'));
    await settle(tester);
    final saved = await tester.runAsync(() => store.diaryOn(const Day(2026, 11, 10)));
    expect(saved!.title, '未來改過');
    expect(saved.body, contains('diary_hologram'));
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
