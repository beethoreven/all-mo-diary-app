import 'package:flutter/foundation.dart';

/// Diagnostic log entry points. Call sites use the same API as mama-fufood's `core/log.dart`.
///
/// ★ For now this only prints in debug builds. The feedback feature (spec §10) replaces the body
///   with mama-fufood's file log (7 days, redaction of e-mail / tokens / names, attached to "遇到問題"
///   feedback); call sites stay as they are. Remove this note when that lands.
abstract final class AppLog {
  static void info(String event, [Map<String, Object?> data = const {}]) => _print('I', event, data);

  static void warn(String event, [Map<String, Object?> data = const {}]) => _print('W', event, data);

  static void error(String event, Object error, [StackTrace? stack]) =>
      _print('E', event, {'type': error.runtimeType.toString()});

  static void _print(String level, String event, Map<String, Object?> data) {
    if (kDebugMode) debugPrint('[$level] $event ${data.isEmpty ? '' : data}');
  }
}
