import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'startup/startup_screen.dart';
import 'main_menu/main_menu_screen.dart';
import 'new_career/new_career_screen.dart';
import 'shell/home_shell.dart';
import 'career/career_dashboard_screen.dart';
import 'match/match_screen.dart';
import 'team_management/team_management_screen.dart';
import 'settings/settings_screen.dart';
import 'transfer_market/transfer_market_screen.dart';
import 'league_table/league_table_screen.dart';
import 'privacy/privacy_policy_screen.dart';

/// Root navigator key shared by the router.
final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

/// Narrow-phone breakpoint for adaptive two-pane layouts.
const double kTwoPaneBreakpoint = 600;

/// App router.
///
/// The `/home`, `/squad`, `/match` and `/settings` routes render inside a
/// [ShellRoute] that provides the bottom navigation bar (phone) or side rail
/// (wide layout).
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
      path: '/new-career',
      builder: (context, state) => const NewCareerScreen(),
    ),
    ShellRoute(
      builder: (context, state, child) => HomeShell(child: child),
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => const CareerDashboardScreen(),
        ),
        GoRoute(
          path: '/squad',
          builder: (context, state) => const TeamManagementScreen(),
        ),
        GoRoute(
          path: '/match',
          builder: (context, state) => const MatchScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/transfers',
      builder: (context, state) => const TransferMarketScreen(),
    ),
    GoRoute(
      path: '/league-table',
      builder: (context, state) => const LeagueTableScreen(),
    ),
    GoRoute(
      path: '/privacy',
      builder: (context, state) => const PrivacyPolicyScreen(),
    ),
  ],
  errorBuilder: (context, state) =>
      _NotFoundScreen(error: state.error?.toString() ?? 'Unknown route'),
);

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not Found')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Screen not found'),
            const SizedBox(height: 8),
            Text(error, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/main-menu'),
              child: const Text('Main Menu'),
            ),
          ],
        ),
      ),
    );
  }
}
