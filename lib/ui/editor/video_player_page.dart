import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../core/log.dart';
import '../../core/time.dart';

/// Where the diary body gets the files of its images and videos.
class MediaSource {
  const MediaSource({required this.image, required this.video, required this.videoProgress, required this.keepScreenOn});

  /// The file to show for an image id: on the phone, cached, or downloaded from the cloud.
  /// null when it can't be had now.
  final Future<File?> Function(String id) image;

  /// The same for a video id.
  final Future<File?> Function(String id) video;

  /// How much of a video's download has arrived (0–1); null while there is nothing to tell.
  final ValueListenable<double?> Function(String id) videoProgress;

  /// Keeps the screen from switching itself off while a video plays.
  final Future<void> Function(bool on) keepScreenOn;
}

/// Plays one diary video over the whole screen, with sound. The rest of the app is portrait only;
/// this screen follows the phone when it is turned on its side, and goes back to portrait on leaving.
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key, required this.id, required this.media});

  final String id;
  final MediaSource media;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

enum _Stage { fetching, unavailable, opening, unplayable, ready }

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  _Stage _stage = _Stage.fetching;
  VideoPlayerController? _player;
  bool _controls = true;
  bool _awake = false;

  /// While the slider is dragged, it shows the finger's position, not the player's.
  double? _dragMs;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(
        const [DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    _open();
  }

  @override
  void dispose() {
    _closePlayer();
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Future<void> _open() async {
    _closePlayer();
    setState(() => _stage = _Stage.fetching);
    final file = await widget.media.video(widget.id);
    if (!mounted) return;
    if (file == null) {
      setState(() => _stage = _Stage.unavailable);
      return;
    }
    setState(() => _stage = _Stage.opening);
    final player = VideoPlayerController.file(file);
    try {
      await player.initialize();
    } catch (e) {
      AppLog.warn('video.open_failed', {'type': e.runtimeType.toString()});
      await player.dispose();
      if (mounted) setState(() => _stage = _Stage.unplayable);
      return;
    }
    if (!mounted) {
      await player.dispose();
      return;
    }
    _player = player..addListener(_onTick);
    setState(() => _stage = _Stage.ready);
    await player.play();
  }

  void _onTick() {
    final player = _player;
    if (player == null || !mounted) return;
    if (player.value.hasError) {
      // The player gave up part-way (a damaged file, the decoder taken away).
      AppLog.warn('video.play_failed');
      _closePlayer();
      setState(() => _stage = _Stage.unplayable);
      return;
    }
    _keepAwake(player.value.isPlaying);
    setState(() {});
  }

  void _closePlayer() {
    _player?.removeListener(_onTick);
    _player?.dispose();
    _player = null;
    _keepAwake(false);
  }

  void _keepAwake(bool on) {
    if (on == _awake) return;
    _awake = on;
    // Best effort: a phone that refuses only lets its screen time out as usual.
    unawaited(widget.media.keepScreenOn(on).catchError((Object _) {}));
  }

  bool get _ended {
    final v = _player?.value;
    return v != null && v.duration > Duration.zero && v.position >= v.duration;
  }

  Future<void> _togglePlay() async {
    final player = _player;
    if (player == null) return;
    if (player.value.isPlaying) {
      await player.pause();
    } else {
      if (_ended) await player.seekTo(Duration.zero);
      await player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(child: _content()),
          if (_controls || _stage != _Stage.ready)
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                tooltip: '返回',
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _content() {
    const style = TextStyle(color: Colors.white70);
    switch (_stage) {
      case _Stage.fetching:
        return Center(
          child: ValueListenableBuilder<double?>(
            valueListenable: widget.media.videoProgress(widget.id),
            builder: (context, fraction, _) => Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(value: fraction),
              if (fraction != null) ...[
                const SizedBox(height: 16),
                Text('正在從雲端下載影片 ${(fraction * 100).round()}%', style: style),
              ],
            ]),
          ),
        );
      case _Stage.opening:
        return const Center(child: CircularProgressIndicator());
      case _Stage.unavailable:
        return _message('需要網路才能播放這段影片\n（點一下重試）', onTap: _open);
      case _Stage.unplayable:
        // Trying again looks the file up afresh: the sync may have moved it from the phone to the
        // cache between finding it and opening it.
        return _message('無法播放這段影片\n（點一下重試）', onTap: _open);
      case _Stage.ready:
        final player = _player!;
        final value = player.value;
        final durationMs = value.duration.inMilliseconds;
        final positionMs = (_dragMs ?? value.position.inMilliseconds.toDouble()).clamp(0, durationMs.toDouble()).toDouble();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _controls = !_controls),
          child: Stack(alignment: Alignment.center, children: [
            Center(child: AspectRatio(aspectRatio: value.aspectRatio, child: VideoPlayer(player))),
            if (_controls)
              IconButton(
                onPressed: _togglePlay,
                iconSize: 56,
                tooltip: value.isPlaying ? '暫停' : '播放',
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
                icon: Icon(
                    value.isPlaying
                        ? Icons.pause_rounded
                        : (_ended ? Icons.replay_rounded : Icons.play_arrow_rounded),
                    color: Colors.white),
              ),
            if (_controls)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ColoredBox(
                  color: Colors.black45,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      Text(clockText(positionMs.round()), style: const TextStyle(color: Colors.white)),
                      Expanded(
                        child: Slider(
                          min: 0,
                          max: durationMs <= 0 ? 1 : durationMs.toDouble(),
                          value: durationMs <= 0 ? 0 : positionMs,
                          onChangeStart: (v) => setState(() => _dragMs = v),
                          onChanged: (v) => setState(() => _dragMs = v),
                          onChangeEnd: (v) async {
                            await player.seekTo(Duration(milliseconds: v.round()));
                            if (mounted) setState(() => _dragMs = null);
                          },
                        ),
                      ),
                      Text(clockText(durationMs), style: const TextStyle(color: Colors.white)),
                    ]),
                  ),
                ),
              ),
          ]),
        );
    }
  }

  Widget _message(String text, {VoidCallback? onTap}) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          ),
        ),
      );
}
