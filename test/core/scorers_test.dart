import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';

import '../helpers/test_hive.dart';

/// Runs one round of rival fixtures through the same path the game uses, with
/// squads available so every goal can be attributed.
SeasonState _playedRound(int clubCount, {int round = 0}) {
  final db = stubLeagueDatabase(clubCount);
  final ids = [for (final t in db.teams) t.id];
  final season = SeasonState(
    leagueId: 'test_league',
    currentYear: 2026,
    isPreSeason: false,
    records: {for (final id in ids) id: LeagueRecord()},
    rounds: buildRounds(ids, rng: Random(1)),
  );
  simulateRound(
    season,
    round,
    strengths: {for (final t in db.teams) t.id: 60.0},
    teams: {for (final t in db.teams) t.id: t},
  );
  return season;
}

void main() {
  group('ScorerRecord bookkeeping', () {
    test('contributions accumulate per player and order by goals then assists',
        () {
      final season = SeasonState(leagueId: 'l1');
      season.recordContribution(
        playerId: 1,
        playerName: 'Alpha',
        clubId: 'a',
        clubName: 'A FC',
        goals: 2,
      );
      season.recordContribution(
        playerId: 1,
        playerName: 'Alpha',
        clubId: 'a',
        clubName: 'A FC',
        assists: 1,
      );
      season.recordContribution(
        playerId: 2,
        playerName: 'Bravo',
        clubId: 'b',
        clubName: 'B FC',
        goals: 2,
        assists: 3,
      );

      expect(season.scorers[1]!.goals, 2);
      expect(season.scorers[1]!.assists, 1);
      expect(season.scorers[2]!.goals, 2);
      // Tied on goals: the better provider leads.
      expect(season.topScorers().map((r) => r.playerId).toList(), [2, 1]);
    });

    test('a zero contribution writes nothing', () {
      final season = SeasonState(leagueId: 'l1');
      season.recordContribution(
        playerId: 5,
        playerName: 'Ghost',
        clubId: 'a',
        clubName: 'A FC',
      );
      expect(season.scorers, isEmpty);
    });
  });

  group('Rival fixture attribution', () {
    test('every simulated goal gets a scorer from the right club', () {
      final season = _playedRound(8);
      final db = stubLeagueDatabase(8);

      final played = season.rounds[0].where((f) => f.played).toList();
      expect(played, hasLength(4));
      final totalGoals = played.fold<int>(
          0, (sum, f) => sum + f.homeGoals + f.awayGoals);
      final attributed =
          season.scorers.values.fold<int>(0, (sum, r) => sum + r.goals);

      expect(season.scorers, isNotEmpty);
      expect(attributed, totalGoals,
          reason: 'every goal must be credited exactly once');

      for (final record in season.scorers.values) {
        final club = db.teams.firstWhere((t) => t.id == record.clubId);
        final author = club.squad.where((p) => p.id == record.playerId).toList();
        expect(author, hasLength(1),
            reason: '${record.playerName} must belong to ${club.name}');
        expect(author.single.name, record.playerName);
        // Keepers never score in the attribution model.
        expect(author.single.primaryPosition, isNot('GK'));
      }

      // Assists are common enough that a full round without one would mean
      // the assist pass never runs.
      expect(season.scorers.values.any((r) => r.assists > 0), isTrue);
    });

    test('the round is deterministic, so a restored save replays it', () {
      final first = _playedRound(8);
      final second = _playedRound(8);
      expect(
        {
          for (final e in first.scorers.entries)
            e.key: '${e.value.goals}:${e.value.assists}',
        },
        {
          for (final e in second.scorers.entries)
            e.key: '${e.value.goals}:${e.value.assists}',
        },
      );
    });

    test('without squads the round still simulates but records nothing', () {
      final db = stubLeagueDatabase(8);
      final ids = [for (final t in db.teams) t.id];
      final season = SeasonState(
        leagueId: 'test_league',
        currentYear: 2026,
        isPreSeason: false,
        records: {for (final id in ids) id: LeagueRecord()},
        rounds: buildRounds(ids, rng: Random(1)),
      );
      simulateRound(season, 0, strengths: {for (final t in db.teams) t.id: 60.0});
      expect(season.scorers, isEmpty);
      expect(season.rounds[0].every((f) => f.played), isTrue);
    });
  });
}
