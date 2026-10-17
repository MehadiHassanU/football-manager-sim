import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_config.dart';
import 'providers/settings_providers.dart';
import 'ui/theme/app_theme.dart';
import 'screens/app_router.dart';

class FootballManagerSimApp extends ConsumerWidget {
  const FootballManagerSimApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Follows the persisted Appearance setting. The light theme was already
    // built but unreachable while this was pinned to ThemeMode.dark.
    final themeMode = themeModeOf(ref.watch(themeModeProvider));
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: appRouter,
    );
  }
}
