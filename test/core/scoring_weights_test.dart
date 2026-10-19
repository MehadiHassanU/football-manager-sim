import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/player.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/team.dart';
import 'package:football_manager_sim/core/services/match_simulator_service.dart';
import 'package:football_manager_sim/core/services/scorer_attribution_service.dart';
import 'package:football_manager_sim/core/utils/scoring_weights.dart';

import '../helpers/test_hive.dart';

Player _player(int id, String position, {int ovr = 75, int? finishing}) =>
    stubPlayer(
      id: id,
      name: '$position $id',
      position: position,
      ovr: ovr,
      random: Random(id),
    )..finishing = finishing ?? ovr - 4;

void main() {
  group('ScoringWeights', () {
    test('position order matches how football distributes goals', () {
      final st = _player(1, 'ST');
      final winger = _player(2, 'LW');
      final cam = _player(3, 'CAM');
      final cm = _player(4, 'CM');
      final cdm = _player(5, 'CDM');
      final fullBack = _player(6, 'LB');
      final centreBack = _player(7, 'CB');
      final keeper = _player(8, 'GK');

      expect(ScoringWeights.scoring(st),
          greaterThan(ScoringWeights.scoring(winger)));
      expect(ScoringWeights.scoring(winger),
          greaterThan(ScoringWeights.scoring(cam)));
      expect(ScoringWeights.scoring(cam),
          greaterThan(ScoringWeights.scoring(cm)));
      expect(ScoringWeights.scoring(cm),
          greaterThan(ScoringWeights.scoring(cdm)));
      expect(ScoringWeights.scoring(cdm),
          greaterThan(ScoringWeights.scoring(fullBack)));
      expect(ScoringWeights.scoring(fullBack),
          greaterThan(ScoringWeights.scoring(centreBack)));
      expect(ScoringWeights.scoring(keeper), 0);
    });

    test('a better finisher and creator carries more of the weight', () {
      final clinical = _player(1, 'ST', ovr: 80, finishing: 92);
      final wasteful = _player(2, 'ST', ovr: 80, finishing: 45);
      expect(ScoringWeights.scoring(clinical),
          greaterThan(ScoringWeights.scoring(wasteful)));

      final playmaker = _player(3, 'CAM', ovr: 80);
      playmaker.vision = 95;
      final workhorse = _player(4, 'CAM', ovr: 80);
      workhorse.vision = 40;
      expect(ScoringWeights.assist(playmaker),
          greaterThan(ScoringWeights.assist(workhorse)));
    });

    test('a weighted draw concentrates on the striker', () {
      final rng = Random(9);
      final squad = [
        _player(1, 'ST'),
        _player(2, 'CB'),
        _player(3, 'CM'),
        _player(4, 'GK'),
      ];
      final counts = <int, int>{};
      for (var i = 0; i < 2000; i++) {
        final pick = ScoringWeights.pick(squad, ScoringWeights.scoring, rng)!;
        counts.update(pick.id, (v) => v + 1, ifAbsent: () => 1);
      }
      expect(counts[4] ?? 0, 0, reason: 'a keeper never scores');
      expect(counts[1]!, greaterThan((counts[2] ?? 0) * 5));
      expect(counts[1]!, greaterThan((counts[3] ?? 0) * 3));
    });
  });

  group('rival fixture attribution', () {
    test('a season of goals lands on the forwards, not the defenders', () {
      final squad = [
        _player(1, 'GK'),
        _player(2, 'CB'),
        _player(3, 'CB'),
        _player(4, 'LB'),
        _player(5, 'CM'),
        _player(6, 'CAM'),
        _player(7, 'LW'),
        _player(8, 'ST', ovr: 82, finishing: 88),
        _player(9, 'ST', ovr: 70, finishing: 62),
      ];
      final team = Team(
        id: 'fc',
        name: 'FC',
        shortName: 'FC',
        leagueId: 'l',
        country: 'Spain',
        stadiumName: 'Park',
        stadiumCapacity: 30000,
        budget: 1,
        color: '#000000',
        badgeUrl: '',
        squad: squad,
      );
      final season = SeasonState(leagueId: 'l');
      final rng = Random(4);
      const service = ScorerAttributionService();
      for (var i = 0; i < 120; i++) {
        service.attribute(
          season: season,
          home: team,
          away: team,
          homeGoals: 2,
          awayGoals: 0,
          rng: rng,
        );
      }
      final byPosition = <String, int>{};
      for (final record in season.scorers.values) {
        final position =
            squad.firstWhere((p) => p.id == record.playerId).primaryPosition;
        byPosition.update(position, (v) => v + record.goals,
            ifAbsent: () => record.goals);
      }
      final strikerGoals = byPosition['ST'] ?? 0;
      final defenderGoals =
          (byPosition['CB'] ?? 0) + (byPosition['LB'] ?? 0);
      expect(byPosition['GK'] ?? 0, 0);
      expect(strikerGoals, greaterThan(defenderGoals * 3),
          reason: 'byPosition: $byPosition');
    });
  });

  group('live engine', () {
    test('a run of matches sends the goals to the forwards', () {
      final db = stubPlayerDatabase(random: Random(11));
      final squad = db.teams[0].squad;
      final gk = squad.firstWhere((p) => p.primaryPosition == 'GK');
      final xi = squad.where((p) => p.primaryPosition != 'GK').take(10).toList();
      final bench = [
        for (final p in squad)
          if (p.id != gk.id && !xi.any((s) => s.id == p.id)) p,
      ];
      final awaySquad = db.teams[1].squad;
      final awayGk = awaySquad.firstWhere((p) => p.primaryPosition == 'GK');
      final awayXi = awaySquad
          .where((p) => p.primaryPosition != 'GK')
          .take(10)
          .toList();
      final positionOf = {
        for (final p in squad) p.id: p.primaryPosition,
      };

      final goals = <int, int>{};
      for (var seed = 1; seed <= 80; seed++) {
        final result = MatchSimulatorService(rng: Random(seed)).simulateMatch(
          homeGoalkeeper: gk,
          homeSquad: xi,
          homeBench: bench,
          awayGoalkeeper: awayGk,
          awaySquad: awayXi,
        );
        for (final rating in result.homeRatings) {
          final id = rating.playerId;
          if (id == null || rating.goals == 0) continue;
          goals.update(id, (v) => v + rating.goals,
              ifAbsent: () => rating.goals);
        }
      }

      int goalsIn(Set<String> positions) => goals.entries
          .where((e) => positions.contains(positionOf[e.key]))
          .fold(0, (sum, e) => sum + e.value);

      final strikerGoals = goalsIn({'ST', 'CF'});
      final wingerGoals = goalsIn({'LW', 'RW', 'LM', 'RM'});
      final midfielderGoals = goalsIn({'CM', 'CAM', 'CDM'});
      final defenderGoals = goalsIn({'CB', 'LB', 'RB'});
      final keeperGoals = goalsIn({'GK'});

      expect(keeperGoals, 0);
      expect(strikerGoals, greaterThan(defenderGoals * 4),
          reason: 'forwards $strikerGoals vs defenders $defenderGoals');
      expect(strikerGoals, greaterThan(midfielderGoals),
          reason: 'forwards $strikerGoals vs midfielders $midfielderGoals');
      expect(strikerGoals, greaterThanOrEqualTo(wingerGoals),
          reason: 'forwards $strikerGoals vs wingers $wingerGoals');
      expect(defenderGoals, lessThan(strikerGoals + wingerGoals),
          reason: 'defenders must not carry a meaningful share of the goals');
    });
  });
}
