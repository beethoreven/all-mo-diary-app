import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/time.dart';
import '../../data/store.dart';
import '../../services/auth_service.dart';
import '../../services/daily_check.dart';
import '../../services/sync_engine.dart';
import '../../state/providers.dart';
import '../first_run/name_dialog.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'font_settings_page.dart';

/// Saves a new user name and stamps when it changed, so the newer name wins in the cloud.
Future<void> saveUserName(WidgetRef ref, String name) async {
  final store = ref.read(storeProvider);
  await store.setSetting(Keys.userName, name);
  await store.setSetting(SyncKeys.profileUpdatedAt, '${TimeRules.nowMs()}');
  await ref.read(syncEngineProvider).syncNow();
}

/// App 設定: user name, display, cloud (two switches), the font list and
/// font settings, update check, app version, open-source licences.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _busy = false;
  String? _checkResult;

  Future<void> _toggle(Future<void> Function() action) async {
    if (ref.read(authUserProvider) == null) {
      toast(context, '請先用右上角的按鈕登入 Google 帳號');
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } on SyncProblem catch (e) {
      if (mounted) toast(context, e.message, duration: const Duration(seconds: 5));
    } catch (e) {
      if (mounted) toast(context, '沒有成功：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Checks left today, from the settings already watched here (so the line updates after a check).
  int? _checksLeft(Map<String, String?> raw) =>
      raw[CheckKeys.checksLeftDay] == '${TimeRules.today()}' ? int.tryParse(raw[CheckKeys.checksLeft] ?? '') : null;

  String _time(String? ms) {
    final v = int.tryParse(ms ?? '');
    if (v == null) return '還沒有';
    final t = DateTime.fromMillisecondsSinceEpoch(v).toLocal();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${t.year}/${two(t.month)}/${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = settingsOf(ref);
    final raw = settings.raw;
    final store = ref.read(storeProvider);
    final sync = ref.read(syncEngineProvider);
    final syncState = ref.watch(syncStateProvider);
    final signedIn = ref.watch(authUserProvider) != null;
    final expired = ref.watch(authStateProvider) == AuthState.sessionExpired;
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final diariesOn = raw[SyncKeys.diaries] == '1';
    final imagesOn = raw[SyncKeys.images] == '1';
    final fonts = ref.read(dailyCheckProvider);
    Widget section(String title) =>
        Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 8), child: Text(title, style: weight(t.titleSmall!, 600)));
    final lastLine = syncState == SyncState.running
        ? '正在同步，請勿關閉 App'
        : raw[SyncKeys.lastError] != null
            ? '上次同步沒有成功：${raw[SyncKeys.lastError]}'
            : '最後同步：${_time(raw[SyncKeys.lastOk])}';
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      section('個人'),
      ListTile(
        title: const Text('使用者名稱'),
        subtitle: Text(settings.userName ?? ''),
        trailing: const Icon(Icons.edit_rounded),
        onTap: () async {
          final name = await askUserName(context, initial: settings.userName ?? '');
          if (name != null) await saveUserName(ref, name);
        },
      ),
      section('顯示'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          const Expanded(child: Text('週起始日')),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'monday', label: Text('星期一')),
              ButtonSegment(value: 'sunday', label: Text('星期日')),
            ],
            selected: {settings.weekStartsMonday ? 'monday' : 'sunday'},
            onSelectionChanged: (v) => store.setSetting(Keys.weekStart, v.first),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('主題'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'system', label: Text('跟隨系統')),
              ButtonSegment(value: 'light', label: Text('淺色')),
              ButtonSegment(value: 'dark', label: Text('深色')),
            ],
            selected: {settings.themeCode},
            onSelectionChanged: (v) => store.setSetting(Keys.theme, v.first),
          ),
        ]),
      ),
      section('雲端'),
      if (!signedIn)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('用右上角的按鈕登入 Google 帳號後才能使用雲端功能。', style: t.bodySmall),
        ),
      SwitchListTile(
        title: const Text('日記與雲端同步'),
        subtitle: Text(signedIn && diariesOn ? '存到你自己的 Google 雲端硬碟中只有本 App 能讀取的區域\n$lastLine' : '存到你自己的 Google 雲端硬碟中只有本 App 能讀取的區域'),
        isThreeLine: signedIn && diariesOn,
        value: diariesOn,
        onChanged: _busy || syncState == SyncState.running ? null : (v) => _toggle(() => sync.setDiariesOn(v)),
      ),
      SwitchListTile(
        title: const Text('圖片存到雲端'),
        subtitle: const Text('存到你的雲端硬碟「全心日記/圖片」資料夾，上傳成功並核對無誤後才刪掉手機上的圖片'),
        isThreeLine: true,
        value: imagesOn,
        onChanged: _busy || syncState == SyncState.running ? null : (v) => _toggle(() => sync.setImagesOn(v)),
      ),
      if (imagesOn && !diariesOn)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('只開了「圖片存到雲端」：日記的文字沒有雲端備份，手機遺失時文字救不回來。建議也打開「日記與雲端同步」。',
              style: t.bodySmall!.copyWith(color: c.danger)),
        ),
      if (diariesOn || imagesOn)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: syncState == SyncState.running || !signedIn
                  ? null
                  : () async {
                      await sync.syncNow(interactive: true);
                      if (context.mounted) toast(context, sync.state == SyncState.ok ? '同步完成' : (sync.lastError ?? '同步沒有成功'));
                    },
              icon: const Icon(Icons.sync_rounded),
              label: const Text('現在同步'),
            ),
          ),
        ),
      section('字體與版本'),
      ListTile(
        title: const Text('字體設定'),
        subtitle: const Text('安裝或刪除日記可以用的字體'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => ref.read(shellProvider.notifier).open(SubPage('字體設定', (_) => const FontSettingsPage())),
      ),
      FutureBuilder(
        future: fonts.fontCatalog(),
        builder: (context, snap) => ListTile(
          title: const Text('檢查更新'),
          subtitle: Text([
            '字體清單 ${snap.data?.version ?? '還沒有'}｜最後檢查：${_time(raw[CheckKeys.lastAt])}',
            '每天最多檢查 ${Limits.checksPerDay} 次（含開 App 時的自動檢查）'
                '${_checksLeft(raw) == null ? '' : '，今天還有 ${_checksLeft(raw)} 次'}',
            if (!signedIn) '需要登入 Google 帳號才能檢查。',
            if (expired) '登入已過期，請重新登入。',
            ?_checkResult,
          ].join('\n')),
          trailing: TextButton(
            onPressed: !signedIn || _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    final result = await fonts.run();
                    if (mounted) {
                      setState(() {
                        _busy = false;
                        _checkResult = result;
                      });
                    }
                  },
            child: const Text('檢查'),
          ),
        ),
      ),
      section('關於'),
      const _VersionTile(),
      ListTile(
        title: const Text('開放原始碼授權'),
        subtitle: const Text('本 App 使用的套件與字型（Noto Sans TC 等）的授權條款'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => showLicensePage(context: context, applicationName: '全心日記'),
      ),
    ]);
  }
}

class _VersionTile extends ConsumerWidget {
  const _VersionTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ListTile(title: const Text('App 版本'), subtitle: Text(ref.watch(appVersionProvider)));
}
