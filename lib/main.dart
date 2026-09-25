import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/save_service.dart';
import 'core/utils/window_setup_stub.dart'
    if (dart.library.io) 'core/utils/window_setup_io.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SaveService().init();
  await configureDesktopWindow();

  runApp(const ProviderScope(child: FootballManagerSimApp()));
}
