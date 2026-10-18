import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/constants/tactic_definitions.dart';
import 'package:football_manager_sim/core/models/player.dart';
import 'package:football_manager_sim/core/models/tactics.dart';
import 'package:football_manager_sim/core/services/injury_service.dart';

import '../helpers/test_hive.dart';

/// Finds a probe player whose scare at [matchday] becomes a real absence.
(Player, Injury) _findRealInjury({
  String leagueId = 'test_league',
  int year = 2026,
  int matchday = 0,
}) {
  for (var id = 1; id < 500; id++) {
    final player = stubPlayer(id: id, name: 'Probe $id', random: Random(id));
    final injury = InjuryService.rollMatchInjury(
      player,
      leagueId: leagueId,
      year: year,
      matchday: matchday,
    );
    if (injury != null) return (player, injury);
  }
  fail('no real injury found in the probe range');
}

void main() {
  group('Match scares', () {
    test('a scare is rolled deterministically for the same matchday', () {
      final player = stubPlayer(id: 4, name: 'Probe', random: Random(4));
      final first = InjuryService.rollMatchInjury(player,
          leagueId: 'l', year: 2026, matchday: 7);
      final second = InjuryService.rollMatchInjury(player,
          leagueId: 'l', year: 2026, matchday: 7);

      expect(first?.type, second?.type);
      expect(first?.weeks, second?.weeks);
    });

    test('real absences are the minority, but a real minority', () {
      var real = 0;
      for (var id = 1; id <= 200; id++) {
        final player = stubPlayer(id: id, name: 'Probe $id', random: Random(id));
        if (InjuryService.rollMatchInjury(player,
                leagueId: 'l', year: 2026, matchday: 3) !=
            null) {
          real++;
        }
      }
      // ~58% are expected to become real absences. The bounds are only here
      // to catch a gross regression (everything or nothing); the exact count
      // is deterministic for the fixed seed.
      expect(real, greaterThan(40));
      expect(real, lessThan(160));
    });

    test('the aftermath carries a type, a return date and a morale hit', () {
      final (player, injury) = _findRealInjury();
      final moraleBefore = player.morale;

      final injured = InjuryService.applyMatchInjuries(
        [player],
        [player.name],
        leagueId: 'test_league',
        year: 2026,
        matchday: 0,
      );

      expect(injured, hasLength(1));
      expect(player.isInjured, isTrue);
      expect(player.injuryType, injury.type);
      expect(
        player.injuryReturnDate,
        InjuryService.dateOfMatchday(2026, injury.weeks),
      );
      expect(
        InjuryService.weeksOut(player, year: 2026, matchday: 0),
        injury.weeks,
      );
      expect(player.morale, lessThan(moraleBefore));
    });

    test('a player who went down twice is only treated once', () {
      final (player, injury) = _findRealInjury();

      final injured = InjuryService.applyMatchInjuries(
        [player],
        [player.name, player.name],
        leagueId: 'test_league',
        year: 2026,
        matchday: 0,
      );

      expect(injured, hasLength(1));
      expect(player.injuryType, injury.type);
    });

    test('the already-injured are left alone and strangers are ignored', () {
      final (player, _) = _findRealInjury();
      InjuryService.applyMatchInjuries(
        [player],
        [player.name],
        leagueId: 'test_league',
        year: 2026,
        matchday: 0,
      );

      expect(
        InjuryService.applyMatchInjuries(
          [player],
          [player.name, 'Nobody At All'],
          leagueId: 'test_league',
          year: 2026,
          matchday: 0,
        ),
        isEmpty,
      );
    });
  });

  group('The calendar', () {
    test('weeks out count down with the matchdays', () {
      final (player, injury) = _findRealInjury();
      InjuryService.applyMatchInjuries(
        [player],
        [player.name],
        leagueId: 'test_league',
        year: 2026,
        matchday: 0,
      );

      expect(
        InjuryService.weeksOut(player,
            year: 2026, matchday: injury.weeks - 1),
        1,
      );
      expect(
        InjuryService.weeksOut(player, year: 2026, matchday: injury.weeks),
        0,
      );
    });

    test('the treatment room clears exactly when the return date arrives',
        () {
      final due = stubPlayer(id: 50, name: 'Due', random: Random(50))
        ..isInjured = true
        ..injuryType = 'Knock'
        ..injuryReturnDate = InjuryService.dateOfMatchday(2026, 3);
      final stillOut = stubPlayer(id: 51, name: 'Still out', random: Random(51))
        ..isInjured = true
        ..injuryType = 'Hamstring strain'
        ..injuryReturnDate = InjuryService.dateOfMatchday(2026, 5);
      // Legacy data: an injury flag with no return date must not linger.
      final legacy = stubPlayer(id: 52, name: 'Legacy', random: Random(52))
        ..isInjured = true;

      final healed = InjuryService.healDue(
        [due, stillOut, legacy],
        year: 2026,
        matchday: 3,
      );

      expect(healed.map((p) => p.id), containsAll([50, 52]));
      expect(due.isInjured, isFalse);
      expect(due.injuryType, isNull);
      expect(due.injuryReturnDate, isNull);
      expect(stillOut.isInjured, isTrue);
      expect(stillOut.injuryType, 'Hamstring strain');
      expect(legacy.isInjured, isFalse);
    });

    test('a long injury picked up in spring eats into the next season', () {
      final player = stubPlayer(id: 60, name: 'Late blow', random: Random(60))
        ..isInjured = true
        ..injuryType = 'ACL rupture'
        ..injuryReturnDate = InjuryService.dateOfMatchday(2027, 1);

      expect(
        InjuryService.healDue([player], year: 2027, matchday: 0),
        isEmpty,
      );
      expect(player.isInjured, isTrue);

      expect(
        InjuryService.healDue([player], year: 2027, matchday: 1),
        hasLength(1),
      );
      expect(player.isInjured, isFalse);
      expect(player.injuryType, isNull);
    });
  });

  group('Training knocks', () {
    test('a thousand player-weeks produce a few minor knocks', () {
      var knocks = 0;
      for (var id = 1; id <= 1000; id++) {
        final player = stubPlayer(id: id, name: 'T$id', random: Random(id));
        if (InjuryService.rollTrainingKnock(player,
            leagueId: 'tr', year: 2026, matchday: 5)) {
          knocks++;
          expect(player.isInjured, isTrue);
          expect(
            InjuryService.weeksOut(player, year: 2026, matchday: 5),
            1,
          );
        }
      }
      expect(knocks, greaterThan(0));
      expect(knocks, lessThan(30));
    });

    test('an injured player does not pick up a second knock', () {
      final player = stubPlayer(id: 61, name: 'Hurt', random: Random(61))
        ..isInjured = true;

      for (var week = 0; week < 100; week++) {
        expect(
          InjuryService.rollTrainingKnock(player,
              leagueId: 'tr', year: 2026, matchday: week),
          isFalse,
        );
      }
      expect(player.injuryType, isNull);
    });
  });

  group('The treatment room in selection', () {
    test('an injured star slides down the pecking order for his slot', () {
      final db = stubLeagueDatabase(1);
      final squad = db.teams.first.squad;
      final defender = squad.firstWhere((p) => p.primaryPosition == 'CB');
      defender
        ..isInjured = true
        ..ovr = 95;

      final xi = selectStartingEleven(squad, Formation.fourFourTwo);

      expect(xi, hasLength(11));
      expect(xi.any((p) => p.id == defender.id), isFalse);
    });

    test('when nobody fit can stand in, even an injured player takes the field',
        () {
      final db = stubLeagueDatabase(1);
      final squad = db.teams.first.squad.take(11).toList();
      final keeper = squad.firstWhere((p) => p.primaryPosition == 'GK');
      keeper.isInjured = true;

      final xi = selectStartingEleven(squad, Formation.fourFourTwo);

      expect(xi, hasLength(11));
      expect(xi.any((p) => p.id == keeper.id), isTrue);
    });
  });
}
