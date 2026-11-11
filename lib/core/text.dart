import 'package:characters/characters.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
final _uuid4 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

/// A new random id (UUID v4, lower case).
String newId() => _uuid.v4().toLowerCase();

bool isUuid4(String text) => _uuid4.hasMatch(text);

/// Text rules shared by the title, user name and search inputs.
abstract final class TextRules {
  /// Characters the way a person counts them: an emoji (even a combined one) is one.
  static int length(String text) => text.characters.length;

  /// Line breaks and other invisible control characters (only these are blocked).
  static final _control = RegExp(r'[\u0000-\u001F\u007F-\u009F\u2028\u2029]');

  /// Typing or pasting a blocked character simply doesn't insert it.
  static final TextInputFormatter blockControl = FilteringTextInputFormatter.deny(_control);

  /// Trims the ends; keeps spaces in the middle exactly ("An Apple" ≠ "AnApple").
  static String clean(String text) => text.replaceAll(_control, '').trim();
}
