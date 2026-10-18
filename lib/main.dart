import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/save_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode) {
    // The match, save and startup layers log through debugPrint; a shipped
    // build has no console to read, so silence the channel entirely.
    debugPrint = (String? message, {int? wrapWidth}) {};
  }
  await SaveService().init();

  runApp(const ProviderScope(child: FootballManagerSimApp()));
}
