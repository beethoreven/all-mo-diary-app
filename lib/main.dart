import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/database.dart';
import 'data/store.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The bundled font isn't a pub package, so its licence must be registered by hand
  // (SIL OFL 1.1 requires shipping the notice with the font).
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const ['Noto Sans TC'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  // Portrait only for now, as in mama-fufood.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final support = await getApplicationSupportDirectory();
  final store = Store(AppDb.open(), imagesDir: Directory(p.join(support.path, 'images')));
  // Remove images left behind by discarded writing (spec §6.2). Not awaited: start-up doesn't wait.
  unawaited(store.cleanupImages());
  // Restores the remembered account and pass from the database; never asks Google for a silent
  // sign-in (that fails on real phones and shows an account picker).
  final auth = createAuthService(store);
  await auth.init();
  runApp(ProviderScope(
    overrides: [storeProvider.overrideWithValue(store), authServiceProvider.overrideWithValue(auth)],
    child: const DiaryApp(),
  ));
}
