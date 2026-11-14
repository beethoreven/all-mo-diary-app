// The app's own Android video code (VideoChannel.kt), run on an emulator: the unit tests only see
// a stand-in for it.
//
// ★ Emulator only. `flutter test` removes an installed app whose signature differs before
//   installing this one, and removes the app again when the run ends — on a phone that has the
//   real app, that deletes its diaries. With a phone attached too, name the emulator in every
//   command (-d / -s).
//
// It needs sample videos in the app's files/video_samples/ folder; tool/video_samples.sh makes
// them with ffmpeg and copies them to the emulator. Then:
//
//   flutter test integration_test/video_channel_test.dart -d emulator-5554
//
// To look at the shrunk files (files/video_out/) afterwards, build this file as the app
// (flutter build apk --debug -t integration_test/video_channel_test.dart), install and start it by
// hand: the run reports to logcat and the app stays installed.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:allmodiary/services/video_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final platform = ChannelVideoPlatform();
  // The size videos are shrunk for: a 1080×2400 screen.
  const screen = ui.Size(1080, 2400);
  late Directory samples, out;

  setUpAll(() async {
    final files = await getApplicationSupportDirectory();
    samples = Directory('${files.path}/video_samples');
    out = Directory('${files.path}/video_out');
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync(recursive: true);
    expect(samples.existsSync(), isTrue, reason: 'run tool/video_samples.sh first');
  });

  String uri(String name) => Uri.file('${samples.path}/$name').toString();

  /// Shrinks one sample the way the app does and returns what came out.
  Future<({int durationMs, VideoFrame cover, File file, Map<String, Object?> info})> shrink(
      String name, int width, int height,
      {int? startMs, int? endMs}) async {
    final goal = VideoService.target(width, height, screen);
    final file = File('${out.path}/$name');
    final watch = Stopwatch()..start();
    var last = -1;
    final durationMs = await platform.transcode(
      source: uri(name),
      out: file.path,
      startMs: startMs,
      endMs: endMs,
      height: goal.height,
      bitrate: goal.bitrate,
      onProgress: (p) => last = p,
    );
    final cover = await platform.frame(Uri.file(file.path).toString());
    final info = await platform.describe(Uri.file(file.path).toString());
    // ignore: avoid_print
    print('VIDEO ${jsonEncode({
          'name': name,
          'goal_h': goal.height,
          'bitrate': goal.bitrate,
          'duration_ms': durationMs,
          'cover': '${cover.width}x${cover.height}',
          'cover_bytes': cover.bytes.length,
          'bytes': file.lengthSync(),
          'took_ms': watch.elapsedMilliseconds,
          'last_progress': last,
          'frames': info['frames'],
          'audio': info['hasAudio'],
          'location': info['location'],
        })}');
    return (durationMs: durationMs, cover: cover, file: file, info: info);
  }

  /// Frames per second of a shrunk file.
  double fps(Map<String, Object?> info) => (info['frames']! as num) * 1000 / (info['durationMs']! as num);

  testWidgets('a landscape 1080p 60 fps video becomes screen-wide', (tester) async {
    final r = await shrink('land60.mp4', 1920, 1080);
    expect(r.cover.width, closeTo(1080, 2));
    expect(r.cover.height, closeTo(608, 2));
    expect(r.durationMs, closeTo(10000, 300));
    expect(r.file.lengthSync(), lessThan(5 * 1024 * 1024));
    expect(fps(r.info), closeTo(30, 2), reason: '60 frames a second are stored as 30');
    expect(r.info['hasAudio'], isTrue);
  });

  testWidgets('where a video was filmed is not kept', (tester) async {
    final before = await platform.describe(uri('land60.mp4'));
    expect(before['location'], isNotNull, reason: 'the sample says where it was filmed');
    final r = await shrink('land60.mp4', 1920, 1080);
    expect(r.info['location'], isNull);
  });

  testWidgets('a video filmed upright stays upright, a third of the screen tall', (tester) async {
    final r = await shrink('portrait_rot.mp4', 1080, 1920);
    expect(r.cover.width, closeTo(450, 2));
    expect(r.cover.height, closeTo(800, 2));
  });

  testWidgets('a video without sound', (tester) async {
    final r = await shrink('silent.mp4', 1280, 720);
    expect(r.cover.width, closeTo(1080, 2));
    expect(r.durationMs, closeTo(5000, 300));
    expect(r.info['hasAudio'], isFalse);
    expect(fps(r.info), closeTo(30, 2));
  });

  testWidgets('a small video is not enlarged', (tester) async {
    final r = await shrink('small.mp4', 320, 240);
    expect((r.cover.width, r.cover.height), (320, 240));
  });

  testWidgets('only the chosen part of a long video is kept', (tester) async {
    final r = await shrink('long150.mp4', 640, 360, startMs: 20000, endMs: 140000);
    expect(r.durationMs, closeTo(120000, 300));
    expect((r.cover.width, r.cover.height), (640, 360));
  });

  testWidgets('a frame of the original, shrunk for the trim screen', (tester) async {
    final f = await platform.frame(uri('land60.mp4'), timeMs: 5000, maxHeight: 120, quality: 70);
    expect(f.height, closeTo(120, 2));
    expect(f.width, closeTo(213, 3));
    expect(f.bytes.length, greaterThan(500));
  });

  testWidgets('cancelling stops the work and leaves no file', (tester) async {
    final file = File('${out.path}/cancelled.mp4');
    final goal = VideoService.target(640, 360, screen);
    final work = platform.transcode(
        source: uri('long150.mp4'),
        out: file.path,
        height: goal.height,
        bitrate: goal.bitrate,
        onProgress: (p) {
          if (p >= 1) platform.cancel();
        });
    await expectLater(work, throwsA(isA<VideoCancelled>()));
    expect(file.existsSync(), isFalse);
    // The channel is free again afterwards.
    final r = await shrink('small.mp4', 320, 240);
    expect(r.durationMs, closeTo(4000, 300));
  });

  testWidgets('a file that is not a video is refused, with nothing left behind', (tester) async {
    final junk = File('${samples.path}/junk.mp4')..writeAsBytesSync(List.filled(4096, 7));
    final file = File('${out.path}/junk.mp4');
    await expectLater(
        platform.transcode(source: Uri.file(junk.path).toString(), out: file.path, height: 240, bitrate: 400000),
        throwsA(isA<VideoProblem>()));
    expect(file.existsSync(), isFalse);
    await expectLater(platform.frame(Uri.file(junk.path).toString()), throwsA(isA<VideoProblem>()));
    junk.deleteSync();
  });
}
