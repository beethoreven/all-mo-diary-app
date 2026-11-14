import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A stand-in for the phone's video player: every video opens at once with [duration] and [size],
/// and shows as a plain box.
class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  Duration duration = const Duration(seconds: 4);
  Size size = const Size(1080, 608);

  /// What was opened, in order.
  final List<DataSource> opened = [];
  final Map<int, Duration> positions = {};
  final Map<int, bool> playing = {};
  var disposed = 0;
  final Map<int, StreamController<VideoEvent>> _events = {};
  var _next = 1;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _next++;
    opened.add(options.dataSource);
    positions[id] = Duration.zero;
    _events[id] = StreamController<VideoEvent>()
      ..add(VideoEvent(eventType: VideoEventType.initialized, duration: duration, size: size));
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    disposed++;
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> play(int playerId) async => playing[playerId] = true;

  @override
  Future<void> pause(int playerId) async => playing[playerId] = false;

  @override
  Future<void> seekTo(int playerId, Duration position) async => positions[playerId] = position;

  @override
  Future<Duration> getPosition(int playerId) async => positions[playerId] ?? Duration.zero;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const ColoredBox(color: Color(0xFF224466));
}
