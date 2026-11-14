import '../core/constants.dart';

/// The part of a video kept on the trim screen: [startMs]–[endMs] inside 0–[durationMs], never
/// longer than [maxMs] nor shorter than [minMs]. Moving one end past either limit takes the other
/// end along, so the part slides instead of stopping.
class TrimWindow {
  const TrimWindow._(this.durationMs, this.startMs, this.endMs, this.maxMs, this.minMs);

  /// The first [maxMs] of the video (all of it when it is shorter).
  factory TrimWindow.initial(int durationMs, {int? maxMs, int? minMs}) {
    final max = maxMs ?? VideoSpec.maxLength.inMilliseconds;
    final min = minMs ?? VideoSpec.minLength.inMilliseconds;
    return TrimWindow._(durationMs, 0, durationMs < max ? durationMs : max, max, min < durationMs ? min : durationMs);
  }

  final int durationMs;
  final int startMs;
  final int endMs;
  final int maxMs;
  final int minMs;

  int get lengthMs => endMs - startMs;

  TrimWindow withStart(int ms) {
    final start = ms.clamp(0, durationMs - minMs);
    var end = endMs;
    if (end - start > maxMs) end = start + maxMs;
    if (end - start < minMs) end = start + minMs;
    return TrimWindow._(durationMs, start, end, maxMs, minMs);
  }

  TrimWindow withEnd(int ms) {
    final end = ms.clamp(minMs, durationMs);
    var start = startMs;
    if (end - start > maxMs) start = end - maxMs;
    if (end - start < minMs) start = end - minMs;
    return TrimWindow._(durationMs, start, end, maxMs, minMs);
  }
}
