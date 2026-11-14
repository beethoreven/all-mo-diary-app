import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:allmodiary/core/constants.dart';
import 'package:allmodiary/services/video_service.dart';

/// A stand-in for the phone's video code: "shrinking" writes a few bytes, a frame is a few bytes.
class FakeVideoPlatform implements VideoPlatform {
  /// What the picker returns (null = the user backed out).
  PickedVideo? picked;

  /// The size of the frames handed back (the stored video's size as shown).
  int frameWidth = 1080, frameHeight = 608;

  /// Set to make shrinking fail.
  Object? failWith;

  /// Set to make reading a frame fail.
  bool failFrames = false;

  /// When set, shrinking waits here (until completed, or until cancel()).
  Completer<void>? hold;

  /// Arguments of the last transcode.
  String? source, out;
  int? startMs, endMs, height, bitrate;
  final List<bool> screenOn = [];
  var cancels = 0;
  Completer<void>? _cancelled;

  static final videoBytes = List<int>.generate(5000, (i) => i % 241);
  /// A real picture (1×1), so widgets that draw a frame can decode it.
  static final frameBytes = Uint8List.fromList(const [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 218, 99, 252, 207, 192, 80, 15, 0, 4, 133, 1, 128, 132, 169, 140, 33, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]);

  @override
  Future<PickedVideo?> pick() async => picked;

  @override
  Future<VideoFrame> frame(String source, {int timeMs = 0, int? maxHeight, int quality = VideoSpec.coverQuality}) async {
    if (failFrames) throw const VideoProblem('no_frame');
    return VideoFrame(frameBytes, frameWidth, frameHeight);
  }

  @override
  Future<int> transcode({
    required String source,
    required String out,
    int? startMs,
    int? endMs,
    required int height,
    required int bitrate,
    void Function(int percent)? onProgress,
  }) async {
    this.source = source;
    this.out = out;
    this.startMs = startMs;
    this.endMs = endMs;
    this.height = height;
    this.bitrate = bitrate;
    onProgress?.call(40);
    // Half-written, like the real thing while it works.
    await File(out).writeAsBytes(videoBytes.sublist(0, 100));
    final wait = hold;
    if (wait != null) {
      final cancelled = _cancelled = Completer<void>();
      await Future.any([wait.future, cancelled.future]);
      if (cancelled.isCompleted) {
        await File(out).delete();
        throw const VideoCancelled();
      }
    }
    final failure = failWith;
    if (failure != null) {
      await File(out).delete();
      throw failure;
    }
    await File(out).writeAsBytes(videoBytes);
    onProgress?.call(100);
    return (endMs ?? picked?.durationMs ?? 5000) - (startMs ?? 0);
  }

  @override
  Future<void> cancel() async {
    cancels++;
    final c = _cancelled;
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  Future<void> keepScreenOn(bool on) async => screenOn.add(on);
}
