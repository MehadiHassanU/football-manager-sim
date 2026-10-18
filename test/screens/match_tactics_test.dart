import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/constants/tactic_definitions.dart';
import 'package:football_manager_sim/core/models/match.dart';
import 'package:football_manager_sim/core/models/player.dart';
import 'package:football_manager_sim/core/models/tactics.dart';
import 'package:football_manager_sim/core/services/match_simulator_service.dart';
import 'package:football_manager_sim/screens/match/match_screen.dart';

import '../helpers/test_hive.dart';

/// A prepared side: the keeper, ten out-field starters and the spare bodies.
class _Side {
  _Side(List<Player> squad)
      : goalkeeper =
            squad.firstWhere((p) => p.primaryPosition == 'GK'),
        xi = squad
            .where((p) => p.primaryPosition != 'GK')
            .take(10)
            .toList() {
    final taken = {
      goalkeeper.id,
      for (final p in xi) p.id,
    };
    bench = [
      for (final p in squad)
        if (!taken.contains(p.id)) p,
    ];
  }

  final Player goalkeeper;
  final List<Player> xi;
  late final List<Player> bench;
}

void main() {
  group('matchTacticsFor', () {
    const tactic =
        Tactic(playingStyle: PlayingStyle.attacking, tempo: Tempo.fast);

    test('the home manager takes the field with his instructions', () {
      final tactics = matchTacticsFor(userIsHome: true, userTactic: tactic);
      expect(tactics.home, same(tactic));
      expect(tactics.away, isNull);
    });

    test("the away manager's instructions travel too", () {
      // Regression: the call site used to be `userIsHome ? tactic : null`, so
      // every away match was quietly played on default instructions while the
      // manager's own dials were dropped on the coach down.
      final tactics = matchTacticsFor(userIsHome: false, userTactic: tactic);
      expect(tactics.home, isNull);
      expect(tactics.away, same(tactic));
    });
  });

  group("the engine reads the visiting manager's tactic", () {
    MatchResult run({
      required int seed,
      required _Side home,
      required _Side away,
      Tactic? awayTactic,
    }) =>
        MatchSimulatorService(rng: Random(seed)).simulateMatch(
          homeGoalkeeper: home.goalkeeper,
          homeSquad: home.xi,
          awayGoalkeeper: away.goalkeeper,
          awaySquad: away.xi,
          homeBench: home.bench,
          awayBench: away.bench,
          awayTactic: awayTactic,
        );

    test('a tactic passed as the away side changes the match', () {
      const tactic =
          Tactic(playingStyle: PlayingStyle.attacking, tempo: Tempo.fast);
      final db = stubLeagueDatabase(4, random: Random(3));
      final home = _Side(db.playersByTeam['club_0']!);
      final away = _Side(db.playersByTeam['club_1']!);

      // The wiring guarantees the away tactic arrives; the engine must then
      // do something with it, or the fix is cosmetic. Same seed, same squads:
      // the only difference is the tactic. One seed whose match differs is
      // proof the instruction reached the pitch.
      var seenDifference = false;
      for (var seed = 1; seed <= 40 && !seenDifference; seed++) {
        final withTactic =
            run(seed: seed, home: home, away: away, awayTactic: tactic);
        final without = run(seed: seed, home: home, away: away);
        seenDifference = withTactic.homeGoals != without.homeGoals ||
            withTactic.awayGoals != without.awayGoals ||
            withTactic.events.length != without.events.length;
      }
      expect(seenDifference, isTrue,
          reason: 'no seed in 1..40 produced a different match for the '
              'visiting side with an attacking, fast-paced tactic');
    });
  });
}
