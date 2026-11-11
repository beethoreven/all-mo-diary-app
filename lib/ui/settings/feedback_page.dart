import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/log.dart';
import '../../services/api_client.dart';
import '../../services/feedback_service.dart';
import '../../state/providers.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 意見回饋(SPEC 第 10 節「送出流程」):描述只有一個自由填寫的欄位(必填,上限 1000 字);
/// 送出前選類型;按「送出」後先顯示確認畫面,按「確認送出」才送。
class FeedbackPage extends ConsumerStatefulWidget {
  const FeedbackPage({super.key, this.kind = FeedbackKind.suggestion});

  final FeedbackKind kind;

  @override
  ConsumerState<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends ConsumerState<FeedbackPage> {
  late FeedbackKind _kind = widget.kind;
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String get _hint => _kind == FeedbackKind.problem
      ? '請描述發生了什麼、大概什麼時候、當時在做什麼。請不要貼上日記內容或其他私人資料。'
      : '想到什麼都可以告訴我們。請不要貼上日記內容或其他私人資料。';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.all(12), children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('類型', style: t.labelSmall),
          const SizedBox(height: 6),
          SegmentedButton<FeedbackKind>(
            showSelectedIcon: false,
            segments: [for (final k in FeedbackKind.values) ButtonSegment(value: k, label: Text(k.label))],
            selected: {_kind},
            onSelectionChanged: (v) => setState(() => _kind = v.first),
          ),
          const SizedBox(height: 6),
          Text(_kind == FeedbackKind.problem
              ? '會附上手機狀態、雲端同步狀態與最近 7 天的使用記錄（不含日記的標題與內容）。'
              : '只附基本資訊（App 版本、機型、系統版本、設定摘要）。', style: t.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 5,
            maxLines: 10,
            maxLength: Limits.feedbackMaxChars,
            decoration: InputDecoration(hintText: _hint, hintMaxLines: 3),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy || _text.text.trim().isEmpty ? null : _send,
              child: const Text('送出'),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      Text('需要先登入 Google，我們才能用 Email 回覆你。每天最多 ${Limits.feedbackPerDay} 則。', style: t.labelSmall),
    ]);
  }

  Future<void> _send() async {
    final feedback = ref.read(feedbackServiceProvider);
    if (ref.read(authUserProvider) == null) {
      // Sign in from here (a user tap), as mama-fufood's ensureSignedIn does.
      final ok = await confirmDialog(context, message: '送出意見回饋需要先登入 Google 帳號，我們才能用 Email 回覆你。要現在登入嗎？', confirm: '登入');
      if (!ok || !mounted) return;
      await signInFlow(context, ref);
      if (!mounted || ref.read(authUserProvider) == null) return;
    }
    setState(() => _busy = true);
    try {
      final draft = await feedback.prepare(_kind, _text.text);
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('這次會送出'),
          content: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              for (final (label, value) in draft.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '$label:', style: weight(Theme.of(ctx).textTheme.bodyMedium!, 500)),
                    TextSpan(text: value),
                  ])),
                ),
              Text('不會送出截圖、照片、位置與 IP 位址。', style: Theme.of(ctx).textTheme.bodySmall),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('確認送出')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final outcome = await feedback.submit(draft);
      if (!mounted) return;
      _text.clear();
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(outcome.sent ? '已送出，謝謝你' : '目前無法送出'),
          content: Text(outcome.sent
              ? '意見回饋編號：${outcome.id.substring(0, 8)}'
              : '目前無法送出，會在下次開啟 App 時自動重試。'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('好'))],
        ),
      );
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e, st) {
      AppLog.error('feedback.error', e, st);
      if (mounted) toast(context, '送出失敗，請稍後再試');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
