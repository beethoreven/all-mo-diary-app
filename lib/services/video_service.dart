import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../core/constants.dart';
import '../core/log.dart';
import '../data/store.dart';
import '../domain/diary.dart';
import 'image_service.dart';

/// A video chosen in the photo library, still where it was (a content URI); nothing is stored yet.
class PickedVideo {
  const PickedVideo({required this.uri, required this.durationMs, required this.width, required this.height});

  final String uri;
  final int durationMs;

  /// Pixel size as shown (upright).
  final int width;
  final int height;

  /// Longer than a diary video may be: the user picks which part to keep first.
  bool get needsTrim => durationMs > VideoSpec.maxLength.inMilliseconds;
}

/// One frame of a video as a JPEG, with its pixel size.
class VideoFrame {
  const VideoFrame(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}

/// The user stopped a video that was being shrunk.
class VideoCancelled implements Exception {
  const VideoCancelled();
}

/// The phone couldn't read or shrink the video (a format it has no decoder for, a broken file,
/// no space left, or the system stopped the app's work in the background).
class VideoProblem implements Exception {
  const VideoProblem(this.code);

  /// Another video is still being shrunk (one at a time).
  static const busy = 'busy';

  final String code;

  @override
  String toString() => 'VideoProblem($code)';
}

/// What the phone does for videos (android/app/src/main/kotlin/.../VideoChannel.kt). Tests replace it.
abstract class VideoPlatform {
  /// Opens the system photo picker for one video. null when the user backs out.
  Future<PickedVideo?> pick();

  /// The key frame nearest [timeMs] of [source] (a content or file URI), at most [maxHeight] tall.
  Future<VideoFrame> frame(String source, {int timeMs = 0, int? maxHeight, int quality = VideoSpec.coverQuality});

  /// Writes a shrunk copy of [source] to [out]: the part from [startMs] to [endMs] (null = from the
  /// start / to the end), [height] pixels tall. Returns its length. Throws [VideoCancelled] or
  /// [VideoProblem]. One at a time.
  Future<int> transcode({
    required String source,
    required String out,
    int? startMs,
    int? endMs,
    required int height,
    required int bitrate,
    void Function(int percent)? onProgress,
  });

  /// Stops the transcode in flight (it then throws [VideoCancelled]). Nothing happens when idle.
  Future<void> cancel();

  /// Keeps the screen from switching itself off while a video plays.
  Future<void> keepScreenOn(bool on);
}

class ChannelVideoPlatform implements VideoPlatform {
  ChannelVideoPlatform() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'progress') _onProgress?.call(call.arguments as int);
    });
  }

  static const _channel = MethodChannel('tw.com.tutorarthur.allmodiary/video');
  void Function(int percent)? _onProgress;
  bool _transcoding = false;

  @override
  Future<PickedVideo?> pick() async {
    final Map<String, Object?>? m;
    try {
      m = await _channel.invokeMapMethod<String, Object?>('pick');
    } on PlatformException catch (e) {
      throw VideoProblem(e.code);
    }
    if (m == null) return null;
    return PickedVideo(
      uri: m['uri']! as String,
      durationMs: (m['durationMs']! as num).toInt(),
      width: m['width']! as int,
      height: m['height']! as int,
    );
  }

  /// What the phone reads about the video at [source]: `durationMs`, `width`, `height` (as shown),
  /// `frames`, `hasAudio` and `location` (where it was filmed, null when the file doesn't say).
  /// The on-phone test checks stored videos with it.
  Future<Map<String, Object?>> describe(String source) async {
    try {
      return (await _channel.invokeMapMethod<String, Object?>('describe', {'source': source}))!;
    } on PlatformException catch (e) {
      throw VideoProblem(e.code);
    }
  }

  @override
  Future<VideoFrame> frame(String source, {int timeMs = 0, int? maxHeight, int quality = VideoSpec.coverQuality}) async {
    try {
      final m = (await _channel.invokeMapMethod<String, Object?>(
          'frame', {'source': source, 'timeMs': timeMs, 'maxHeight': maxHeight, 'quality': quality}))!;
      return VideoFrame(m['bytes']! as Uint8List, m['width']! as int, m['height']! as int);
    } on PlatformException catch (e) {
      throw VideoProblem(e.code);
    }
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
    // One at a time (the phone's side refuses a second too): refused here, before the progress of
    // the one in flight could be redirected to this caller.
    if (_transcoding) throw const VideoProblem(VideoProblem.busy);
    _transcoding = true;
    _onProgress = onProgress;
    try {
      final m = (await _channel.invokeMapMethod<String, Object?>('transcode', {
        'source': source,
        'out': out,
        'startMs': startMs,
        'endMs': endMs,
        'height': height,
        'bitrate': bitrate,
        'audioBitrate': VideoSpec.audioBitrate,
        'maxFrameRate': VideoSpec.maxFrameRate,
      }))!;
      return (m['durationMs']! as num).toInt();
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') throw const VideoCancelled();
      if (e.code == 'busy') throw const VideoProblem(VideoProblem.busy);
      throw VideoProblem(e.message ?? e.code);
    } finally {
      _transcoding = false;
      _onProgress = null;
    }
  }

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');

  @override
  Future<void> keepScreenOn(bool on) => _channel.invokeMethod<void>('keepScreenOn', {'on': on});
}

