import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/text.dart';

/// Asks for the user name shown as「名字的日記」 (spec §1.1): at most 8 characters, not blank.
/// Returns the cleaned name, or null when cancelled.
Future<String?> askUserName(BuildContext context, {String initial = '', bool cancellable = true}) =>
    showDialog<String>(
      context: context,
      barrierDismissible: cancellable,
      builder: (_) => _NameDialog(initial: initial, cancellable: cancellable),
    );

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial, required this.cancellable});

  final String initial;
  final bool cancellable;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _done() {
    final name = TextRules.clean(_text.text);
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final ok = TextRules.clean(_text.text).isNotEmpty;
    return AlertDialog(
      title: const Text('你的名字'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('會顯示成「你設定的名字」的日記，最多 ${Limits.userNameMaxChars} 個字。', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          autofocus: true,
          maxLines: 1,
          maxLength: Limits.userNameMaxChars,
          inputFormatters: [TextRules.blockControl],
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _done(),
          decoration: const InputDecoration(hintText: '例如：小明'),
        ),
      ]),
      actions: [
        if (widget.cancellable) TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: ok ? _done : null, child: const Text('確定')),
      ],
    );
  }
}
