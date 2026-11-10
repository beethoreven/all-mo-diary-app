import 'package:flutter/material.dart';

/// Colours. Structure follows mama-fufood's theme; the accent is goose yellow (鵝黃) instead of
/// its blue. Yellow is too light to be text on a light background, so the light theme splits it:
/// [accentFill] (yellow) behind dark [onAccent] text, and a deeper [accent] for text and icons.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.text,
    required this.text2,
    required this.muted,
    required this.accent,
    required this.accentFill,
    required this.onAccent,
    required this.accentSoft,
    required this.todayBg,
    required this.todayText,
    required this.diaryDot,
    required this.danger,
  });

  final Color bg, surface, surface2, border, text, text2, muted;
  final Color accent, accentFill, onAccent, accentSoft, todayBg, todayText, diaryDot, danger;

  static const light = AppColors(
    bg: Color(0xFFFBF8F1),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF5EFDF),
    border: Color(0xFFE6DCC4),
    text: Color(0xFF2B2620),
    text2: Color(0xFF5C5345),
    muted: Color(0xFF6B6253),
    accent: Color(0xFF8A6500),
    accentFill: Color(0xFFF6D365),
    onAccent: Color(0xFF332800),
    accentSoft: Color(0xFFFCEFC4),
    todayBg: Color(0xFFF6D365),
    todayText: Color(0xFF332800),
    diaryDot: Color(0xFF2F6FDB),
    danger: Color(0xFFBC4339),
  );

  static const dark = AppColors(
    bg: Color(0xFF17150F),
    surface: Color(0xFF201D16),
    surface2: Color(0xFF2B271D),
    border: Color(0xFF3B3527),
    text: Color(0xFFF1ECE0),
    text2: Color(0xFFC4BBA8),
    muted: Color(0xFF9D9481),
    accent: Color(0xFFF6D365),
    accentFill: Color(0xFFF6D365),
    onAccent: Color(0xFF2E2400),
    accentSoft: Color(0xFF3D3420),
    todayBg: Color(0xFFF6D365),
    todayText: Color(0xFF2E2400),
    diaryDot: Color(0xFF7FB0FF),
    danger: Color(0xFFF59A92),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) => t < 0.5 ? this : (other as AppColors? ?? this);
}

/// The diary "paper" (spec §6): off-white with black text in the light theme, dark grey with white
/// text in the dark theme. The default text colour is no colour attribute at all, so the same diary
/// reads correctly in either theme; picking the swatch that equals the default removes the attribute.
@immutable
class Paper {
  const Paper._(this.color, this.text, this.hint, this.placeholderBox);

  final Color color;

  /// Default text colour (equals the 黑色 swatch in light, the 白色 swatch in dark).
  final Color text;
  final Color hint;

  /// Behind a picture that can't be shown.
  final Color placeholderBox;

  static const light = Paper._(Color(0xFFFAF6EC), Color(0xFF000000), Color(0xFF8C8577), Color(0x14000000));
  static const dark = Paper._(Color(0xFF2B2B2B), Color(0xFFFFFFFF), Color(0xFF9A9A9A), Color(0x1FFFFFFF));

  static Paper of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

/// Noto Sans TC is a variable font: set both fontWeight and the wght axis.
TextStyle weight(TextStyle style, int w) =>
    style.copyWith(fontWeight: FontWeight.values[(w ~/ 100) - 1], fontVariations: [FontVariation('wght', w.toDouble())]);

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accentFill,
    onPrimary: c.onAccent,
    secondary: c.accent,
    onSecondary: c.onAccent,
    error: c.danger,
    onError: brightness == Brightness.dark ? const Color(0xFF3A0A06) : Colors.white,
    surface: c.surface,
    onSurface: c.text,
    surfaceContainerHighest: c.surface2,
    outline: c.border,
    primaryContainer: c.accentSoft,
    onPrimaryContainer: c.text,
  );
  const family = 'NotoSansTC';
  TextStyle s(double size, int w, Color color) => weight(TextStyle(fontFamily: family, fontSize: size, color: color), w);
  final text = TextTheme(
    titleLarge: s(17, 500, c.text),
    titleMedium: s(16, 500, c.text),
    titleSmall: s(14, 500, c.text),
    bodyLarge: s(15, 400, c.text),
    bodyMedium: s(14, 400, c.text),
    bodySmall: s(12, 400, c.text2),
    labelLarge: s(14, 500, c.text),
    labelMedium: s(13, 400, c.text),
    labelSmall: s(11, 400, c.muted),
  );
  const stadium = StadiumBorder();
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    fontFamily: family,
    textTheme: text,
    extensions: [c],
    dividerColor: c.border,
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: s(16, 500, c.text),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: s(16, 500, c.text),
      contentTextStyle: s(14, 400, c.text),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accentFill,
        foregroundColor: c.onAccent,
        minimumSize: const Size(64, 48),
        shape: stadium,
        textStyle: s(14, 500, c.onAccent),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        minimumSize: const Size(64, 48),
        side: BorderSide(color: c.border),
        shape: stadium,
        textStyle: s(14, 500, c.text),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
          foregroundColor: c.accent, minimumSize: const Size(48, 48), shape: stadium, textStyle: s(14, 500, c.accent)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.accent, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: s(14, 400, c.muted),
      labelStyle: s(14, 400, c.text2),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor:
            WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? c.accentSoft : c.surface2),
        foregroundColor: WidgetStateProperty.all(c.text),
        side: WidgetStateProperty.resolveWith((st) => BorderSide(
            color: st.contains(WidgetState.selected) ? c.accent : c.border,
            width: st.contains(WidgetState.selected) ? 1.5 : 1)),
        minimumSize: WidgetStateProperty.all(const Size(48, 44)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.surface2,
      contentTextStyle: s(14, 400, c.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: ListTileThemeData(iconColor: c.text2, textColor: c.text, minVerticalPadding: 12),
  );
}
