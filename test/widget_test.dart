import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:football_manager_sim/app.dart';

import 'helpers/test_hive.dart';

void main() {
  late Directory storageDir;

  setUpAll(() async {
    storageDir = await initTestHive('fms_widget_test');
  });

  tearDownAll(() async {
    await disposeTestHive(storageDir);
  });

  Future<void> bootApp(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: stubDatabaseOverrides(),
          child: const FootballManagerSimApp(),
        ),
      );

  Future<bool> waitForReady(WidgetTester tester) =>
      waitForReal(tester, () => find.text('Continue').evaluate().isNotEmpty);

  testWidgets('app boots on the startup screen', (tester) async {
    await bootApp(tester);
    await tester.pump();

    expect(find.text('Touchline Legend'), findsOneWidget);
    expect(find.text('Your Tactics. Your Club. Your Legacy.'), findsOneWidget);

    // Drain the bootstrap before the test ends: Hive caches an in-flight
    // `openBox` future per box name, and its continuation belongs to this
    // test's fake-async zone. Abandoning it would wedge every later test.
    expect(await waitForReady(tester), isTrue);
  });

  testWidgets('startup finishes its work and unlocks Continue', (tester) async {
    await bootApp(tester);
    expect(
      await waitForReady(tester),
      isTrue,
      reason: 'startup never reached the ready state',
    );

    // Bootstrap is async (Hive settings read + career restore), so the button
    // swaps from "Skip" to "Continue" only once both have resolved.
    expect(find.text('Skip'), findsNothing);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('Continue navigates to the main menu when there is no save',
      (tester) async {
    await bootApp(tester);
    expect(await waitForReady(tester), isTrue);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('New Career'), findsOneWidget);
    // No save exists in this temp Hive directory, so Continue Career must not
    // be offered.
    expect(find.text('Continue Career'), findsNothing);
  });
}
