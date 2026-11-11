import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../domain/font_catalog.dart';
import '../../services/font_manager.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

/// 字體設定 (spec §9): 已安裝字體 / 未安裝字體, together the whole font list. Each shows its size on
/// the phone and whether its licence is confirmed. Names come from the admin console, not the file.
class FontSettingsPage extends ConsumerStatefulWidget {
  const FontSettingsPage({super.key});

  @override
  ConsumerState<FontSettingsPage> createState() => _FontSettingsPageState();
}

class _FontSettingsPageState extends ConsumerState<FontSettingsPage> {
  late Future<(FontCatalog, Set<int>)> _data = _load();

  Future<(FontCatalog, Set<int>)> _load() async {
    final catalog = await ref.read(dailyCheckProvider).fontCatalog();
    final fonts = ref.read(fontManagerProvider);
    final installed = <int>{
      for (final f in catalog.fonts)
        if (await fonts.isInstalled(f)) f.id,
    };
    return (catalog, installed);
  }

  void _reload() => setState(() => _data = _load());

  Future<void> _install(FontInfo f) async {
    if (f.fontBytes > FontManager.askAboveBytes) {
      final ok = await confirmDialog(context,
          message: '「${f.name}」安裝後佔 ${_mb(f.fontBytes)}，要下載 ${_mb(f.downloadBytes)}。要安裝嗎？', confirm: '安裝');
      if (!ok) return;
    }
    try {
      await ref.read(fontManagerProvider).install(f);
      if (mounted) toast(context, '已安裝「${f.name}」');
    } on FontProblem catch (e) {
      if (mounted) toast(context, e.message);
    }
    if (mounted) _reload();
  }

  Future<void> _remove(FontInfo f) async {
    final ok = await confirmDialog(context,
        message: '要刪除「${f.name}」嗎？用了這個字體的日記會先用預設字體顯示，重新安裝就會恢復。', confirm: '刪除', danger: true);
    if (!ok) return;
    await ref.read(fontManagerProvider).uninstall(f);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final manager = ref.watch(fontManagerProvider);
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) => FutureBuilder<(FontCatalog, Set<int>)>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: TextButton(onPressed: _reload, child: const Text('讀不到字體清單，點一下重試')));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (catalog, installed) = snap.data!;
          Widget license(FontInfo f) => Text(f.licensed ? '有授權' : '未確認授權',
              style: t.labelSmall!.copyWith(color: f.licensed ? c.text2 : c.danger));
          final installedTiles = [
            ListTile(
              title: const Text(EditorSpec.defaultFontName, style: TextStyle(fontFamily: EditorSpec.defaultFontFamily)),
              subtitle: const Text('內建（不能刪除）｜SIL Open Font License'),
            ),
            for (final f in catalog.fonts.where((f) => installed.contains(f.id)))
              ListTile(
                title: Text(f.name),
                subtitle: Row(children: [Text('${_mb(f.fontBytes)}｜'), license(f)]),
                trailing: IconButton(tooltip: '刪除字體', icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _remove(f)),
              ),
          ];
          final available = catalog.fonts.where((f) => !installed.contains(f.id) && !f.disabled).toList();
          return ListView(children: [
            ExpansionTile(
              initiallyExpanded: true,
              title: Text('已安裝字體（${installedTiles.length}）'),
              children: installedTiles,
            ),
            ExpansionTile(
              initiallyExpanded: true,
              title: Text('未安裝字體（${available.length}）'),
              children: [
                if (catalog.fonts.isEmpty)
                  const ListTile(subtitle: Text('還沒有字體清單：登入 Google 帳號後，到 App 設定按「檢查更新」。')),
                for (final f in available)
                  ListTile(
                    title: Text(f.name),
                    subtitle: Row(children: [Text('安裝後 ${_mb(f.fontBytes)}（下載 ${_mb(f.downloadBytes)}）｜'), license(f)]),
                    trailing: manager.isInstalling(f)
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : IconButton(tooltip: '安裝字體', icon: const Icon(Icons.download_rounded), onPressed: () => _install(f)),
                  ),
              ],
            ),
          ]);
        },
      ),
    );
  }
}
