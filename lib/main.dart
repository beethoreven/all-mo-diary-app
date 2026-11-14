import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/log.dart';
import 'data/database.dart';
import 'data/store.dart';
import 'services/diagnostics.dart';
import 'services/font_manager.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Crashes go to the on-phone diagnostic log; native ones are caught by AllMoDiaryApp.kt.
  FlutterError.onError = (details) {
    AppLog.error('flutter.error', details.exception, details.stack);
    if (kDebugMode) FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.error('dart.uncaught', error, stack);
    return true;
  };
  // The bundled font isn't a pub package, so its licence must be registered by hand
  // (SIL OFL 1.1 requires shipping the notice with the font).
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const ['Noto Sans TC'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  // Portrait only for now.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final support = await getApplicationSupportDirectory();
  final cache = await getApplicationCacheDirectory();
  final store = Store(AppDb.open(),
      imagesDir: Directory(p.join(support.path, 'images')),
      videosDir: Directory(p.join(support.path, 'videos')),
      cacheDir: Directory(p.join(cache.path, 'images')),
      videoCacheDir: Directory(p.join(cache.path, 'videos')));
  final diagnostics = Diagnostics(store);
  await diagnostics.init();
  final package = await PackageInfo.fromPlatform();
  final version = package.version;
  AppLog.info('app.start', {'version': version});
  // Remove images and videos left behind by discarded writing. Not awaited: start-up doesn't wait.
  unawaited(store.cleanupMedia());
  final fonts = FontManager(Directory(p.join(support.path, 'fonts')));
  unawaited(fonts.cleanupPartials());
  // Restores the remembered account and pass from the database; never asks Google for a silent
  // sign-in (that fails on real phones and shows an account picker).
  final auth = createAuthService(store);
  await auth.init();
  runApp(ProviderScope(
    overrides: [
      storeProvider.overrideWithValue(store),
      authServiceProvider.overrideWithValue(auth),
      appVersionProvider.overrideWithValue(version),
      buildNumberProvider.overrideWithValue(package.buildNumber),
      diagnosticsProvider.overrideWithValue(diagnostics),
      fontManagerProvider.overrideWithValue(fonts),
    ],
    child: const AllMoDiaryApp(),
  ));
}
