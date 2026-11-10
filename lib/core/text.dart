import 'package:characters/characters.dart';
import 'package:flutter/services.dart';

/// Text rules shared by the title, user name and search inputs.
abstract final class TextRules {
  /// Characters the way a person counts them: an emoji (even a combined one) is one.
  static int length(String text) => text.characters.length;

  /// Line breaks and other invisible control characters (spec §5: only these are blocked).
  static final _control = RegExp(r'[\u0000-\u001F\u007F-\u009F  ]');

  /// Typing or pasting a blocked character simply doesn't insert it.
  static final TextInputFormatter blockControl = FilteringTextInputFormatter.deny(_control);

  /// Trims the ends; keeps spaces in the middle exactly (spec §5: "An Apple" ≠ "AnApple").
  static String clean(String text) => text.replaceAll(_control, '').trim();
}
