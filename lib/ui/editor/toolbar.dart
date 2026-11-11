import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../core/constants.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// A colour choice. [hex] null means "no attribute" (the default: no background / black text).
class Swatch {
  const Swatch(this.name, this.hex, this.color);

  final String name;
  final String? hex;
  final Color? color;
}

/// Spec §6.1.
abstract final class Swatches {
  static const background = [
    Swatch('淡紅', '#FFD6D6', Color(0xFFFFD6D6)),
    Swatch('淡黃', '#FFF3B0', Color(0xFFFFF3B0)),
    Swatch('粉藍', '#CDE7FF', Color(0xFFCDE7FF)),
    Swatch('粉綠', '#D4F5D4', Color(0xFFD4F5D4)),
    Swatch('灰色', '#D9D9D9', Color(0xFFD9D9D9)),
    Swatch('黑色', '#000000', Color(0xFF000000)),
    Swatch('無色', null, null),
  ];

  static const text = [
    Swatch('深紅', '#B00020', Color(0xFFB00020)),
    Swatch('亮黃', '#FFD600', Color(0xFFFFD600)),
    Swatch('深藍', '#0D3B8C', Color(0xFF0D3B8C)),
    Swatch('深綠', '#1B5E20', Color(0xFF1B5E20)),
    Swatch('白色', '#FFFFFF', Color(0xFFFFFFFF)),
    Swatch('黑色', '#000000', Color(0xFF000000)),
  ];
}

/// The editor toolbar (spec §6.1): one row that scrolls sideways, icons only; long-press shows
/// what a button does. With text selected a change applies to the selection; otherwise it
/// applies to what is typed next at the cursor (Quill's toggled style does exactly that).
class DiaryToolbar extends StatelessWidget {
  const DiaryToolbar(
      {super.key, required this.controller, required this.onAddImage, required this.fonts, required this.onFontPicked});

  final QuillController controller;
  final VoidCallback onAddImage;

  /// The font menu (spec §9): the built-in font first, then installed fonts, as (family, name).
  final List<(String, String)> fonts;

  /// Called after a font is applied (null = the default), to check which characters it lacks.
  final Future<void> Function(String? family) onFontPicked;

  /// Inline formats the 「預設」 button clears.
  static const List<Attribute<dynamic>> _clearable = [
    Attribute.bold,
    Attribute.italic,
    Attribute.underline,
    Attribute.strikeThrough,
    SizeAttribute(null),
    FontAttribute(null),
    BackgroundAttribute(null),
    ColorAttribute(null),
  ];

  void _toggle(Attribute on) {
    final active = controller.getSelectionStyle().attributes.containsKey(on.key);
    controller.formatSelection(active ? Attribute.clone(on, null) : on);
  }

