import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'calendar/calendar_tab.dart';
import 'filter/filter_tab.dart';
import 'search/search_tab.dart';
import 'settings/settings_page.dart';
import 'settings/text_pages.dart';
import 'theme.dart';
import '../state/providers.dart';

/// A page opened from the ⋮ menu; it replaces the tab content and the top bar shows a back arrow.
class SubPage {
  const SubPage(this.title, this.builder);

  final String title;
  final WidgetBuilder builder;
}

class ShellState {
  const ShellState({this.tab = 0, this.sub});

  final int tab;
  final SubPage? sub;
}

class ShellController extends Notifier<ShellState> {
  @override
  ShellState build() => const ShellState();

  void selectTab(int tab) => state = ShellState(tab: tab);

  void open(SubPage page) => state = ShellState(tab: state.tab, sub: page);

  bool close() {
    if (state.sub == null) return false;
    state = ShellState(tab: state.tab);
    return true;
  }
}

final shellProvider = NotifierProvider<ShellController, ShellState>(ShellController.new);

/// Main screen (spec §1.2, §1.3): top bar「名字的日記」with the ⋮ menu; bottom bar with
/// 行事曆／篩選／搜尋 and a greyed-out fourth tab reserved for later.
class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  static const _tabs = [
    (Icons.calendar_month_rounded, '行事曆'),
    (Icons.filter_list_rounded, '篩選'),
    (Icons.search_rounded, '搜尋'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shell = ref.watch(shellProvider);
    final c = context.colors;
    final sub = shell.sub;
    return PopScope(
      canPop: sub == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(shellProvider.notifier).close();
      },
      child: Scaffold(
        appBar: _TopBar(sub: sub),
        body: sub != null
            ? sub.builder(context)
            : IndexedStack(index: shell.tab, children: const [CalendarTab(), FilterTab(), SearchTab()]),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: _TabItem(
                      icon: _tabs[i].$1,
                      label: _tabs[i].$2,
                      selected: sub == null && i == shell.tab,
                      onTap: () => ref.read(shellProvider.notifier).selectTab(i),
                    ),
                  ),
                // Tab 4 is reserved (spec §1): shown greyed out, does nothing.
                const Expanded(child: _TabItem(icon: Icons.more_horiz_rounded, label: '即將推出', selected: false, onTap: null)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final disabled = onTap == null;
    final color = disabled ? c.muted.withValues(alpha: 0.45) : (selected ? c.accent : c.text2);
    return InkWell(
      onTap: onTap,
      child: Semantics(
        selected: selected,
        button: true,
        enabled: !disabled,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: selected ? 28 : 22, color: color),
          const SizedBox(height: 2),
          Text(label,
              style: weight(Theme.of(context).textTheme.labelSmall!.copyWith(color: color, fontSize: 11), selected ? 500 : 400)),
        ]),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget implements PreferredSizeWidget {
  const _TopBar({required this.sub});

  final SubPage? sub;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final name = settingsOf(ref).userName ?? '';
    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: sub == null ? 16 : 0,
      leading: sub == null
          ? null
          : IconButton(
              tooltip: '返回',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => ref.read(shellProvider.notifier).close(),
            ),
      title: Text(sub?.title ?? '$name的日記', overflow: TextOverflow.ellipsis),
      actions: [
        PopupMenuButton<int>(
          tooltip: '更多',
          icon: const Icon(Icons.more_vert_rounded),
          color: c.surface2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onSelected: (i) => ref.read(shellProvider.notifier).open(switch (i) {
            0 => SubPage('App 設定', (_) => const SettingsPage()),
            1 => SubPage('使用者條款', (_) => const LegalPage(key: ValueKey('terms'), asset: 'terms')),
            _ => SubPage('隱私權政策', (_) => const LegalPage(key: ValueKey('privacy'), asset: 'privacy')),
          }),
          // 匯入/匯出 and 意見回饋 (spec §1.3) need Google sign-in and the backend; they join this menu
          // with those features.
          itemBuilder: (_) => const [
            PopupMenuItem(value: 0, child: Text('App 設定')),
            PopupMenuItem(value: 1, child: Text('使用者條款')),
            PopupMenuItem(value: 2, child: Text('隱私權政策')),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
