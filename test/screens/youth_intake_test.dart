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

/// The academy used to swallow its own intake: the prospects were added to the
/// session, but the StateProvider re-emitted the same instance, so Riverpod saw
/// no change and the tab stayed on "0 prospects in the academy".
void main() {
  late Directory storageDir;

  setUpAll(() async {
    storageDir = await initTestHive('fms_youth_intake');
  });

  tearDownAll(() async {
    await disposeTestHive(storageDir);
  });

  testWidgets('Run Youth Intake renders the new prospects immediately',
      (tester) async {
    final db = stubPlayerDatabase(random: Random(9));
    final team = db.teams.first;
    final session = CareerSession(
      manager: Manager(name: 'Boss', age: 40, nationality: 'Spain'),
      team: team,
      season: SeasonState(leagueId: team.leagueId),
    );
    expect(session.youthPlayers, isEmpty);

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

    await tester.tap(find.text('Youth'));
    await tester.pumpAndSettle();
    expect(find.text('No youth prospects yet'), findsOneWidget);

    await tester.tap(find.text('Run Youth Intake'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(session.youthPlayers, hasLength(3));
    // The list is lazy, so only the cards that fit on screen are built; the
    // header count proves all three landed.
    expect(find.byType(ProspectCard), findsWidgets);
    expect(find.text('3 prospects in the academy'), findsOneWidget);
    expect(find.textContaining('0 prospects'), findsNothing,
        reason: 'the academy count must follow the intake');
    expect(tester.takeException(), isNull);
  });
}
