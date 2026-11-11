import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/log.dart';
import '../core/time.dart';
import '../services/daily_check.dart';
import '../services/feedback_service.dart';
import '../state/providers.dart';
import 'editor/diary_page.dart';
import 'first_run/welcome_page.dart';
import 'settings/feedback_page.dart';
import 'settings/text_pages.dart';
import 'shell.dart';
import 'widgets/common.dart';

/// Decides the first screen: the first-launch page (set a name, import, or restore) when there is no
/// name, a forced-update screen when this version is below the minimum, otherwise the main screen.
/// On reaching the main screen (and on every return to the app) it runs the daily check and the cloud
/// sync, offers an unsaved draft, and shows a new announcement once.
class AppGate extends ConsumerStatefulWidget {
  const AppGate({super.key});

  @override
  ConsumerState<AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<AppGate> with WidgetsBindingObserver {
  bool _started = false;

  /// An import or restore on the first-launch page is running: stay on that page until it's done.
  bool _firstRunBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _started) {
      AppLog.info('app.resumed');
      unawaited(_background());
    }
  }

  /// The daily check and the sync; neither ever shows a Google screen by itself.
  Future<void> _background() async {
    final check = ref.read(dailyCheckProvider);
    await check.maybeRun();
    unawaited(ref.read(syncEngineProvider).maybeSync());
    // Unsent feedback (no network when it was sent) goes out now, at most 5 tries a day.
    unawaited(ref.read(feedbackServiceProvider).retryQueued().catchError((_) => 0));
    if (!mounted) return;
    final text = await check.takeAnnouncement();
    if (text != null && mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('公告'),
          content: Text(text),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了'))],
        ),
      );
    }
  }

  /// After the app closed unexpectedly (crash, not responding, native crash): ask once a day whether
  /// to send feedback. Only asks; nothing is sent automatically. Returns true when
  /// the feedback page was opened.
  Future<bool> _offerCrashFeedback() async {
    final exit = await ref.read(diagnosticsProvider).unexpectedExit();
    if (exit == null || !mounted) return false;
    final go = await confirmDialog(context, message: 'App 上次意外關閉，要送出意見回饋告訴我們嗎？', confirm: '要', cancel: '不要');
    if (!mounted) return false;
    if (go) {
      ref.read(shellProvider.notifier).open(SubPage('意見回饋', (_) => const FeedbackPage(kind: FeedbackKind.problem)));
      return true;
    }
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        content: const Text('如果問題持續發生，可以點右上角選單的「意見回饋」告訴我們，我們會嘗試修正。'),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('好'))],
      ),
    );
    return false;
  }

  Future<void> _onMainScreen() async {
    _started = true;
    await _background();
    if (!mounted) return;
    if (await _offerCrashFeedback() || !mounted) return;
    final store = ref.read(storeProvider);
    final drafts = await store.drafts();
    if (drafts.isEmpty || !mounted) return;
    final latest = drafts.first;
    final day = Day.parse(latest.day);
    final resume = await confirmDialog(context,
        message: '${day.label}有上次沒儲存的內容，要接著寫嗎？', confirm: '接著寫', cancel: '不要');
    if (!mounted) return;
    if (resume) {
      await openDiary(context, day: day, resume: latest);
    } else {
      await store.deleteDraft(latest.key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    if (!settings.hasValue) return const Scaffold(body: SizedBox.shrink());
    final s = settings.value!;
    AppLog.userName = s.userName;
    // First launch: set a name, import, or restore from the cloud (an import or restore that is
    // still running keeps this page even once the name has come back).
    if (s.userName == null || _firstRunBusy) {
      return WelcomePage(onBusy: (busy) {
        if (mounted) setState(() => _firstRunBusy = busy);
      });
    }
    final min = s.raw[CheckKeys.forceMin];
    if (min != null && DailyCheckService.compareVersions(ref.read(appVersionProvider), min) < 0) {
      return _ForceUpdatePage(reason: s.raw[CheckKeys.forceReason] ?? '', url: s.raw[CheckKeys.forceUrl] ?? '');
    }
    if (!_started) WidgetsBinding.instance.addPostFrameCallback((_) => _onMainScreen());
    return const MainShell();
  }
}

/// This version is below the minimum set in the admin console: explain why and link to the update.
/// The diaries stay on the phone; checking again (the minimum may have been lowered) is one tap away.
class _ForceUpdatePage extends ConsumerStatefulWidget {
  const _ForceUpdatePage({required this.reason, required this.url});

  final String reason;
  final String url;

  @override
  ConsumerState<_ForceUpdatePage> createState() => _ForceUpdatePageState();
}

class _ForceUpdatePageState extends ConsumerState<_ForceUpdatePage> {
  bool _checking = false;

  Future<void> _recheck() async {
    setState(() => _checking = true);
    try {
      final check = ref.read(dailyCheckProvider);
      final message = await check.run();
      final stillForced = await check.forceUpdate() != null;
      if (mounted && stillForced) toast(context, message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24), children: [
              const Icon(Icons.system_update_rounded, size: 56),
              const SizedBox(height: 12),
              Text('請更新全心日記', style: t.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(widget.reason.isEmpty ? '這個版本已經不能使用，請更新到最新版。' : widget.reason,
                  style: t.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('手機上的日記不會受影響。', style: t.bodySmall, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              if (widget.url.isNotEmpty)
                FilledButton(onPressed: () => openLink(context, widget.url), child: const Text('前往更新')),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _checking ? null : _recheck, child: Text(_checking ? '檢查中…' : '重新檢查')),
            ]),
          ),
        ),
      ),
    );
  }
}
