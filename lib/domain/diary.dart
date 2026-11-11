import 'dart:convert';

import '../core/time.dart';

/// A saved diary.
class Diary {
  const Diary({
    required this.id,
    required this.day,
    required this.title,
    required this.body,
    required this.bodyPlain,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final Day day;
  final String title;

  /// Quill Delta JSON (see [DiaryBody]).
  final String body;
  final String bodyPlain;
  final int createdAt;
  final int updatedAt;
}

/// What the editor hands to the store when saving.
class DiaryInput {
  const DiaryInput({this.id, required this.day, required this.title, required this.body});

  /// null for a new diary.
  final String? id;
  final Day day;
  final String title;

  /// Quill Delta JSON.
  final String body;
}

/// Working with the stored body (a Quill Delta: a JSON list of insert operations) without the editor.
abstract final class DiaryBody {
  /// The embed type of a diary image. Its data is JSON: {"id": "...", "w": 960, "h": 720}.
  static const imageType = 'diary_image';

  /// An empty body (Quill documents always end with a newline).
  static const empty = '[{"insert":"\\n"}]';

  static List<dynamic> _ops(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is List ? decoded : const [];
    } on FormatException {
      return const [];
    }
  }

  /// The text a person would read, for search: text inserts joined, images skipped, ends trimmed
  /// of the document's closing newline only.
  static String plainText(String body) {
    final buf = StringBuffer();
    for (final op in _ops(body)) {
      final insert = op is Map ? op['insert'] : null;
      if (insert is String) buf.write(insert);
    }
    final text = buf.toString();
    return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  }

  /// Image ids referenced by the body.
  static Set<String> imageIds(String body) {
    final ids = <String>{};
    for (final op in _ops(body)) {
      final insert = op is Map ? op['insert'] : null;
      if (insert is Map && insert[imageType] is String) {
        final ref = ImageRef.tryParse(insert[imageType] as String);
        if (ref != null) ids.add(ref.id);
      }
    }
    return ids;
  }

  /// Font families used in the body (Quill's font attribute), e.g. {'amdfont3'}.
  static Set<String> fontFamilies(String body) {
    final out = <String>{};
    for (final op in _ops(body)) {
      final attrs = op is Map ? op['attributes'] : null;
      if (attrs is Map && attrs['font'] is String) out.add(attrs['font'] as String);
    }
    return out;
  }

  /// Whether the body has anything in it (text other than whitespace, or an image).
  static bool hasContent(String body) => plainText(body).trim().isNotEmpty || imageIds(body).isNotEmpty;
}

/// An image embedded in a diary: the file id and its stored pixel size.
class ImageRef {
  const ImageRef(this.id, this.width, this.height);

  final String id;
  final int width;
  final int height;

  String encode() => jsonEncode({'id': id, 'w': width, 'h': height});

  static ImageRef? tryParse(String data) {
    try {
      final m = jsonDecode(data);
      if (m is Map && m['id'] is String && m['w'] is int && m['h'] is int) {
        return ImageRef(m['id'] as String, m['w'] as int, m['h'] as int);
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}
