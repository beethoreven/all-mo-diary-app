import 'dart:convert';

/// One font from the published font list (backend apps/diary/fonts.py → daily check).
class FontInfo {
  const FontInfo({
    required this.id,
    required this.name,
    required this.sort,
    required this.disabled,
    required this.licensed,
    required this.downloadUrl,
    required this.downloadBytes,
    required this.downloadSha256,
    required this.fontBytes,
    required this.fontSha256,
  });

  final int id;

  /// The display name set in the admin console (spec §9: not the name inside the font file).
  final String name;
  final int sort;

  /// Disabled fonts stay in the list so diaries that use them still show the name, but can't be installed.
  final bool disabled;
  final bool licensed;
  final String downloadUrl;
  final int downloadBytes;
  final String downloadSha256;

  /// Size on the phone once installed (spec §9: shown next to each font).
  final int fontBytes;
  final String fontSha256;

  /// The family name used in diaries (Quill's font attribute) and with Flutter's FontLoader.
  String get family => 'amdfont$id';

  static FontInfo? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, Object?>();
    final id = m['id'], name = m['name'];
    if (id is! int || name is! String) return null;
    int i(String k) => m[k] is int ? m[k] as int : 0;
    String s(String k) => m[k] is String ? m[k] as String : '';
    return FontInfo(
      id: id,
      name: name,
      sort: i('sort'),
      disabled: m['disabled'] == true,
      licensed: m['licensed'] == true,
      downloadUrl: s('download_url'),
      downloadBytes: i('download_bytes'),
      downloadSha256: s('download_sha256'),
      fontBytes: i('font_bytes'),
      fontSha256: s('font_sha256'),
    );
  }
}

/// The font list this phone last received, and its version.
class FontCatalog {
  const FontCatalog(this.version, this.fonts);

  static const empty = FontCatalog(null, []);

  final String? version;

  /// Sorted by the admin's order.
  final List<FontInfo> fonts;

  FontInfo? byFamily(String family) {
    for (final f in fonts) {
      if (f.family == family) return f;
    }
    return null;
  }

  static FontCatalog decode(String? stored) {
    if (stored == null) return empty;
    try {
      final m = (jsonDecode(stored) as Map).cast<String, Object?>();
      final list = ((m['content'] as Map?)?['fonts'] as List?) ?? const [];
      final fonts = [for (final f in list) ?FontInfo.tryParse(f)]..sort((a, b) => a.sort.compareTo(b.sort));
      return FontCatalog(m['version'] as String?, fonts);
    } catch (_) {
      return empty;
    }
  }
}
