import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';
import 'package:football_manager_sim/screens/league_table/league_table_screen.dart';

import '../helpers/test_hive.dart';

/// Pumps the screen with a career whose season carries [scorers].
Future<void> _pumpScreen(
  WidgetTester tester, {
  required List<ScorerRecord> scorers,
  bool withStandings = true,
}) async {
  final db = stubLeagueDatabase(6);
  final ids = [for (final t in db.teams) t.id];
  final season = SeasonState(
    leagueId: 'test_league',
    currentMatchday: 5,
    currentYear: 2026,
    isPreSeason: false,
    records: {
      for (final id in ids)
        id: withStandings
            ? LeagueRecord(
                played: 5, won: 2, drawn: 1, lost: 2, goalsFor: 7, goalsAgainst: 6)
            : LeagueRecord(),
    },
    rounds: [for (final round in buildRounds(ids, rng: Random(1))) round],
    scorers: {for (final s in scorers) s.playerId: s},
  );

  final session = CareerSession(
    manager: Manager(
      name: 'Boss',
      age: 40,
      nationality: 'Spain',
      teamId: db.teams.first.id,
    ),
    team: db.teams.first,
    season: season,
  );

  final container = ProviderContainer(
    overrides: [
      playerDatabaseProvider.overrideWith((ref) async => db),
      careerSessionProvider.overrideWith((ref) => session),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LeagueTableScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  late Directory storageDir;

  setUpAll(() async {
    storageDir = await initTestHive('fms_league_scorers');
  });

  tearDownAll(() async {
    await disposeTestHive(storageDir);
  });

  testWidgets('the table toggles to the season top scorers', (tester) async {
    await _pumpScreen(tester, scorers: [
      ScorerRecord(
        playerId: 1,
        playerName: 'Ace Striker',
        clubId: 'club_1',
        clubName: 'Club One',
        goals: 9,
        assists: 3,
      ),
      ScorerRecord(
        playerId: 2,
        playerName: 'Rival Poacher',
        clubId: 'club_2',
        clubName: 'Club Two',
        goals: 6,
        assists: 1,
      ),
    ]);

    // The standings are the default view.
    expect(find.text('Pts'), findsOneWidget);
    expect(find.text('Ace Striker'), findsNothing);

    await tester.tap(find.text('Top scorers'));
    await tester.pump();

    expect(find.text('Ace Striker'), findsOneWidget);
    expect(find.text('Rival Poacher'), findsOneWidget);
    // Rank order: the nine-goal striker leads.
    final first = tester.getTopLeft(find.text('Ace Striker'));
    final second = tester.getTopLeft(find.text('Rival Poacher'));
    expect(first.dy, lessThan(second.dy));
    // Goal and assist columns are headed.
    expect(find.text('G'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);

    await tester.tap(find.text('Table'));
    await tester.pump();
    expect(find.text('Pts'), findsOneWidget);
    expect(find.text('Ace Striker'), findsNothing);
  });

  testWidgets('an empty scorer list says so instead of showing a blank',
      (tester) async {
    await _pumpScreen(tester, scorers: const []);

    await tester.tap(find.text('Top scorers'));
    await tester.pump();

    expect(find.text('No goals yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
