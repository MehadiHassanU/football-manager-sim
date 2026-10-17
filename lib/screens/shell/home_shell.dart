import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../ui/ui.dart';
import '../app_router.dart' show kTwoPaneBreakpoint;

/// Tab destinations in navigation order; system back returns to the previous.
const _tabOrder = ['/home', '/squad', '/match', '/settings'];

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.child});

  final Widget child;

  static const _destinations = [
    ('/home', Icons.home_outlined, Icons.home, 'Home'),
    ('/squad', Icons.groups_outlined, Icons.groups, 'Squad'),
    ('/match', Icons.sports_soccer_outlined, Icons.sports_soccer, 'Match'),
    ('/settings', Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  int _indexFor(String location) {
    final index = _destinations.indexWhere((d) => location.startsWith(d.$1));
    return index < 0 ? 0 : index;
  }

  /// Whether [location] is one of the four tab roots, as opposed to a
  /// drill-down such as `/league-table` or `/main-menu`.
  ///
  /// Tab roots own the back gesture (walk one tab back); drill-downs must be
  /// allowed to pop normally, otherwise back would do nothing at all on them.
  static bool _isTabRoot(String location) =>
      _destinations.any((d) => d.$1 == location) || location == '/main-menu';

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _indexFor(location);
    final wide = MediaQuery.sizeOf(context).width >= kTwoPaneBreakpoint;

    // Android back gesture: on a non-Home tab, navigate one tab back instead
    // of exiting the game; on Home the event is swallowed (standard game
    // behavior — exit via the system home gesture or recent apps). Drill-down
    // routes inside the shell pop normally so back always goes somewhere.
    return PopScope<Object?>(
      canPop: !_isTabRoot(location),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (index > 0) {
          context.go(_tabOrder[index - 1]);
        }
      },
      child: wide ? _buildWide(context, index) : _buildNarrow(context, index),
    );
  }

  Widget _buildWide(BuildContext context, int index) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (i) => context.go(_destinations[i].$1),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Icon(
                Icons.sports_soccer,
                color: AppTheme.pitchGreen,
                size: 32,
              ),
            ),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.$2),
                  selectedIcon: Icon(d.$3),
                  label: Text(d.$4),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildNarrow(BuildContext context, int index) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(_destinations[i].$1),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.$2),
              selectedIcon: Icon(d.$3),
              label: d.$4,
            ),
        ],
      ),
    );
  }
}
