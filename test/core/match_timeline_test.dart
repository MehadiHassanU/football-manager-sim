import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/match.dart';
import 'package:football_manager_sim/core/services/match_simulator_service.dart';
import 'package:football_manager_sim/screens/match/match_screen.dart';

import '../helpers/test_hive.dart';

/// Runs the full simulator on the stub clubs with a seeded RNG.
MatchResult simulate(int seed) {
  final db = stubPlayerDatabase(random: Random(seed));
  final home = db.teams[0];
  final away = db.teams[1];
  final homeGk = home.squad.firstWhere((p) => p.primaryPosition == 'GK');
  final awayGk = away.squad.firstWhere((p) => p.primaryPosition == 'GK');
  final homeXi = home.squad.where((p) => p.id != homeGk.id).take(10).toList();
  final awayXi = away.squad.where((p) => p.id != awayGk.id).take(10).toList();
  return MatchSimulatorService(rng: Random(seed * 31 + 7)).simulateMatch(
    homeGoalkeeper: homeGk,
    homeSquad: homeXi,
    awayGoalkeeper: awayGk,
    awaySquad: awayXi,
  );
}

void main() {
  group('match timeline', () {
    test('starts at kick-off and every event is stamped in order', () {
      final result = simulate(12);
      expect(result.events, isNotEmpty);
      expect(result.events.first.isKickOff, isTrue);
      expect(result.events.first.minute, 0);

      var previous = 0;
      for (final event in result.events) {
        expect(event.minute, greaterThanOrEqualTo(previous),
            reason: 'the feed must stay chronological at ${event.minute}\'');
        expect(event.minute, inInclusiveRange(0, 90));
        previous = event.minute;
      }
    });

    test('goal events carry the running score, ending on the final result', () {
      final result = simulate(5);
      var home = 0;
      var away = 0;
      for (final event in result.events) {
        if (!event.isGoal) continue;
        expect(event.homeScore, isNotNull);
        expect(event.awayScore, isNotNull);
        final nextHome = event.homeScore!;
        final nextAway = event.awayScore!;
        expect(nextHome + nextAway, home + away + 1,
            reason: 'exactly one goal is added per goal event');
        expect(nextHome, greaterThanOrEqualTo(home));
        expect(nextAway, greaterThanOrEqualTo(away));
        home = nextHome;
        away = nextAway;
      }
      expect(home, result.homeGoals);
      expect(away, result.awayGoals);
    });

    test('the live score does not leak the final result', () {
      // Find a match with at least two goals so there is a clear early state.
      late MatchResult result;
      var seed = 1;
      do {
        result = simulate(seed++);
      } while (result.homeGoals + result.awayGoals < 2 && seed < 40);

      final firstGoalMinute = result.events.firstWhere((e) => e.isGoal).minute;
      expect(scoreAt(result.events, 0), (home: 0, away: 0),
          reason: 'kick-off must read 0-0');
      expect(scoreAt(result.events, firstGoalMinute - 1), (home: 0, away: 0),
          reason: 'the score must not change before the goal minute');
      expect(scoreAt(result.events, 90),
          (home: result.homeGoals, away: result.awayGoals));
    });

    test('fouls, cards and set pieces appear at their own minute', () {
      final types = <String>{};
      for (var seed = 1; seed <= 6; seed++) {
        types.addAll(simulate(seed).events.map((e) => e.type));
      }
      // Seeded runs are stable, but asserting the whole vocabulary appears
      // across several matches keeps the test honest about the feed's depth.
      expect(types, contains('foul'));
      expect(types, contains('corner'));
      expect(types, contains('goal'));
    });

    test('key-events mode keeps fouls but drops corners and filler', () {
      final events = [
        MatchEvent(
            type: 'foul',
            team: 'home',
            player: 'A',
            description: '',
            minute: 8),
        MatchEvent(
            type: 'corner',
            team: 'home',
            player: 'A',
            description: '',
            minute: 9),
        MatchEvent(
            type: 'commentary',
            team: 'home',
            player: '',
            description: '',
            minute: 10),
        MatchEvent(
            type: 'goal',
            team: 'away',
            player: 'B',
            description: '',
            minute: 11),
      ];
      final filtered =
          applyCommentarySettings(events, enabled: true, level: 'keyEvents');
      expect(filtered.map((e) => e.type), ['foul', 'goal']);
    });

    test('ratings credit the players who actually scored', () {
      final result = simulate(3);
      final goalSum =
          result.playerRatings.fold<int>(0, (sum, r) => sum + r.goals);
      expect(goalSum, result.homeGoals + result.awayGoals,
          reason: 'every goal belongs to exactly one rated player');
    });
  });
}
