import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/services/save_service.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';
import 'package:football_manager_sim/screens/career/career_dashboard_screen.dart';

import '../helpers/test_hive.dart';

/// A season that has been played all the way to the end, with the table
/// filled in by the same round simulator the game uses.
CareerSession _finishedCareer(PlayerDatabase db) {
  final ids = [for (final t in db.teams) t.id];
  final rounds = buildRounds(ids, rng: Random(1));
  final records = <String, LeagueRecord>{
    for (final id in ids) id: LeagueRecord(),
  };

  // Fixtures and records are mutable and shared, so simulating through a
  // working season fills the very objects the finished season will hold.
  final working = SeasonState(
    leagueId: 'test_league',
    currentYear: 2026,
    isPreSeason: false,
    records: records,
    rounds: rounds,
  );
  for (var r = 0; r < rounds.length; r++) {
    simulateRound(working, r);
  }

  final userTeam = db.teams.first;
  return CareerSession(
    manager: Manager(
        name: 'Boss', age: 40, nationality: 'Spain', teamId: userTeam.id),
    team: userTeam,
    season: SeasonState(
      leagueId: 'test_league',
      currentMatchday: rounds.length,
      currentYear: 2026,
      isPreSeason: false,
      records: records,
      rounds: rounds,
    ),
  )..userResults.addAll([3, 3, 1, 0, 3]);
}

void main() {
  late Directory storageDir;
  const clubCount = 8;

  setUpAll(() async {
    storageDir = await initTestHive('fms_season_rollover');
  });

  tearDownAll(() async {
    await disposeTestHive(storageDir);
  });

  group('Season rollover', () {
    testWidgets('starts a fresh season for the next year', (tester) async {
      final db = stubLeagueDatabase(clubCount);
      final session = _finishedCareer(db);
      expect(session.season.isPostSeason, isTrue);
      expect(session.season.records[session.team.id]!.played, greaterThan(0));

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
          child: const MaterialApp(home: CareerDashboardScreen()),
        ),
      );
      expect(find.text('Start next season'), findsOneWidget);
      await tester.tap(find.text('Start next season'));
      await tester.pump();

      final after = container.read(careerSessionProvider)!;
      expect(after.season.currentYear, 2027);
      expect(after.season.currentMatchday, 0);
      expect(after.season.isWinterBreak, isFalse);
      // The new season rides a cup: the league double round-robin plus the
      // cup rounds spliced into the calendar.
      expect(after.season.cup, isNotNull);
      expect(after.season.rounds.length,
          2 * (clubCount - 1) + after.season.cup!.anchors.length);
      expect(after.userResults, isEmpty,
          reason: 'form belongs to a season, not a career');

      for (final entry in after.season.records.entries) {
        expect(entry.value.played, 0, reason: entry.key);
        expect(entry.value.points, 0, reason: entry.key);
      }

      expect(after.team.matchesPlayed, 0);
      expect(after.team.goalsFor, 0);
      expect(after.team.wins, 0);
      expect(after.team.points, 0);
    });

    testWidgets('a club stays put when no neighbouring division exists',
        (tester) async {
      // The stub has one division, so nothing can be promoted or relegated.
      final db = stubLeagueDatabase(clubCount);
      final session = _finishedCareer(db);
      final originalLeague = session.team.leagueId;

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
          child: const MaterialApp(home: CareerDashboardScreen()),
        ),
      );
      await tester.tap(find.text('Start next season'));
      await tester.pump();

      final after = container.read(careerSessionProvider)!;
      expect(after.team.leagueId, originalLeague,
          reason: 'promotion needs a real adjacent league in the data');
      expect(after.season.leagueId, originalLeague);
    });
  });

  group('Legacy save migration', () {
    // The adapter and the migration both touch disk, so these run as plain
    // async tests: real file I/O inside a widget test never completes.
    test('a v1 schedule survives a Hive round-trip as a legacy season',
        () async {
      final save = SaveService();
      await save.init(storageDirectory: storageDir.path);

      final legacy = SeasonState(
        leagueId: 'test_league',
        currentMatchday: 2,
        currentYear: 2025,
        isPreSeason: false,
        legacyFixturePairs: const ['club_0|club_1', 'club_2|club_3'],
      );
      await save.saveSeason(legacy);

      final readBack = await save.loadSeason();
      expect(readBack!.rounds, isEmpty,
          reason: 'a v1 save has no round structure to recover');
      expect(readBack.legacyFixturePairs, const [
        'club_0|club_1',
        'club_2|club_3',
      ]);
      expect(readBack.currentMatchday, 2);
    });

    test('migrating a v1 season rebuilds a playable schedule', () {
      final db = stubLeagueDatabase(clubCount);
      final userTeam = db.teams.first;
      final legacy = SeasonState(
        leagueId: 'test_league',
        currentMatchday: 2,
        currentYear: 2025,
        isPreSeason: false,
        legacyFixturePairs: const ['club_0|club_1', 'club_2|club_3'],
      );

      final migrated = migrateSeasonSchedule(legacy, userTeam, db);

      expect(migrated.rounds.length, 2 * (clubCount - 1));
      expect(migrated.records.keys.length, clubCount);
      expect(migrated.currentMatchday, 2,
          reason: 'the matchday counter is carried across');
      expect(migrated.currentYear, 2025);
      expect(migrated.isWinterBreak, isFalse,
          reason: 'the break is re-derived from the new schedule');
      // The user is genuinely due to play someone in the migrated round.
      expect(migrated.currentFixtureFor(userTeam.id), isNotNull);
    });

    test('migrating a v1 season clamps a counter past the new schedule', () {
      final db = stubLeagueDatabase(4);
      final userTeam = db.teams.first;
      final legacy = SeasonState(
        leagueId: 'test_league',
        // The old flat list implied a bogus total of N-1 matchdays.
        currentMatchday: 999,
        isPreSeason: false,
        legacyFixturePairs: const ['club_0|club_1'],
      );

      final migrated = migrateSeasonSchedule(legacy, userTeam, db);
      expect(migrated.currentMatchday, migrated.rounds.length);
      expect(migrated.isPostSeason, isTrue);
    });

    test('a current season is left untouched', () {
      final db = stubLeagueDatabase(clubCount);
      final userTeam = db.teams.first;
      final ids = [for (final t in db.teams) t.id];
      final current = SeasonState(
        leagueId: 'test_league',
        currentYear: 2026,
        isPreSeason: false,
        records: {for (final id in ids) id: LeagueRecord()},
        rounds: buildRounds(ids, rng: Random(3)),
      );

      expect(identical(migrateSeasonSchedule(current, userTeam, db), current),
          isTrue);
    });

    test('a league too small to schedule is left alone', () {
      final db = stubLeagueDatabase(1);
      final lone = db.teams.first;
      final legacy = SeasonState(
        leagueId: 'test_league',
        isPreSeason: false,
        legacyFixturePairs: const ['club_0|club_1'],
      );

      final migrated = migrateSeasonSchedule(legacy, lone, db);
      expect(migrated.rounds, isEmpty);
    });
  });
}
