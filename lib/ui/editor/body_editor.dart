import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../core/constants.dart';
import '../../data/store.dart';
import '../../domain/diary.dart';
import '../theme.dart';

/// Opens a stored body in a Quill controller. A broken body opens empty rather than crashing.
QuillController controllerFor(String body, {required bool readOnly}) {
  Document doc;
  try {
    doc = Document.fromJson(jsonDecode(body) as List<dynamic>);
  } catch (_) {
    doc = Document();
  }
  return QuillController(document: doc, selection: const TextSelection.collapsed(offset: 0), readOnly: readOnly);
}

String bodyOf(QuillController c) => jsonEncode(c.document.toDelta().toJson());

/// The diary body on its off-white paper (spec §6). Sizes are stored in points and drawn at
/// 4/3 px per point by scaling text inside the body only.
class BodyEditor extends StatelessWidget {
  const BodyEditor({super.key, required this.controller, required this.store, required this.focusNode, required this.scroll});

  final QuillController controller;
  final Store store;
  final FocusNode focusNode;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final paper = Paper.of(context);
    final base = TextStyle(
      fontFamily: EditorSpec.defaultFontFamily,
      fontSize: EditorSpec.defaultFontSize.toDouble(),
      color: paper.text,
      height: 1.5,
    );
    final styles = DefaultStyles.getInstance(context).merge(DefaultStyles(
      paragraph: DefaultTextBlockStyle(
          base, const HorizontalSpacing(0, 0), const VerticalSpacing(0, 0), const VerticalSpacing(0, 0), null),
      placeHolder: DefaultTextBlockStyle(base.copyWith(color: paper.hint), const HorizontalSpacing(0, 0),
          const VerticalSpacing(0, 0), const VerticalSpacing(0, 0), null),
    ));
    return ColoredBox(
      color: paper.color,
      child: MediaQuery(
        data: mq.copyWith(textScaler: _PointScaler(mq.textScaler)),
        child: QuillEditor.basic(
          controller: controller,
          focusNode: focusNode,
          scrollController: scroll,
          config: QuillEditorConfig(
            placeholder: controller.readOnly ? null : '內文',
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            expands: true,
            customStyles: styles,
            showCursor: !controller.readOnly,
            embedBuilders: [_ImageEmbedBuilder(store)],
          ),
        ),
      ),
    );
  }
}

/// The system text scale times 4/3 (points → logical pixels).
class _PointScaler extends TextScaler {
  const _PointScaler(this.system);

  final TextScaler system;

  @override
  double scale(double fontSize) => system.scale(fontSize) * EditorSpec.pointToPixel;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => system.scale(1) * EditorSpec.pointToPixel;

  @override
  bool operator ==(Object other) => other is _PointScaler && other.system == system;

  @override
  int get hashCode => system.hashCode;
}

/// Draws a diary image at its stored size (it was shrunk to 1/3 of this screen's height), never
/// wider than the paper. Tapping opens it full screen where it can be zoomed (spec §6.2).
class _ImageEmbedBuilder extends EmbedBuilder {
  const _ImageEmbedBuilder(this.store);

  final Store store;

  @override
  String get key => DiaryBody.imageType;

  @override
  bool get expanded => false;

  @override
  String toPlainText(Embed node) => '';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final ref = ImageRef.tryParse(embedContext.node.value.data as String);
    if (ref == null) return const SizedBox.shrink();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final file = store.imageFile(ref.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => _ImageViewer(file: file),
        )),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ref.width / dpr),
          child: AspectRatio(
            aspectRatio: ref.width / ref.height,
            child: Image.file(
              file,
              fit: BoxFit.contain,
              errorBuilder: (context, _, _) {
                final paper = Paper.of(context);
                return ColoredBox(
                  color: paper.placeholderBox,
                  child: Center(child: Text('無法顯示這張圖片', style: TextStyle(color: paper.hint, fontSize: 12))),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('圖片')),
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(child: Image.file(file, fit: BoxFit.contain)),
        ),
      );
}
