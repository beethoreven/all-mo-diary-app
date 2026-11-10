import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/store.dart';
import '../domain/diary.dart';
import '../services/image_service.dart';

/// Replaced in main() with the real store; tests pass one on an in-memory database.
final storeProvider = Provider<Store>((ref) => throw UnimplementedError('storeProvider must be overridden in main'));

final imageServiceProvider = Provider<ImageService>((ref) => ImageService(ref.watch(storeProvider)));

class AppSettings {
  const AppSettings(this.raw);

  final Map<String, String> raw;

  String? get userName {
    final v = raw[Keys.userName]?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  /// Week starts on Monday unless set to Sunday (as in mama-fufood).
  bool get weekStartsMonday => raw[Keys.weekStart] != 'sunday';

  /// Follows the system unless the user picked one (spec §8).
  ThemeMode get themeMode => switch (raw[Keys.theme]) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  String get themeCode => raw[Keys.theme] ?? 'system';
}

final settingsProvider =
    StreamProvider<AppSettings>((ref) => ref.watch(storeProvider).watchSettings().map(AppSettings.new));

AppSettings settingsOf(WidgetRef ref) => ref.watch(settingsProvider).value ?? const AppSettings({});

final monthDiariesProvider = StreamProvider.family<List<Diary>, (int, int)>(
    (ref, key) => ref.watch(storeProvider).watchMonth(key.$1, key.$2));

final prefixDiariesProvider =
    StreamProvider.family<List<Diary>, String>((ref, prefix) => ref.watch(storeProvider).watchPrefix(prefix));

final allDiariesProvider = StreamProvider<List<Diary>>((ref) => ref.watch(storeProvider).watchAll());
