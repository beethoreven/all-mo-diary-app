import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/store.dart';
import '../domain/diary.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/daily_check.dart';
import '../services/diagnostics.dart';
import '../services/drive_store.dart';
import '../services/export_service.dart';
import '../services/feedback_service.dart';
import '../services/font_manager.dart';
import '../services/image_service.dart';
import '../services/sync_engine.dart';
import '../services/video_service.dart';

/// Replaced in main() with the real store; tests pass one on an in-memory database.
final storeProvider = Provider<Store>((ref) => throw UnimplementedError('storeProvider must be overridden in main'));

final imageServiceProvider = Provider<ImageService>((ref) => ImageService(ref.watch(storeProvider)));

final videoServiceProvider = Provider<VideoService>((ref) => VideoService(ref.watch(storeProvider)));

/// Replaced in main() with the initialized service (its sign-in is restored from storage there).
final authServiceProvider =
    Provider<AuthService>((ref) => throw UnimplementedError('authServiceProvider must be overridden in main'));

/// The signed-in account, rebuilt whenever the sign-in changes.
final authUserProvider = Provider<SignedInUser?>((ref) {
  final auth = ref.watch(authServiceProvider);
  void listener() => ref.invalidateSelf();
  auth.addListener(listener);
  ref.onDispose(() => auth.removeListener(listener));
  return auth.user;
});

/// The sign-in state (signed out / signed in / pass expired), rebuilt with it.
final authStateProvider = Provider<AuthState>((ref) {
  ref.watch(authUserProvider);
  final auth = ref.watch(authServiceProvider);
  void listener() => ref.invalidateSelf();
  auth.addListener(listener);
  ref.onDispose(() => auth.removeListener(listener));
  return auth.state;
});

/// Install id and unexpected-exit detection; created and initialized in main().
final diagnosticsProvider =
    Provider<Diagnostics>((ref) => throw UnimplementedError('diagnosticsProvider must be overridden in main'));

/// Downloaded fonts (files/fonts/); replaced in main() with the real folder.
final fontManagerProvider = Provider<FontManager>((ref) => FontManager(Directory('${Directory.systemTemp.path}/amd_fonts')));

/// The app's version (x.y.z) and build number, read once at start-up in main().
final appVersionProvider = Provider<String>((ref) => '0.0.0');
final buildNumberProvider = Provider<String>((ref) => '0');

final feedbackServiceProvider = Provider<FeedbackService>((ref) => FeedbackService(
      store: ref.watch(storeProvider),
      api: ref.watch(apiClientProvider),
      auth: ref.watch(authServiceProvider),
      diagnostics: ref.watch(diagnosticsProvider),
      appVersion: () => ref.read(appVersionProvider),
      buildNumber: () => ref.read(buildNumberProvider),
      fonts: () => ref.read(dailyCheckProvider).fontCatalog(),
    ));

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient()..auth = ref.watch(authServiceProvider));

final dailyCheckProvider = Provider<DailyCheckService>((ref) => DailyCheckService(
      store: ref.watch(storeProvider),
      auth: ref.watch(authServiceProvider),
      api: ref.watch(apiClientProvider),
      appVersion: () => ref.read(appVersionProvider),
    ));

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final auth = ref.watch(authServiceProvider);
  final engine = SyncEngine(
    store: ref.watch(storeProvider),
    auth: auth,
    cloud: ({required interactive}) => GoogleDriveStore(auth, interactive: interactive),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

final exportServiceProvider = Provider<ExportService>((ref) {
  final auth = ref.watch(authServiceProvider);
  return ExportService(
    store: ref.watch(storeProvider),
    sync: ref.watch(syncEngineProvider),
    appVersion: () => ref.read(appVersionProvider),
    cloud: ({required interactive}) => GoogleDriveStore(auth, interactive: interactive),
  );
});

/// Rebuilds when the sync state changes (running / ok / error).
final syncStateProvider = Provider<SyncState>((ref) {
  final engine = ref.watch(syncEngineProvider);
  void listener() => ref.invalidateSelf();
  engine.addListener(listener);
  ref.onDispose(() => engine.removeListener(listener));
  return engine.state;
});

/// Keeps the sign-in in Store's settings table (files/db/, so Android auto-backup includes it).
class StoreAuthStorage implements AuthStorage {
  const StoreAuthStorage(this.store);

  final Store store;

  @override
  Future<String?> read(String key) => store.getSetting(key);

  @override
  Future<void> write(String key, String? value) => store.setSetting(key, value);
}

/// Wires the auth service to the backend exchange (none when the backend address isn't set).
AuthService createAuthService(Store store, {ApiClient? api}) {
  final client = api ?? ApiClient();
  return AuthService(StoreAuthStorage(store))..exchange = client.configured ? client.createSession : null;
}

class AppSettings {
  const AppSettings(this.raw);

  final Map<String, String> raw;

  String? get userName {
    final v = raw[Keys.userName]?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  /// Week starts on Monday unless set to Sunday.
  bool get weekStartsMonday => raw[Keys.weekStart] != 'sunday';

  /// Follows the system unless the user picked one.
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
