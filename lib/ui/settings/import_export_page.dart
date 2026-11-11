import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/log.dart';
import '../../services/auth_service.dart';
import '../../services/drive_store.dart';
import '../../services/export_service.dart';
import '../../state/providers.dart';
import '../shell.dart';
import '../widgets/common.dart';

/// 匯入/匯出 (spec §1.3, terms §3), as mama-fufood: exports go to the user's own Drive folder
/// 「全心日記」, encrypted; importing needs the Google account that exported the file.
class ImportExportPage extends ConsumerStatefulWidget {
  const ImportExportPage({super.key});

  @override
  ConsumerState<ImportExportPage> createState() => _ImportExportPageState();
}

class _ImportExportPageState extends ConsumerState<ImportExportPage> {
  String? _step;

  Future<bool> _signedIn() async {
    if (ref.read(authUserProvider) != null) return true;
    final ok = await confirmDialog(context, message: '匯出與匯入需要先登入 Google 帳號（金鑰存在你的雲端硬碟）。要現在登入嗎？', confirm: '登入');
    if (!ok || !mounted) return false;
    await signInFlow(context, ref);
    return mounted && ref.read(authUserProvider) != null;
  }

  Future<Directory> _tmp() async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/amd_transfer');
    if (await dir.exists()) await dir.delete(recursive: true);
    return dir;
  }

  String _message(Object e) => switch (e) {
        ExportProblem() => e.message,
        CloudError() => e.message,
        DriveNotAuthorized() => '需要雲端硬碟的權限才能匯出或匯入',
        NotSignedIn() => '請先用 Google 帳號登入',
        _ => '沒有成功，請稍後再試',
      };

  Future<void> _export() async {
    if (!await _signedIn()) return;
    setState(() => _step = '正在匯出，請勿關閉 App');
    try {
      final name = await ref.read(exportServiceProvider).export(await _tmp());
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('匯出完成'),
            content: Text('已存到你的 Google 雲端硬碟「全心日記」資料夾：\n$name\n\n'
                '這個檔案已加密，只有用這個 Google 帳號登入全心日記才能匯入。'),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('好'))],
          ),
        );
      }
    } catch (e, st) {
      AppLog.error('export.failed', e, st);
      if (mounted) toast(context, _message(e), duration: const Duration(seconds: 5));
    } finally {
      if (mounted) setState(() => _step = null);
    }
  }

  Future<void> _import() async {
    if (!await _signedIn()) return;
    final picked = await FilePicker.pickFiles(type: FileType.any);
    final path = picked.isEmpty ? null : picked.single.path;
    if (path == null || !mounted) return;
    setState(() => _step = '正在讀取匯出檔');
    final service = ref.read(exportServiceProvider);
    try {
      final opened = await service.open(File(path), await _tmp());
      final conflicts = await service.conflicts(opened.data);
      var choice = ImportConflict.keepPhone;
      if (conflicts.isNotEmpty && mounted) {
        final picked = await showDialog<ImportConflict>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('有些日子手機上已經有日記'),
            content: Text('${conflicts.length} 天手機上已經有另一篇日記（例如 ${conflicts.first.label}）。要怎麼處理？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消匯入')),
              TextButton(onPressed: () => Navigator.pop(ctx, ImportConflict.useImported), child: const Text('用匯入的取代')),
              FilledButton(onPressed: () => Navigator.pop(ctx, ImportConflict.keepPhone), child: const Text('保留手機上的')),
            ],
          ),
        );
        if (picked == null) return;
        choice = picked;
      }
      if (!mounted) return;
      setState(() => _step = '正在匯入');
      final result = await service.apply(opened.data, opened.images, choice);
      await ref.read(syncEngineProvider).syncNow();
      if (mounted) {
        toast(context, '匯入完成：新增 ${result.added} 篇'
            '${result.replaced > 0 ? '、取代 ${result.replaced} 篇' : ''}${result.kept > 0 ? '、保留手機上的 ${result.kept} 篇' : ''}',
            duration: const Duration(seconds: 4));
      }
    } catch (e, st) {
      AppLog.error('import.failed', e, st);
      if (mounted) toast(context, _message(e), duration: const Duration(seconds: 5));
    } finally {
      if (mounted) setState(() => _step = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final busy = _step != null;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('匯出', style: t.titleSmall),
          const SizedBox(height: 6),
          Text('把手機上全部的日記（含圖片與使用者名稱）存成一個加密檔，放到你的 Google 雲端硬碟「全心日記」資料夾。'
              '只有用同一個 Google 帳號才能匯入。', style: t.bodyMedium),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: busy ? null : _export, icon: const Icon(Icons.upload_rounded), label: const Text('匯出')),
        ]),
      ),
      const SizedBox(height: 12),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('匯入', style: t.titleSmall),
          const SizedBox(height: 6),
          Text('選一個全心日記的匯出檔（.amd）。選檔畫面可以直接開雲端硬碟的「全心日記」資料夾。'
              '同一篇日記保留比較新的版本；手機上同一天已經有另一篇時，會問你要保留哪一篇。', style: t.bodyMedium),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: busy ? null : _import, icon: const Icon(Icons.download_rounded), label: const Text('匯入')),
        ]),
      ),
      if (busy) ...[
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Flexible(child: Text('$_step…', style: t.bodyMedium)),
        ]),
      ],
    ]);
  }
}
