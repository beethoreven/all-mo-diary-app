/// Limits and timings in one place; the reasons are in docs/SPEC_DRAFT.md.
library;

abstract final class Limits {
  /// Title: required, single line, at most 20 characters (an emoji counts as one) — spec §2.
  static const titleMaxChars = 20;

  /// User name shown as「名字的日記」: at most 8 characters — spec §1.1.
  static const userNameMaxChars = 8;

  /// Search text: 10 characters for now, to be tuned against the real layout width — spec §5.
  static const searchMaxChars = 10;

  /// Years the calendar, filter and date picker offer (same range as mama-fufood).
  static const yearMin = 2020;
  static const yearMax = 2080;
}

abstract final class Timing {
  /// Changing month needs a drag past half the width (distance only, not fling speed).
  static const monthSwipeFraction = 0.5;
  static const monthSlide = Duration(milliseconds: 220);

  /// While writing, an unsaved draft is written to the phone this often (spec §6, auto draft).
  static const draftSaveInterval = Duration(seconds: 3);
}

/// Editor formatting choices — spec §6.1.
abstract final class EditorSpec {
  /// Font sizes in points. Stored in the diary as the point number ("12").
  static const fontSizes = [8, 10, 12, 14, 16, 18, 20];
  static const defaultFontSize = 12;

  /// Points are drawn at 4/3 logical pixels each (the CSS pt→px ratio), so 12 pt reads like
  /// body text in other apps. Applied as a text scale around the body only; images aren't scaled.
  static const pointToPixel = 4 / 3;

  /// The built-in font. Not deletable (spec §9) and the fallback for anything missing.
  static const defaultFontFamily = 'NotoSansTC';
  static const defaultFontName = 'Noto Sans TC';
}
