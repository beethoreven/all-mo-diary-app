import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/store.dart';
import '../../state/providers.dart';
import '../first_run/name_dialog.dart';
import '../theme.dart';

/// App 設定 (spec §8). This version has the user name, display options, app version and open-source
/// licences; cloud sync, the font list / font settings and the update check need Google sign-in and
/// the backend, and arrive with those features.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = settingsOf(ref);
    final store = ref.read(storeProvider);
    final t = Theme.of(context).textTheme;
    Widget section(String title) =>
        Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 8), child: Text(title, style: weight(t.titleSmall!, 600)));
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      section('個人'),
      ListTile(
        title: const Text('使用者名稱'),
        subtitle: Text(settings.userName ?? ''),
        trailing: const Icon(Icons.edit_rounded),
        onTap: () async {
          final name = await askUserName(context, initial: settings.userName ?? '');
          if (name != null) await store.setSetting(Keys.userName, name);
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

class _VersionTile extends StatefulWidget {
  const _VersionTile();

  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
        future: _info,
        builder: (context, snap) => ListTile(
          title: const Text('App 版本'),
          subtitle: Text(snap.hasData ? '${snap.data!.version}（${snap.data!.buildNumber}）' : ''),
        ),
      );
}
