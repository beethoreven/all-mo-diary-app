import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:allmodiary/data/database.dart';
import 'package:allmodiary/data/store.dart';
import 'package:allmodiary/domain/diary.dart';
import 'package:allmodiary/services/video_service.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_video.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const screen = ui.Size(1080, 2400);
  const picked = PickedVideo(uri: 'content://picker/1', durationMs: 83000, width: 1920, height: 1080);
  late Directory dir;
  late Store store;
  late FakeVideoPlatform phone;
  late VideoService videos;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('amd_video_');
    store = Store(AppDb(NativeDatabase.memory()),
        imagesDir: Directory('${dir.path}/images'), videosDir: Directory('${dir.path}/videos'));
    phone = FakeVideoPlatform()..picked = picked;
    videos = VideoService(store, platform: phone);
  });

  tearDown(() async {
    await store.db.close();
    dir.deleteSync(recursive: true);
  });

  List<String> names(Directory d) =>
      d.existsSync() ? (d.listSync().map((e) => e.uri.pathSegments.last).toList()..sort()) : [];

  test('a video is stored shrunk, with its first frame as a cover image', () async {
    final progress = <int>[];
    final ref = await videos.add(picked, screen, onProgress: progress.add);
    expect((ref.width, ref.height, ref.durationMs), (1080, 608, 83000));
    expect(progress, [40, 100]);
    // Asked for the size an image would get on this screen, the whole video.
    expect((phone.source, phone.height, phone.startMs, phone.endMs), ('content://picker/1', 608, null, null));
    expect(phone.bitrate, closeTo(1970000, 20000));

    expect(await store.videoFile(ref.id).readAsBytes(), FakeVideoPlatform.videoBytes);
    expect(await store.imageFile(ref.coverId).readAsBytes(), FakeVideoPlatform.frameBytes);
    expect(names(store.videosDir), ['${ref.id}.mp4'], reason: 'no temporary file left');
    expect(names(store.imagesDir), ['${ref.coverId}.jpg']);
    expect(MediaKind.of((await store.mediaRow(ref.id))!.kind), MediaKind.video);
    expect(MediaKind.of((await store.mediaRow(ref.coverId))!.kind), MediaKind.image);
  });

  test('a chosen part is passed on; choosing everything is the same as not trimming', () async {
    await videos.add(picked, screen, startMs: 10000, endMs: 70000);
    expect((phone.startMs, phone.endMs), (10000, 70000));
    await videos.add(picked, screen, startMs: 0, endMs: 83000);
    expect((phone.startMs, phone.endMs), (null, null));
    await videos.add(picked, screen, startMs: 0, endMs: 60000);
    expect((phone.startMs, phone.endMs), (null, 60000));
  });

  test('when shrinking fails nothing is left behind', () async {
    phone.failWith = const VideoProblem('ERROR_CODE_DECODING_FORMAT_UNSUPPORTED');
    await expectLater(videos.add(picked, screen), throwsA(isA<VideoProblem>()));
    expect(names(store.videosDir), isEmpty);
    expect(names(store.imagesDir), isEmpty);
    expect(await store.mediaRows(), isEmpty);
  });

  test('when the cover can\'t be read the video isn\'t kept either', () async {
    phone.failFrames = true;
    await expectLater(videos.add(picked, screen), throwsA(isA<VideoProblem>()));
    expect(names(store.videosDir), isEmpty);
    expect(names(store.imagesDir), isEmpty);
    expect(await store.mediaRows(), isEmpty);
  });

  test('one video at a time: a second is refused while the first is being shrunk', () async {
    phone.hold = Completer<void>();
    final first = videos.add(picked, screen);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(videos.working, isTrue);
    await expectLater(videos.add(picked, screen),
        throwsA(isA<VideoProblem>().having((e) => e.code, 'code', VideoProblem.busy)));
    expect(names(store.videosDir), hasLength(1), reason: 'the first one is untouched');
    phone.hold!.complete();
    final ref = await first;
    expect(await store.videoFile(ref.id).exists(), isTrue);
    expect(videos.working, isFalse);
    // And the next one goes through.
    phone.hold = null;
    await videos.add(picked, screen);
  });

  test('cancelling stops the work and leaves nothing behind', () async {
    phone.hold = Completer<void>();
    final work = videos.add(picked, screen);
    final failed = expectLater(work, throwsA(isA<VideoCancelled>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(names(store.videosDir), hasLength(1), reason: 'being written under a temporary name');
    expect(names(store.videosDir).single, endsWith('.part'));
    await videos.cancel();
    await failed;
    expect(names(store.videosDir), isEmpty);
    expect(await store.mediaRows(), isEmpty);
  });
}
