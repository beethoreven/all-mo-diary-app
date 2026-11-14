import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/constants.dart';
import '../../core/time.dart';
import '../../domain/trim.dart';
import '../../services/video_service.dart';
import '../theme.dart';

/// Choosing which part of a video that is too long to keep: a start and an end, nothing else.
/// Pops with the chosen [TrimWindow], or null when the user backs out.
class VideoTrimPage extends StatefulWidget {
  const VideoTrimPage({super.key, required this.video, required this.platform});

  final PickedVideo video;

  /// Reads the small frames of the strip above the slider.
  final VideoPlatform platform;

  @override
  State<VideoTrimPage> createState() => _VideoTrimPageState();
}

class _VideoTrimPageState extends State<VideoTrimPage> {
  static const _stripFrames = 8;
  static const _nudgeMs = 1000;

  late TrimWindow _window = TrimWindow.initial(widget.video.durationMs);
  late final VideoPlayerController _player = VideoPlayerController.contentUri(Uri.parse(widget.video.uri));
  bool _ready = false;
  bool _failed = false;
  final List<Uint8List?> _strip = List.filled(_stripFrames, null);

  /// The position the preview should show; seeks run one at a time, the latest wish wins.
  int? _wantedMs;
  bool _seeking = false;

  @override
  void initState() {
    super.initState();
    _player.addListener(_onTick);
    _player.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
    }).catchError((Object _) {
      // The picture can't be previewed on this phone; the part can still be chosen by time.
      if (mounted) setState(() => _failed = true);
    });
    _loadStrip();
  }

  @override
  void dispose() {
    _player.removeListener(_onTick);
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadStrip() async {
    for (var i = 0; i < _stripFrames; i++) {
      if (!mounted) return;
      try {
        final at = (widget.video.durationMs * (i + 0.5) / _stripFrames).round();
        final frame = await widget.platform.frame(widget.video.uri, timeMs: at, maxHeight: 120, quality: 70);
        if (!mounted) return;
        setState(() => _strip[i] = frame.bytes);
      } catch (_) {
        // A frame that can't be read stays an empty box.
      }
    }
  }

  /// While playing: stop at the end of the chosen part.
  void _onTick() {
    final value = _player.value;
    if (value.isPlaying && value.position.inMilliseconds >= _window.endMs) {
      _player.pause();
      _show(_window.startMs);
    }
    if (mounted) setState(() {});
  }

  void _show(int ms) {
    _wantedMs = ms;
    if (!_ready || _seeking) return;
    _seeking = true;
    () async {
      while (mounted && _wantedMs != null) {
        final target = _wantedMs!;
        _wantedMs = null;
        try {
          await _player.seekTo(Duration(milliseconds: target));
        } catch (_) {
          break;
        }
      }
      _seeking = false;
    }();
  }

  void _setStart(int ms) {
    _player.pause();
    setState(() => _window = _window.withStart(ms));
    _show(_window.startMs);
  }

  void _setEnd(int ms) {
    _player.pause();
    setState(() => _window = _window.withEnd(ms));
    _show(_window.endMs);
  }

  void _togglePlay() {
    if (!_ready) return;
    if (_player.value.isPlaying) {
      _player.pause();
      return;
    }
    final at = _player.value.position.inMilliseconds;
    if (at < _window.startMs || at >= _window.endMs - 200) {
      _player.seekTo(Duration(milliseconds: _window.startMs)).then((_) => _player.play());
    } else {
      _player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final video = widget.video;
    final maxText = clockText(VideoSpec.maxLength.inMilliseconds);
    return Scaffold(
      backgroundColor: c.surface,
      appBar: AppBar(title: const Text('剪長度')),
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: GestureDetector(
              onTap: _togglePlay,
              child: ColoredBox(
                color: Colors.black,
                child: Stack(alignment: Alignment.center, children: [
                  if (_ready)
                    AspectRatio(aspectRatio: video.width / video.height, child: VideoPlayer(_player))
                  else if (_failed)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('這支手機沒辦法預覽這段影片，仍然可以用下面的時間選要留下的那一段。',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                    )
                  else
                    const CircularProgressIndicator(),
                  if (_ready && !_player.value.isPlaying)
                    const DecoratedBox(
                      decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                      child: Padding(
                          padding: EdgeInsets.all(8), child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40)),
                    ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('這段影片長 ${clockText(video.durationMs)}，日記裡的影片最長 $maxText。請選要留下的那一段。', style: t.bodyMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              height: 44,
              child: Row(children: [
                for (final bytes in _strip)
                  Expanded(
                    child: bytes == null
                        ? ColoredBox(color: c.surface2)
                        : Image.memory(bytes,
                            fit: BoxFit.cover,
                            height: 44,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => ColoredBox(color: c.surface2)),
                  ),
              ]),
            ),
          ),
          RangeSlider(
            min: 0,
            max: video.durationMs.toDouble(),
            values: RangeValues(_window.startMs.toDouble(), _window.endMs.toDouble()),
            onChanged: (v) {
              // Only one end moves per drag event; the other follows by the window's rules.
              if (v.start.round() != _window.startMs) {
                _setStart(v.start.round());
              } else if (v.end.round() != _window.endMs) {
                _setEnd(v.end.round());
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              Expanded(
                child: _Nudge(
                  label: '開始',
                  value: clockText(_window.startMs),
                  onMinus: () => _setStart(_window.startMs - _nudgeMs),
                  onPlus: () => _setStart(_window.startMs + _nudgeMs),
                ),
              ),
              Expanded(
                child: _Nudge(
                  label: '結束',
                  value: clockText(_window.endMs),
                  onMinus: () => _setEnd(_window.endMs - _nudgeMs),
                  onPlus: () => _setEnd(_window.endMs + _nudgeMs),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text('留下的長度：${clockText(_window.lengthMs)}',
                textAlign: TextAlign.center, style: weight(t.bodyMedium!, 600)),
          ),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('取消'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(onPressed: () => Navigator.pop(context, _window), child: const Text('確定'))),
          ]),
        ),
      ),
    );
  }
}

/// One end of the part: its time, with buttons that move it a second at a time.
class _Nudge extends StatelessWidget {
  const _Nudge({required this.label, required this.value, required this.onMinus, required this.onPlus});

  final String label;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton(onPressed: onMinus, tooltip: '$label往前 1 秒', icon: const Icon(Icons.remove_circle_outline_rounded)),
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: t.bodySmall),
        Text(value, style: weight(t.titleMedium!, 600)),
      ]),
      IconButton(onPressed: onPlus, tooltip: '$label往後 1 秒', icon: const Icon(Icons.add_circle_outline_rounded)),
    ]);
  }
}
