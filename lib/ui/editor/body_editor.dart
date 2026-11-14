import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../core/constants.dart';
import '../../core/time.dart';
import '../../domain/diary.dart';
import '../theme.dart';
import 'video_player_page.dart';

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

/// The diary body on its off-white paper. Sizes are stored in points and drawn at
/// 4/3 px per point by scaling text inside the body only.
class BodyEditor extends StatelessWidget {
  const BodyEditor(
      {super.key, required this.controller, required this.media, required this.focusNode, required this.scroll});

  final QuillController controller;

  /// The files of the body's images and videos.
  final MediaSource media;
  final FocusNode focusNode;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final paper = Paper.of(context);
    final base = TextStyle(
      fontFamily: EditorSpec.defaultFontFamily,
      // Characters a downloaded font lacks, and fonts not installed on this phone, show in the
      // built-in font.
      fontFamilyFallback: const [EditorSpec.defaultFontFamily],
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
            embedBuilders: [_ImageEmbedBuilder(media.image), _VideoEmbedBuilder(media)],
            unknownEmbedBuilder: const _UnknownEmbedBuilder(),
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
/// wider than the paper. Tapping opens it full screen where it can be zoomed.
class _ImageEmbedBuilder extends EmbedBuilder {
  const _ImageEmbedBuilder(this.resolve);

  final Future<File?> Function(String id) resolve;

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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ref.width / dpr),
        child: AspectRatio(aspectRatio: ref.width / ref.height, child: _DiaryImage(id: ref.id, resolve: resolve)),
      ),
    );
  }
}

/// Draws a diary video as its cover (its first frame, an image like any other) at the stored size,
/// with a play mark and its length. Tapping plays it over the whole screen.
class _VideoEmbedBuilder extends EmbedBuilder {
  const _VideoEmbedBuilder(this.media);

  final MediaSource media;

  @override
  String get key => DiaryBody.videoType;

  @override
  bool get expanded => false;

  @override
  String toPlainText(Embed node) => '';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final ref = VideoRef.tryParse(embedContext.node.value.data as String);
    if (ref == null) return const SizedBox.shrink();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ref.width / dpr),
        child: AspectRatio(
          aspectRatio: ref.width / ref.height,
          child: Semantics(
            button: true,
            label: '播放影片，長度 ${clockText(ref.durationMs)}',
            child: Stack(fit: StackFit.expand, children: [
              _DiaryImage(
                id: ref.coverId,
                resolve: media.image,
                // Whatever the cover shows (the picture, or that it needs the network), a tap plays.
                onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => VideoPlayerPage(id: ref.id, media: media),
                )),
              ),
              const IgnorePointer(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36)),
                  ),
                ),
              ),
              Positioned(
                right: 6,
                bottom: 6,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      // Fixed size: the length mark belongs to the picture, not to the body's text sizes.
                      child: Text(clockText(ref.durationMs),
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Something a newer version of the app put in the diary. It is kept as it is (saving doesn't drop
/// it); this version only can't show it.
class _UnknownEmbedBuilder extends EmbedBuilder {
  const _UnknownEmbedBuilder();

  @override
  String get key => 'unknown';

  @override
  bool get expanded => false;

  @override
  String toPlainText(Embed node) => '';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final paper = Paper.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ColoredBox(
        color: paper.placeholderBox,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text('這裡的內容要更新 App 才能顯示',
              textScaler: TextScaler.noScaling, style: TextStyle(color: paper.hint, fontSize: 12)),
        ),
      ),
    );
  }
}

/// One image. When it's only in the cloud and can't be fetched now, a box of the same size says so;
/// it stays in the text (moving with it) and appears once online.
class _DiaryImage extends StatefulWidget {
  const _DiaryImage({required this.id, required this.resolve, this.onTap});

  final String id;
  final Future<File?> Function(String id) resolve;

  /// What a tap does instead of opening the image (or retrying) — a video's cover plays the video.
  /// The image is looked up again afterwards when it couldn't be shown before.
  final Future<void> Function()? onTap;

  @override
  State<_DiaryImage> createState() => _DiaryImageState();
}

class _DiaryImageState extends State<_DiaryImage> {
  late Future<File?> _file = widget.resolve(widget.id);

  /// Looks the file up again. (A block body: setState must not be handed the lookup's Future.)
  void _retry() {
    setState(() {
      _file = widget.resolve(widget.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final paper = Paper.of(context);
    final other = widget.onTap;
    // With a tap of its own (a video's cover), every state does that; a cover that couldn't be
    // shown is looked up again once the tap's screen is closed.
    final afterOther = other == null ? null : () => other().whenComplete(() => mounted ? _retry() : null);
    Widget box(String text, {VoidCallback? onTap}) => GestureDetector(
          onTap: afterOther ?? onTap,
          child: ColoredBox(
            color: paper.placeholderBox,
            child: Center(child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: paper.hint, fontSize: 12))),
          ),
        );
    return FutureBuilder<File?>(
      future: _file,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return box('圖片載入中…');
        }
        final file = snap.data;
        if (file == null) {
          return box(other == null ? '需要網路才能顯示\n（點一下重試）' : '需要網路才能顯示', onTap: _retry);
        }
        return GestureDetector(
          onTap: other ??
              () => Navigator.of(context).push(MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => _ImageViewer(file: file),
                  )),
          // The file found can go away while shown: the sync moves an uploaded image from the phone
          // to the cache. Tapping looks it up again (cache or cloud).
          child: Image.file(file,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => box(other == null ? '無法顯示這張圖片\n（點一下重試）' : '無法顯示這張圖片', onTap: _retry)),
        );
      },
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
