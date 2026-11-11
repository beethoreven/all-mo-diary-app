import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/log.dart';
import '../services/auth_service.dart';
import 'widgets/common.dart';

import 'calendar/calendar_tab.dart';
import 'filter/filter_tab.dart';
import 'search/search_tab.dart';
import 'settings/settings_page.dart';
import 'settings/feedback_page.dart';
import 'settings/import_export_page.dart';
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

/// Main screen: top bar「名字的日記」with the ⋮ menu; bottom bar with
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
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    Expanded(
                      child: _TabItem(
                        icon: _tabs[i].$1,
                        label: _tabs[i].$2,
                        selected: sub == null && i == shell.tab,
                        onTap: () => ref.read(shellProvider.notifier).selectTab(i),
                      ),
                    ),
                  // Tab 4 is reserved: shown greyed out, does nothing.
                  const Expanded(
                    child: _TabItem(icon: Icons.more_horiz_rounded, label: '即將推出', selected: false, onTap: null),
                  ),
                ],
              ),
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: selected ? 28 : 22, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: weight(
                Theme.of(context).textTheme.labelSmall!.copyWith(color: color, fontSize: 11),
                selected ? 500 : 400,
              ),
            ),
          ],
        ),
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
        const _AccountButton(),
        PopupMenuButton<int>(
          tooltip: '更多',
          icon: const Icon(Icons.more_vert_rounded),
          color: c.surface2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onSelected: (i) => ref.read(shellProvider.notifier).open(switch (i) {
            0 => SubPage('App 設定', (_) => const SettingsPage()),
            1 => SubPage('匯入/匯出', (_) => const ImportExportPage()),
            2 => SubPage('使用者條款', (_) => const LegalPage(key: ValueKey('terms'), asset: 'terms')),
            3 => SubPage('隱私權政策', (_) => const LegalPage(key: ValueKey('privacy'), asset: 'privacy')),
            _ => SubPage('意見回饋', (_) => const FeedbackPage()),
          }),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 0, child: Text('App 設定')),
            PopupMenuItem(value: 1, child: Text('匯入/匯出')),
            PopupMenuItem(value: 2, child: Text('使用者條款')),
            PopupMenuItem(value: 3, child: Text('隱私權政策')),
            PopupMenuDivider(),
            PopupMenuItem(value: 4, child: Text('意見回饋')),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// Sign-in entry in the top bar, left of the ⋮ menu: a Google "G" when
/// signed out, the account avatar when signed in; tapping the avatar shows the e-mail and 登出.
class _AccountButton extends ConsumerWidget {
  const _AccountButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider);
    final c = context.colors;
    if (user == null) {
      return IconButton(
        tooltip: '用 Google 帳號登入',
        icon: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: c.border),
          ),
          child: const Text(
            'G',
            style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
        onPressed: () => signInFlow(context, ref),
      );
    }
    // The pass has expired (long unused, or the server refused it): a small dot on the avatar; the
    // account sheet offers 重新登入. The phone's diaries are unaffected either way.
    final expired = ref.watch(authStateProvider) == AuthState.sessionExpired;
    final avatar = CircleAvatar(
      radius: 15,
      backgroundColor: c.accentSoft,
      foregroundImage: user.photoUrl == null ? null : NetworkImage(user.photoUrl!),
      child: Text(user.email.characters.first.toUpperCase(), style: TextStyle(color: c.text, fontSize: 14)),
    );
    return IconButton(
      tooltip: expired ? '登入已過期，請重新登入' : user.email,
      icon: expired ? Badge(backgroundColor: c.danger, child: avatar) : avatar,
      onPressed: () => showAccountSheet(context, ref, user),
    );
  }
}

Future<void> signInFlow(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(authServiceProvider).signIn();
    if (context.mounted) toast(context, '已登入');
  } catch (e) {
    AppLog.warn('auth.sign_in_failed', {'type': e.runtimeType.toString()});
    if (context.mounted) toast(context, _signInMessage(e));
  }
}

/// Signed in already, or asks (with [message]) and signs in now. true when signed in afterwards.
Future<bool> ensureSignedIn(BuildContext context, WidgetRef ref, String message) async {
  if (ref.read(authUserProvider) != null) return true;
  final ok = await confirmDialog(context, message: message, confirm: '登入');
  if (!ok || !context.mounted) return false;
  await signInFlow(context, ref);
  return context.mounted && ref.read(authUserProvider) != null;
}

String _signInMessage(Object e) {
  final text = e.toString();
  if (text.contains('canceled')) return '已取消登入';
  if (text.contains('還沒設定')) return text.replaceFirst('Bad state: ', '');
  return '登入沒有成功，請稍後再試';
}

Future<void> showAccountSheet(BuildContext context, WidgetRef ref, SignedInUser u) async {
  final auth = ref.read(authServiceProvider);
  final expired = auth.state == AuthState.sessionExpired;
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.account_circle_rounded),
            title: Text(u.name ?? u.email),
            subtitle: Text(u.email),
          ),
          if (expired)
            ListTile(
              leading: Icon(Icons.login_rounded, color: ctx.colors.danger),
              title: const Text('重新登入'),
              subtitle: const Text('登入已過期。手機上的日記不受影響，重新登入後才能使用需要連線的功能。'),
              onTap: () => Navigator.pop(ctx, 'relogin'),
            ),
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: const Text('登出'),
            onTap: () => Navigator.pop(ctx, 'logout'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (action == 'relogin') return signInFlow(context, ref);
  if (action != 'logout') return;
  final ok = await confirmDialog(context, message: '要登出嗎？手機上的日記會保留。', confirm: '登出');
  if (!ok) return;
  await auth.signOut();
  if (context.mounted) toast(context, '已登出');
}
