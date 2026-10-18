import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';
import 'package:football_manager_sim/screens/team_management/team_management_screen.dart';
import 'package:football_manager_sim/ui/ui.dart';

import '../helpers/test_hive.dart';

/// Manual XI selection: tapping a slot opens the picker, the pick is stored
/// in the session, and the auto-pick controls hand the slots back.
void main() {
  late Directory storageDir;

  setUpAll(() async {
    storageDir = await initTestHive('fms_xi_picker');
  });

  tearDownAll(() async {
    await disposeTestHive(storageDir);
  });

  CareerSession bootSession(PlayerDatabase db) => CareerSession(
        manager: Manager(name: 'Boss', age: 40, nationality: 'Spain'),
        team: db.teams.first,
        season: SeasonState(leagueId: db.teams.first.leagueId),
      );

  /// The live session: the widget re-emits a shallow copy on every change, so
  /// the original instance held by the test can lag behind field writes.
  CareerSession current(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(TeamManagementScreen)),
        listen: false,
      ).read(careerSessionProvider)!;

  Future<void> pumpScreen(
    WidgetTester tester,
    PlayerDatabase db,
    CareerSession session,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerDatabaseProvider.overrideWith((ref) async => db),
          careerSessionProvider.overrideWith((ref) => session),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const TeamManagementScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Tactics'));
    await tester.pumpAndSettle();
  }

  testWidgets('a tapped slot stores the manager\'s pick', (tester) async {
    final db = stubPlayerDatabase(random: Random(6));
    final session = bootSession(db);
    await pumpScreen(tester, db, session);

    expect(find.textContaining('Picked by your assistant'), findsOneWidget);
    expect(find.text('Auto-pick'), findsNothing,
        reason: 'nothing to reset while the assistant picks everything');

    // The first centre-back slot of 4-4-2; Home 3 (a left-back) can fill it.
    await tester.tap(find.byKey(const ValueKey('pitch-slot-2')));
    await tester.pumpAndSettle();
    expect(find.text('Pick CB'), findsOneWidget);
    expect(find.text('FITS THE SLOT'), findsOneWidget);

    await tester.tap(find.text('Home 3'));
    await tester.pumpAndSettle();

    expect(find.text('Pick CB'), findsNothing, reason: 'the sheet closes');
    expect(current(tester).startXI, [0, 0, 1003],
        reason: 'the pick is stored for slot 2, and only slot 2');
    expect(find.textContaining('Manual XI'), findsOneWidget,
        reason: 'the header must say who picked the XI');

    await tester.tap(find.text('Auto-pick'));
    await tester.pumpAndSettle();
    expect(current(tester).startXI, isEmpty);
    expect(find.textContaining('Picked by your assistant'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the assistant option clears one slot again', (tester) async {
    final db = stubPlayerDatabase(random: Random(6));
    final session = bootSession(db);
    await pumpScreen(tester, db, session);

    await tester.tap(find.byKey(const ValueKey('pitch-slot-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home 3'));
    await tester.pumpAndSettle();
    expect(current(tester).startXI, [0, 0, 1003]);

    await tester.tap(find.byKey(const ValueKey('pitch-slot-2')));
    await tester.pumpAndSettle();
    expect(find.text('Let the assistant pick'), findsOneWidget);
    await tester.tap(find.text('Let the assistant pick'));
    await tester.pumpAndSettle();

    expect(current(tester).startXI, isEmpty,
        reason: 'clearing the only pick leaves an all-automatic XI');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the goal slot only offers keepers', (tester) async {
    final db = stubPlayerDatabase(random: Random(6));
    final session = bootSession(db);
    await pumpScreen(tester, db, session);

    await tester.tap(find.byKey(const ValueKey('pitch-slot-0')));
    await tester.pumpAndSettle();

    expect(find.text('Pick GK'), findsOneWidget);
    expect(find.text('Home 0'), findsOneWidget, reason: 'the only keeper');
    expect(find.text('Home 3'), findsNothing,
        reason: 'an out-fielder cannot be picked in goal');
    expect(find.text('OUT OF POSITION'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the squad list marks the starting XI', (tester) async {
    final db = stubPlayerDatabase(random: Random(6));
    final session = bootSession(db);
    await pumpScreen(tester, db, session);

    await tester.tap(find.text('Squad'));
    await tester.pumpAndSettle();

    // Home 15 is the top-rated player (85), so his row is on screen first.
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Home 15'),
        matching: find.text('XI'),
      ),
      findsOneWidget,
      reason: 'the best player starts, and the list must say so',
    );
    expect(tester.takeException(), isNull);
  });
}
