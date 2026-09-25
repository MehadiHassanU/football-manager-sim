import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/startup/startup_screen.dart';
import 'screens/main_menu/main_menu_screen.dart';
import 'screens/career/career_dashboard_screen.dart';
import 'screens/match/match_screen.dart';
import 'screens/team_management/team_management_screen.dart';
import 'screens/settings/settings_screen.dart';

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: navKey,
  initialLocation: '/startup',
  routes: [
    GoRoute(
      path: '/startup',
      builder: (context, state) => const StartupScreen(),
    ),
    GoRoute(
      path: '/main-menu',
      builder: (context, state) => const MainMenuScreen(),
    ),
    GoRoute(
      path: '/career',
      builder: (context, state) => const CareerDashboardScreen(),
    ),
    GoRoute(
      path: '/match',
      builder: (context, state) => const MatchScreen(),
    ),
    GoRoute(
      path: '/team-management',
      builder: (context, state) => const TeamManagementScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);

class FootballManagerSimApp extends ConsumerWidget {
  const FootballManagerSimApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Football Manager Sim',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1A56DB),
        useMaterial3: true,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F1923),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      routerConfig: appRouter,
    );
  }
}
