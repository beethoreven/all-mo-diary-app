import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../widgets/common.dart';

/// 使用者條款 / 隱私權政策: a Markdown file bundled as `assets/texts/<asset>.md`.
class LegalPage extends StatefulWidget {
  const LegalPage({super.key, required this.asset});

  final String asset;

  @override
  State<LegalPage> createState() => _LegalPageState();
}

class _LegalPageState extends State<LegalPage> {
  // Loaded once: a Future created in build would reload (and spin) on every rebuild.
  late final Future<String> _text = rootBundle.loadString('assets/texts/${widget.asset}.md');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return FutureBuilder<String>(
      future: _text,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
          MarkdownBody(
            data: snap.data!,
            // GitHub-flavoured: bare URLs and the e-mail address become tappable links.
            extensionSet: md.ExtensionSet.gitHubFlavored,
            onTapLink: (_, href, _) => openLink(context, href),
            styleSheet: MarkdownStyleSheet(
              h2: weight(t.titleMedium!, 500),
              p: t.bodyMedium!.copyWith(height: 1.6),
              listBullet: t.bodyMedium,
              tableBody: t.bodySmall!.copyWith(color: c.text),
              tableHead: weight(t.bodySmall!.copyWith(color: c.text), 500),
              tableBorder: TableBorder.all(color: c.border, width: 0.5),
              tableCellsPadding: const EdgeInsets.all(6),
              a: t.bodyMedium!.copyWith(color: c.accent, decoration: TextDecoration.underline),
            ),
          ),
        ]);
      },
    );
  }
}

/// Opens an https link in the browser or a mailto link in a mail app; anything else is ignored.
Future<void> openLink(BuildContext context, String? href) async {
  final uri = href == null ? null : Uri.tryParse(href);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'mailto')) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!ok && context.mounted) {
    toast(context, uri.scheme == 'mailto' ? '找不到可以寄信的 App，請手動寄到 ${uri.path}' : '打不開這個網址');
  }
}
