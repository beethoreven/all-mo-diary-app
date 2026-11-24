import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/log.dart';
import '../domain/font_catalog.dart';

/// 開放原始碼授權 entries for the downloadable fonts: one per font that has a source and licence
/// statement, listed under the font's name.
///
/// The licence page asks for its entries each time it opens, so these follow the font list the phone
/// has at that moment: a font added in the admin console is credited without a new app version.
Stream<LicenseEntry> fontLicenses(Future<FontCatalog> Function() catalog) async* {
  final FontCatalog list;
  try {
    list = await catalog();
  } catch (e, stack) {
    // A source of entries that fails makes the licence page show that error in place of every
    // licence. The packages' and the bundled font's licences must stay readable when the font list
    // can't be read, so this one ends without entries instead.
    AppLog.error('fonts.licences_failed', e, stack);
    return;
  }
  for (final font in list.fonts) {
    if (font.attribution.isNotEmpty) yield FontLicenseEntry(font.name, font.attribution);
  }
}

/// A font's statement as written: each line is a paragraph of its own. (Flutter's
/// LicenseEntryWithLineBreaks joins the lines of a paragraph and reads indentation as layout.)
class FontLicenseEntry extends LicenseEntry {
  const FontLicenseEntry(this.fontName, this.statement);

  final String fontName;
  final String statement;

  @override
  Iterable<String> get packages => [fontName];

  @override
  Iterable<LicenseParagraph> get paragraphs => [
        for (final line in const LineSplitter().convert(statement))
          if (line.trim().isNotEmpty) LicenseParagraph(line.trim(), 0),
      ];
}