/// Adding a video to a diary.
///
/// - Only from the phone's photo library (the system picker; no permission to read the whole library).
/// - At most [VideoSpec.maxLength] long: a longer one is trimmed first (the user picks the part).
/// - Stored at the size a diary image would have (ImageService.targetSize): height = 1/3 of the
///   screen height, or the screen's width when that would be wider. The stored file *is* the shrunk
///   one; the original isn't kept. Sound is kept.
/// - Its cover is its first frame, stored as an ordinary diary image, so a diary shows without
///   reading (or downloading) the video itself.
class VideoService {
  VideoService(this.store, {VideoPlatform? platform}) : platform = platform ?? ChannelVideoPlatform();

  final Store store;
  final VideoPlatform platform;

  /// A video is being shrunk. Kept here, not in the screen that started it: the work goes on when
  /// that screen is left, and a second one must wait for it.
  bool get working => _working;
  bool _working = false;

  Future<PickedVideo?> pick() async {
    try {
      return await platform.pick();
    } catch (e) {
      AppLog.warn('video.pick_failed', {'reason': e is VideoProblem ? e.code : e.runtimeType.toString()});
      rethrow;
    }
  }

  /// The stored height (as shown) and bitrate for a [width]×[height] video on a [screen]-sized display.
  static ({int height, int bitrate}) target(int width, int height, ui.Size screen) {
    final size = ImageService.targetSize(width, height, screen);
    // Encoders need even sides; the width follows from the height.
    final h = size.height.isEven ? size.height : size.height - 1;
    final safeH = h < 2 ? 2 : h;
    final w = (width * safeH / height).round();
    final bitrate = (w * safeH * VideoSpec.maxFrameRate * VideoSpec.bitsPerPixelPerFrame).round();
    return (height: safeH, bitrate: bitrate < VideoSpec.minBitrate ? VideoSpec.minBitrate : bitrate);
  }

  /// Shrinks [video] (the part from [startMs] to [endMs] when given) and stores it with its cover.
  /// [screen] is the screen size in physical pixels. Throws [VideoCancelled] or [VideoProblem];
  /// nothing is left behind then.
  Future<VideoRef> add(PickedVideo video, ui.Size screen,
      {int? startMs, int? endMs, void Function(int percent)? onProgress}) async {
    if (_working) throw const VideoProblem(VideoProblem.busy);
    _working = true;
    try {
      return await _add(video, screen, startMs: startMs, endMs: endMs, onProgress: onProgress);
    } finally {
      _working = false;
    }
  }

  Future<VideoRef> _add(PickedVideo video, ui.Size screen,
      {int? startMs, int? endMs, void Function(int percent)? onProgress}) async {
    final wholeFromStart = startMs == null || startMs <= 0;
    final wholeToEnd = endMs == null || endMs >= video.durationMs;
    final goal = target(video.width, video.height, screen);
    final id = Store.newId(), coverId = Store.newId();
    final file = store.videoFile(id), cover = store.imageFile(coverId);
    // Under temporary names until both are complete: a half-written file at the real name would
    // be shown (and uploaded) as if it were whole.
    final filePart = File('${file.path}.part'), coverPart = File('${cover.path}.part');
    await file.parent.create(recursive: true);
    await cover.parent.create(recursive: true);
    final watch = Stopwatch()..start();
    try {
      final durationMs = await platform.transcode(
        source: video.uri,
        out: filePart.path,
        startMs: wholeFromStart ? null : startMs,
        endMs: wholeToEnd ? null : endMs,
        height: goal.height,
        bitrate: goal.bitrate,
        onProgress: onProgress,
      );
      final first = await platform.frame(Uri.file(filePart.path).toString());
      await coverPart.writeAsBytes(first.bytes, flush: true);
      await coverPart.rename(cover.path);
      await filePart.rename(file.path);
      await store.addImage(coverId);
      await store.addVideo(id);
      AppLog.info('video.added', {
        'source_s': video.durationMs ~/ 1000,
        'source_h': video.height,
        's': durationMs ~/ 1000,
        'h': first.height,
        'kb': await file.length() ~/ 1024,
        'took_s': watch.elapsed.inSeconds,
      });
      return VideoRef(id: id, coverId: coverId, width: first.width, height: first.height, durationMs: durationMs);
    } catch (e) {
      for (final f in [filePart, coverPart, file, cover]) {
        if (await f.exists()) await f.delete();
      }
      // The last steps record the two files; one may have been recorded before the other failed.
      await store.deleteMediaRow(coverId);
      await store.deleteMediaRow(id);
      if (e is! VideoCancelled) AppLog.warn('video.add_failed', {'reason': e is VideoProblem ? e.code : e.runtimeType.toString()});
      rethrow;
    }
  }

  Future<void> cancel() => platform.cancel();
}
