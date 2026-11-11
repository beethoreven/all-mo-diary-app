import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log.dart';
import '../../data/store.dart';
import '../../services/sync_engine.dart';
import '../../state/providers.dart';
import '../settings/import_export_page.dart';
import '../settings/settings_page.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'name_dialog.dart';

/// First launch (no user name yet; also after reinstalling):
/// start fresh by setting a name, import an export file, or get the diaries back from the cloud.
/// Import and restore bring the name back too, so the main screen opens once they're done.
///
/// [onBusy]: an import or restore is running. The gate keeps this page up meanwhile even after the
/// name has arrived, so the flow (and its closing message) finishes before the screen changes.
class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key, required this.onBusy});

  final ValueChanged<bool> onBusy;

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  String? _step;
  bool _running = false;

  void _setStep(String? step) {
    if (mounted) setState(() => _step = step);
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() => _running = true);
    widget.onBusy(true);
    try {
      await task();
    } catch (e, st) {
      AppLog.error('first_run.failed', e, st);
      if (mounted) toast(context, '沒有成功，請稍後再試');
    } finally {
      if (mounted) setState(() => _running = false);
      _setStep(null);
      widget.onBusy(false);
    }
  }

  Future<void> _setName() async {
    final name = await askUserName(context);
    if (name == null) return;
    await saveUserName(ref, name);
  }

  Future<void> _import() => _run(() => importFlow(context, ref));

  Future<void> _restore() => _run(() async {
        if (!await ensureSignedIn(context, ref, '從雲端取回需要先登入之前同步用的 Google 帳號。要現在登入嗎？') || !mounted) return;
        final sync = ref.read(syncEngineProvider);
        final store = ref.read(storeProvider);
        _setStep('正在從雲端取回日記，請勿關閉 App');
        try {
          await sync.setDiariesOn(true);
          await sync.whenIdle();
        } on SyncProblem catch (e) {
          if (mounted) toast(context, e.message, duration: const Duration(seconds: 5));
          return;
        }
        final name = await store.getSetting(Keys.userName);
        final diaries = (await store.counts())['diaries'] ?? 0;
        AppLog.info('first_run.restore', {'state': sync.state.name, 'diaries': diaries, 'name': name != null});
        if (!mounted) return;
        if (name != null) {
          toast(context, diaries > 0 ? '已從雲端取回 $diaries 篇日記' : '已從雲端取回', duration: const Duration(seconds: 4));
          return;
        }
        _setStep(null);
        final message = sync.state == SyncState.ok
            ? '雲端上沒有找到之前同步的日記。請按「設定名字」開始寫，或改用匯出檔匯入。\n\n「日記與雲端同步」已經打開，之後寫的日記會同步到雲端。'
            : '這次沒有取回成功：${sync.lastError ?? '請確認網路後再試一次'}';
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: Text(message),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('好'))],
          ),
        );
      });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: ValueListenableBuilder<String?>(
            valueListenable: ref.watch(exportServiceProvider).step,
            builder: (context, importStep, _) {
              final step = _step ?? importStep;
              final busy = _running || step != null;
              return ListView(padding: const EdgeInsets.fromLTRB(24, 32, 24, 24), children: [
                Icon(Icons.auto_stories_rounded, size: 56, color: c.accent),
                const SizedBox(height: 12),
                Text('全心日記', style: weight(t.titleLarge!.copyWith(fontSize: 22), 600), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text('先告訴我們你的名字，\n首頁會顯示成「你設定的名字」的日記。', style: t.bodyMedium, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy ? null : _setName,
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('設定名字'),
                ),
                const SizedBox(height: 28),
                Text('之前用過這個 App 嗎？', style: t.titleSmall),
                const SizedBox(height: 8),
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('有之前匯出的檔案（.amd），可以直接匯入。要用匯出時的 Google 帳號登入。', style: t.bodyMedium),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _import,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('從匯出檔匯入'),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('之前有開「日記與雲端同步」的話，登入同一個 Google 帳號就能取回，並自動打開同步。', style: t.bodyMedium),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _restore,
                      icon: const Icon(Icons.cloud_download_rounded),
                      label: const Text('從雲端取回'),
                    ),
                  ]),
                ),
                if (step != null) ...[
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Flexible(child: Text('$step…', style: t.bodyMedium)),
                  ]),
                ],
              ]);
            },
          ),
        ),
      ),
    );
  }
}
