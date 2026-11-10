import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/store.dart';
import '../../state/providers.dart';
import '../theme.dart';
import 'name_dialog.dart';

/// First launch: set the user name before anything else (spec §1.1).
/// Import and restore-from-cloud join this page when those features arrive (as in mama-fufood).
class WelcomePage extends ConsumerWidget {
  const WelcomePage({super.key});

  Future<void> _setName(BuildContext context, WidgetRef ref) async {
    final name = await askUserName(context);
    if (name == null) return;
    await ref.read(storeProvider).setSetting(Keys.userName, name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(24, 32, 24, 24), children: [
              Icon(Icons.auto_stories_rounded, size: 56, color: c.accent),
              const SizedBox(height: 12),
              Text('全心日記', style: weight(t.titleLarge!.copyWith(fontSize: 22), 600), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text('先告訴我們你的名字，\n首頁會顯示成「你設定的名字」的日記。', style: t.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _setName(context, ref),
                icon: const Icon(Icons.edit_rounded),
                label: const Text('設定名字'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
