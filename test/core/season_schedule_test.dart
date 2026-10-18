import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/services/save_service.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';

import '../helpers/test_hive.dart';

List<String> _ids(int n) => [for (var i = 0; i < n; i++) 't$i'];

SeasonState _season(int clubCount, {int seed = 1}) {
  final ids = _ids(clubCount);
  return SeasonState(
    leagueId: 'test_league',
    currentYear: 2026,
    isPreSeason: false,
    records: {for (final id in ids) id: LeagueRecord()},
    rounds: buildRounds(ids, rng: Random(seed)),
  );
}

void main() {
  group('Round-robin schedule', () {
    test('a 20-club league plays 38 matchdays', () {
      final season = _season(20);
      expect(season.rounds.length, 38);
      expect(season.totalMatchdays, 38);
    });

    test('a 2-club league plays both legs', () {
      final season = _season(2);
      expect(season.rounds.length, 2);
      expect(season.rounds[0].length, 1);
      expect(season.rounds[1].length, 1);
    });

    test('every club appears exactly once in every round', () {
      final season = _season(8);
      for (final round in season.rounds) {
        final playing = <String>{};
        for (final fixture in round) {
          expect(playing.add(fixture.homeTeamId), isTrue,
              reason: '${fixture.homeTeamId} played twice in one round');
          expect(playing.add(fixture.awayTeamId), isTrue,
              reason: '${fixture.awayTeamId} played twice in one round');
        }
        expect(playing.length, 8);
      }
    });

    test('every pairing meets twice, once home and once away', () {
      final season = _season(8);
      final meetings = <String, int>{};
      final homeAway = <String, Set<String>>{};
      for (final round in season.rounds) {
        for (final fixture in round) {
          final key = '${fixture.homeTeamId}|${fixture.awayTeamId}';
          meetings.update(key, (v) => v + 1, ifAbsent: () => 1);
          homeAway
              .putIfAbsent(fixture.homeTeamId, () => <String>{})
              .add(fixture.awayTeamId);
        }
      }
      // 8 clubs: 28 unordered pairs, each played twice (56 fixtures).
      expect(meetings.length, 56);
      expect(meetings.values.every((count) => count == 1), isTrue,
          reason: 'a pairing was repeated in the same order');
      for (final host in homeAway.keys) {
        expect(homeAway[host]!.length, 7,
            reason: '$host did not host all seven rivals');
      }
    });

    test('home and away are balanced across the season', () {
      final season = _season(8);
      final home = <String, int>{};
      final away = <String, int>{};
      for (final round in season.rounds) {
        for (final fixture in round) {
          home.update(fixture.homeTeamId, (v) => v + 1, ifAbsent: () => 1);
          away.update(fixture.awayTeamId, (v) => v + 1, ifAbsent: () => 1);
        }
      }
      for (final id in _ids(8)) {
        expect(home[id], 7, reason: '$id home games');
        expect(away[id], 7, reason: '$id away games');
      }
    });

    test('an odd league gives every club exactly one bye per leg', () {
      final clubCount = 7;
      final season = _season(clubCount);
      expect(season.rounds.length, 2 * clubCount);

      for (final leg in [0, 1]) {
        final byes = <String, int>{};
        for (var r = leg * clubCount; r < (leg + 1) * clubCount; r++) {
          final playing = <String>{};
          for (final fixture in season.rounds[r]) {
            playing
              ..add(fixture.homeTeamId)
              ..add(fixture.awayTeamId);
          }
          expect(playing.length, clubCount - 1,
              reason: 'round $r should feature ${clubCount - 1} clubs');
          for (final id in _ids(clubCount)) {
            if (!playing.contains(id)) {
              byes.update(id, (v) => v + 1, ifAbsent: () => 1);
            }
          }
        }
        expect(byes.length, clubCount,
            reason: 'every club should get a bye in leg $leg');
        expect(byes.values.every((count) => count == 1), isTrue,
            reason: 'a club got more than one bye in leg $leg');
      }
    });

    test('the same seed produces the same schedule', () {
      final a = _season(9, seed: 42);
      final b = _season(9, seed: 42);
      for (var r = 0; r < a.rounds.length; r++) {
        for (var i = 0; i < a.rounds[r].length; i++) {
          expect(a.rounds[r][i].homeTeamId, b.rounds[r][i].homeTeamId);
          expect(a.rounds[r][i].awayTeamId, b.rounds[r][i].awayTeamId);
        }
      }
    });

    test('a different seed produces a different opening round', () {
      final a = _season(9, seed: 1);
      final b = _season(9, seed: 2);
      final same = [
        for (var i = 0; i < a.rounds[0].length; i++)
          a.rounds[0][i].homeTeamId == b.rounds[0][i].homeTeamId,
      ].every((e) => e);
      expect(same, isFalse);
    });
  });

  group('Resolving the next opponent', () {
    test('finds the club fixture for the round being played', () {
      final season = _season(8);
      for (var r = 0; r < 5; r++) {
        final fixture = season.userFixtureForRound(r, 't3');
        expect(fixture, isNotNull, reason: 'round $r');
        expect(fixture!.involves('t3'), isTrue);
      }
    });

    test('returns null on a bye rather than guessing an opponent', () {
      final season = _season(7);
      var byes = 0;
      for (var r = 0; r < season.rounds.length; r++) {
        final fixture = season.userFixtureForRound(r, 't3');
        // Seven clubs, one on a bye: three fixtures feature the other six.
        expect(season.fixturesForRound(r).length, 3);
        if (fixture == null) {
          // A bye means the club is genuinely absent from the round, not that
          // the lookup failed to find a real pairing.
          byes += 1;
          expect(
            season.fixturesForRound(r).any((f) => f.involves('t3')),
            isFalse,
          );
        }
      }
      expect(byes, 2, reason: 'one bye per leg for t3');
    });

    test('isByeRound reports the round actually being played', () {
      final byeSeason = _season(7);
      final roundWithBye = [
        for (var r = 0; r < byeSeason.rounds.length; r++)
          if (byeSeason.userFixtureForRound(r, 't3') == null) r,
      ].first;

      final atBye = SeasonState(
        leagueId: byeSeason.leagueId,
        currentMatchday: roundWithBye,
        records: byeSeason.records,
        rounds: byeSeason.rounds,
      );
      expect(atBye.isByeRound('t3'), isTrue);
      expect(atBye.currentFixtureFor('t3'), isNull);

      final atPlay = SeasonState(
        leagueId: byeSeason.leagueId,
        currentMatchday: 0,
        records: byeSeason.records,
        rounds: byeSeason.rounds,
      );
      expect(atPlay.isByeRound('t3'), isFalse);
    });

    test('an out-of-range round has no fixture', () {
      final season = _season(8);
      expect(season.userFixtureForRound(-1, 't0'), isNull);
      expect(season.userFixtureForRound(season.rounds.length, 't0'), isNull);
    });
  });

  group('Simulating a round', () {
    test('ten matchdays leave every club on the same number of games', () {
      final season = _season(8);
      for (var r = 0; r < 10; r++) {
        simulateRound(season, r);
      }
      for (final entry in season.records.entries) {
        expect(entry.value.played, 10,
            reason: '${entry.key} played ${entry.value.played}');
      }
    });

    test('points awarded match the results behind them', () {
      final season = _season(8);
      for (var r = 0; r < 10; r++) {
        simulateRound(season, r);
      }

      var playedFixtures = 0;
      var drawnFixtures = 0;
      for (final round in season.rounds) {
        for (final fixture in round) {
          if (!fixture.played) continue;
          playedFixtures += 1;
          if (fixture.homeGoals == fixture.awayGoals) drawnFixtures += 1;
        }
      }
      expect(playedFixtures, 40);

      // A win is worth 3 in total; a draw is worth 1 + 1 = 2. So a league
      // hands out three points per decisive match and two per draw.
      final totalPoints =
          season.records.values.fold<int>(0, (sum, rec) => sum + rec.points);
      expect(totalPoints, 3 * playedFixtures - drawnFixtures);

      // Every drawn fixture is counted on both of its clubs.
      final totalDraws =
          season.records.values.fold<int>(0, (sum, rec) => sum + rec.drawn);
      expect(totalDraws, drawnFixtures * 2);
    });

    test('every record stays internally consistent', () {
      final season = _season(8);
      for (var r = 0; r < 14; r++) {
        simulateRound(season, r);
      }
      for (final entry in season.records.entries) {
        final rec = entry.value;
        expect(rec.won + rec.drawn + rec.lost, rec.played,
            reason: '${entry.key} results do not add up');
        expect(rec.points, rec.won * 3 + rec.drawn, reason: entry.key);
      }
    });

    test('simulation is deterministic for a given season and round', () {
      final a = _season(8, seed: 3);
      final b = _season(8, seed: 3);
      for (var r = 0; r < 6; r++) {
        simulateRound(a, r);
        simulateRound(b, r);
      }
      expect(a.standings, b.standings);
    });

    test('an already-played fixture is not simulated twice', () {
      final season = _season(8);
      simulateRound(season, 0);
      final snapshot = {
        for (final f in season.rounds[0]) f.homeTeamId: f.homeGoals,
      };
      simulateRound(season, 0);
      for (final f in season.rounds[0]) {
        expect(snapshot[f.homeTeamId], f.homeGoals);
      }
      for (final rec in season.records.values) {
        expect(rec.played, 1);
      }
    });

    test('a simulated scoreline is never negative and scoring is believable',
        () {
      // The old Poisson count returned minus one when the first draw already
      // fell under the threshold, which pushed negative goals into the table
      // and biased every simulated match a goal low. A full 14-round, 8-club
      // season is 112 club-fixtures: at roughly 1.25 goals per side that is
      // about 140 goals, while the broken generator produced under 80.
      final season = _season(8);
      for (var r = 0; r < season.rounds.length; r++) {
        simulateRound(season, r);
      }
      var totalGoals = 0;
      for (final round in season.rounds) {
        for (final fixture in round) {
          if (!fixture.played) continue;
          expect(fixture.homeGoals, greaterThanOrEqualTo(0));
          expect(fixture.awayGoals, greaterThanOrEqualTo(0));
          totalGoals += fixture.homeGoals + fixture.awayGoals;
        }
      }
      expect(totalGoals, greaterThan(100),
          reason: 'a full season cannot average under a goal a game');
    });
  });

  group('League table', () {
    test('orders by points, then goal difference, then goals scored', () {
      final season = SeasonState(
        leagueId: 'test_league',
        records: {
          'top': LeagueRecord(won: 5, goalsFor: 10, goalsAgainst: 2),
          'gd': LeagueRecord(won: 5, goalsFor: 8, goalsAgainst: 0),
          'mid': LeagueRecord(won: 4, drawn: 2, goalsFor: 9, goalsAgainst: 5),
          'low': LeagueRecord(lost: 6, goalsFor: 1, goalsAgainst: 12),
        },
      );
      expect(
        season.table().map((row) => row.teamId).toList(),
        ['top', 'gd', 'mid', 'low'],
      );
    });

    test('tied clubs get distinct positions ordered by goal difference', () {
      // Three clubs on 3 points each. Ranking a points value instead of the
      // club would report position 1 for all three.
      final season = SeasonState(
        leagueId: 'test_league',
        records: {
          'a': LeagueRecord(played: 1, won: 1, goalsFor: 4, goalsAgainst: 0),
          'b': LeagueRecord(played: 1, won: 1, goalsFor: 2, goalsAgainst: 1),
          'c': LeagueRecord(played: 1, won: 1, goalsFor: 1, goalsAgainst: 0),
        },
      );
      final table = season.table();
      expect(table.map((r) => r.teamId).toList(), ['a', 'b', 'c']);
      expect(table.map((r) => r.position).toList(), [1, 2, 3]);
      expect(season.positionOf('b'), 2);
    });

    test('an unknown club has no position', () {
      final season = _season(4);
      expect(season.positionOf('nobody'), 0);
    });
  });

  group('Season calendar', () {
    test('the winter break falls at the midpoint', () {
      final season = _season(20);
      expect(season.totalMatchdays, 38);
      expect(season.winterBreakRound, 19);
    });

    test('a fresh season is in progress and has not finished', () {
      final season = _season(8);
      expect(season.isPostSeason, isFalse);
      expect(season.matchdayNumber, 1);
    });

    test('the season is over once every round has been played', () {
      final season = SeasonState(
        leagueId: 'test_league',
        currentMatchday: 14,
        records: {for (final id in _ids(8)) id: LeagueRecord()},
        rounds: buildRounds(_ids(8), rng: Random(1)),
      );
      expect(season.isPostSeason, isTrue);
    });
  });

  group('Schedule persistence', () {
    late Directory storageDir;
    late SaveService save;

    setUpAll(() async {
      storageDir = await initTestHive('fms_season_schedule');
      save = SaveService();
      await save.init(storageDirectory: storageDir.path);
    });

    tearDownAll(() async {
      await disposeTestHive(storageDir);
    });

    test('fixtures and records survive a Hive round-trip', () async {
      final original = _season(6, seed: 5);
      simulateRound(original, 0);
      simulateRound(original, 1);
      await save.saveSeason(original);

      final loaded = await save.loadSeason();
      expect(loaded, isNotNull);
      expect(loaded!.rounds.length, original.rounds.length);
      expect(loaded.standings, original.standings);
      for (final id in _ids(6)) {
        expect(loaded.records[id]!.played, original.records[id]!.played);
        expect(loaded.records[id]!.goalsFor, original.records[id]!.goalsFor);
      }
      final firstFixture = original.rounds[0].first;
      final loadedFixture = loaded.rounds[0].firstWhere(
        (f) => f.homeTeamId == firstFixture.homeTeamId,
      );
      expect(loadedFixture.awayTeamId, firstFixture.awayTeamId);
      expect(loadedFixture.homeGoals, firstFixture.homeGoals);
      expect(loadedFixture.played, isTrue);
    });

    test('the save is stamped with the current schema version', () async {
      expect(await save.storedSchemaVersion(), SaveService.schemaVersion);
      expect(SaveService.schemaVersion, greaterThanOrEqualTo(2));
    });
  });
}
