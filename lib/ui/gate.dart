import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/time.dart';
import '../state/providers.dart';
import 'editor/diary_page.dart';
import 'first_run/welcome_page.dart';
import 'shell.dart';
import 'widgets/common.dart';

/// Decides the first screen: the name setup on first launch, otherwise the main screen.
/// On reaching the main screen it offers to continue any unsaved draft (spec §6, auto draft).
class AppGate extends ConsumerStatefulWidget {
  const AppGate({super.key});

  @override
  ConsumerState<AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<AppGate> {
  bool _checkedDrafts = false;

  Future<void> _offerDrafts() async {
    _checkedDrafts = true;
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
    if (settings.value!.userName == null) return const WelcomePage();
    if (!_checkedDrafts) WidgetsBinding.instance.addPostFrameCallback((_) => _offerDrafts());
    return const MainShell();
  }
}