  void _resetFormats() {
    for (final a in _clearable) {
      controller.formatSelection(Attribute.clone(a, null));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.border))),
      height: 52,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final style = controller.getSelectionStyle().attributes;
          bool on(Attribute a) => style.containsKey(a.key);
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: [
              _ToolButton(icon: Icons.undo_rounded, label: '復原', onTap: controller.hasUndo ? controller.undo : null),
              _ToolButton(icon: Icons.redo_rounded, label: '取消復原', onTap: controller.hasRedo ? controller.redo : null),
              _divider(c),
              _ToolButton(
                icon: Icons.format_size_rounded,
                label: '字體大小',
                active: style.containsKey(Attribute.size.key),
                onTap: () => _pickSize(context, style[Attribute.size.key]?.value),
              ),
              _ToolButton(
                icon: Icons.font_download_outlined,
                label: '字體',
                active: style.containsKey(Attribute.font.key),
                onTap: () => _pickFont(context, style[Attribute.font.key]?.value as String?),
              ),
              _ToolButton(
                  icon: Icons.format_bold_rounded, label: '粗體', active: on(Attribute.bold), onTap: () => _toggle(Attribute.bold)),
              _ToolButton(
                  icon: Icons.format_italic_rounded,
                  label: '斜體',
                  active: on(Attribute.italic),
                  onTap: () => _toggle(Attribute.italic)),
              _ToolButton(
                  icon: Icons.format_underlined_rounded,
                  label: '底線',
                  active: on(Attribute.underline),
                  onTap: () => _toggle(Attribute.underline)),
              _ToolButton(
                  icon: Icons.strikethrough_s_rounded,
                  label: '刪除線',
                  active: on(Attribute.strikeThrough),
                  onTap: () => _toggle(Attribute.strikeThrough)),
              _ToolButton(
                icon: Icons.format_color_fill_rounded,
                label: '底色',
                active: style.containsKey(Attribute.background.key),
                onTap: () => _pickColor(context, '底色', Swatches.background, style[Attribute.background.key]?.value as String?,
                    (hex) => controller.formatSelection(BackgroundAttribute(hex))),
              ),
              _ToolButton(
                icon: Icons.format_color_text_rounded,
                label: '字的顏色',
                active: style.containsKey(Attribute.color.key),
                onTap: () => _pickTextColor(context, style[Attribute.color.key]?.value as String?),
              ),
              _divider(c),
              _ToolButton(icon: Icons.image_outlined, label: '加上圖片', onTap: onAddImage),
              _ToolButton(icon: Icons.format_clear_rounded, label: '預設', onTap: _resetFormats),
            ],
          );
        },
      ),
    );
  }

  Widget _divider(AppColors c) =>
      Center(child: Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 4), color: c.border));

  Future<void> _pickSize(BuildContext context, Object? current) async {
    final now = int.tryParse('${current ?? ''}') ?? EditorSpec.defaultFontSize;
    final pt = await showChoices<int>(context,
        title: '字體大小', items: EditorSpec.fontSizes, selected: now, label: (v) => '$v pt');
    if (pt == null) return;
    controller.formatSelection(SizeAttribute(pt == EditorSpec.defaultFontSize ? null : '$pt'));
  }

  Future<void> _pickFont(BuildContext context, String? current) async {
    final family = await showChoices<String>(context,
        title: '字體',
        items: [for (final f in fonts) f.$1],
        selected: current ?? EditorSpec.defaultFontFamily,
        label: (f) => fonts.firstWhere((x) => x.$1 == f, orElse: () => (f, '已移除的字體')).$2);
    if (family == null) return;
    final value = family == EditorSpec.defaultFontFamily ? null : family;
    // Load the font before applying it, so the text never flashes in a font that isn't there yet.
    await onFontPicked(value);
    controller.formatSelection(FontAttribute(value));
  }

  /// Text colour. No attribute means "the paper's default" (black on light paper, white on dark), so a
  /// diary stays readable in both themes. Picking the swatch that equals this theme's default
  /// therefore removes the attribute instead of fixing the colour.
  Future<void> _pickTextColor(BuildContext context, String? current) {
    final defaultHex = _hex(Paper.of(context).text);
    return _pickColor(context, '字的顏色', Swatches.text, current ?? defaultHex,
        (hex) => controller.formatSelection(ColorAttribute(hex?.toUpperCase() == defaultHex ? null : hex)));
  }

  static String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Future<void> _pickColor(BuildContext context, String title, List<Swatch> swatches, String? current,
      void Function(String? hex) apply) async {
    final picked = await showDialog<Swatch>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final s in swatches) _SwatchButton(swatch: s, selected: s.hex?.toUpperCase() == current?.toUpperCase()),
          ]),
        ],
      ),
    );
    if (picked != null) apply(picked.hex);
  }
}

class _SwatchButton extends StatelessWidget {
  const _SwatchButton({required this.swatch, required this.selected});

  final Swatch swatch;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: swatch.name,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.pop(context, swatch),
        child: SizedBox(
          width: 56,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: swatch.color ?? Paper.of(context).color,
                shape: BoxShape.circle,
                border: Border.all(color: selected ? c.accent : c.border, width: selected ? 3 : 1),
              ),
              child: swatch.color == null ? Icon(Icons.block_rounded, color: c.muted, size: 20) : null,
            ),
            const SizedBox(height: 4),
            Text(swatch.name, style: Theme.of(context).textTheme.labelSmall!.copyWith(color: c.text)),
          ]),
        ),
      ),
    );
  }
}

/// A toolbar icon. No text on it; a long press shows what it does (spec §6.1).
class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      toggled: active,
      excludeSemantics: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        onLongPress: () => toast(context, label, duration: const Duration(milliseconds: 1500)),
        child: Container(
          // Touch target at least 48 dp tall.
          width: 46,
          height: 48,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: active ? BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(10)) : null,
          child: Icon(icon, color: onTap == null ? c.muted.withValues(alpha: 0.4) : (active ? c.accent : c.text)),
        ),
      ),
    );
  }
}
