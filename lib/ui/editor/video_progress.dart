import 'package:flutter/material.dart';

import '../../services/video_service.dart';
import '../theme.dart';

class _Outcome<T> {
  const _Outcome.value(this.value) : error = null, stack = null;
  const _Outcome.error(Object this.error, this.stack) : value = null;

  final T? value;
  final Object? error;
  final StackTrace? stack;
}

/// Runs [work] (shrinking a video) under a dialog that shows how far it is and can't be dismissed
/// except with its 取消 button. Returns the result, or null when the user cancelled ([cancel] was
/// called and [work] ended with [VideoCancelled]). Any other failure of [work] is rethrown.
Future<T?> runWithVideoProgress<T>(
  BuildContext context, {
  required Future<T> Function(void Function(int percent) onProgress) work,
  required Future<void> Function() cancel,
}) async {
  final outcome = await showDialog<_Outcome<T>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _VideoProgressDialog<T>(work: work, cancel: cancel),
  );
  if (outcome == null) return null;
  final error = outcome.error;
  if (error is VideoCancelled) return null;
  if (error != null) Error.throwWithStackTrace(error, outcome.stack ?? StackTrace.current);
  return outcome.value;
}

class _VideoProgressDialog<T> extends StatefulWidget {
  const _VideoProgressDialog({required this.work, required this.cancel});

  final Future<T> Function(void Function(int percent) onProgress) work;
  final Future<void> Function() cancel;

  @override
  State<_VideoProgressDialog<T>> createState() => _VideoProgressDialogState<T>();
}

class _VideoProgressDialogState<T> extends State<_VideoProgressDialog<T>> {
  int? _percent;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    _Outcome<T> outcome;
    try {
      outcome = _Outcome.value(await widget.work((percent) {
        if (mounted) setState(() => _percent = percent.clamp(0, 100));
      }));
    } catch (e, st) {
      outcome = _Outcome.error(e, st);
    }
    if (mounted) Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final percent = _percent;
    return PopScope(
      // The back gesture doesn't close it: the work would go on with nothing on screen.
      canPop: false,
      child: AlertDialog(
        title: const Text('正在處理影片'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LinearProgressIndicator(value: percent == null ? null : percent / 100),
          const SizedBox(height: 8),
          Text(_cancelling ? '正在取消…' : (percent == null ? '準備中…' : '$percent%'), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text('影片越長、原本的畫質越高，需要的時間越久。完成前請不要離開全心日記。', style: t.bodySmall!.copyWith(color: c.text2)),
        ]),
        actions: [
          TextButton(
            onPressed: _cancelling
                ? null
                : () {
                    setState(() => _cancelling = true);
                    // If the request to stop can't be delivered, the work goes on: offer 取消 again.
                    widget.cancel().catchError((Object _) {
                      if (mounted) setState(() => _cancelling = false);
                    });
                  },
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}
