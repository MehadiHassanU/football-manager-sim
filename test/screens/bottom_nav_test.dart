import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:football_manager_sim/screens/shell/home_shell.dart';

/// The shell without the rest of the app: a real router (the shell reads
/// [GoRouterState]) but plain text bodies, so the test only exercises the
/// navigation chrome.
GoRouter _router({String initialLocation = '/home'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, __) => const Text('home body'),
          ),
          GoRoute(
            path: '/squad',
            builder: (_, __) => const Text('squad body'),
          ),
          GoRoute(
            path: '/transfers',
            builder: (_, __) => const Text('transfers body'),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const Text('settings body'),
          ),
          GoRoute(
            path: '/match',
            builder: (_, __) => const Text('match body'),
          ),
        ],
      ),
    ],
  );
}

void main() {
  testWidgets('the bottom bar sells transfers instead of a second Match entry',
      (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Squad'), findsOneWidget);
    expect(find.text('Transfers'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Match'), findsNothing,
        reason: 'the match is started from Home, so the tab is free');

    await tester.tap(find.text('Transfers'));
    await tester.pumpAndSettle();
    expect(find.text('transfers body'), findsOneWidget);
  });

  testWidgets('the match route still works as a drill-down', (tester) async {
    final router = _router(initialLocation: '/match');
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('match body'), findsOneWidget);
    expect(find.text('Match'), findsNothing);
  });
}
