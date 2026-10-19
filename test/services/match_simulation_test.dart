import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/constants/game_constants.dart';
import 'package:football_manager_sim/core/models/match.dart';
import 'package:football_manager_sim/core/models/player.dart';
import 'package:football_manager_sim/core/services/match_simulator_service.dart';

import '../helpers/test_hive.dart';

/// A prepared side: the keeper, the ten out-field starters and the bench.
class _Side {
  _Side(List<Player> squad)
      : goalkeeper = squad.firstWhere((p) => p.primaryPosition == 'GK'),
        xi = squad.where((p) => p.primaryPosition != 'GK').take(10).toList() {
    final xiIds = {
      goalkeeper.id,
      for (final p in xi) p.id,
    };
    bench = [
      for (final p in squad)
        if (!xiIds.contains(p.id)) p,
    ];
  }

  final Player goalkeeper;
  final List<Player> xi;
  late final List<Player> bench;
}

typedef _Match = ({MatchSimulation simulation, _Side home, _Side away});

_Match _simulation(int seed, {bool manualHome = false}) {
  final db = stubPlayerDatabase(random: Random(seed));
  final home = _Side(db.teams[0].squad);
  final away = _Side(db.teams[1].squad);
  return (
    simulation: MatchSimulation(
      homeGoalkeeper: home.goalkeeper,
      homeSquad: home.xi,
      awayGoalkeeper: away.goalkeeper,
      awaySquad: away.xi,
      homeBench: home.bench,
      awayBench: away.bench,
      rng: Random(seed * 31 + 7),
      manualHome: manualHome,
    ),
    home: home,
    away: away,
  );
}

MatchResult _oneShot(int seed) {
  final db = stubPlayerDatabase(random: Random(seed));
  final home = _Side(db.teams[0].squad);
  final away = _Side(db.teams[1].squad);
  return MatchSimulatorService(rng: Random(seed * 31 + 7)).simulateMatch(
    homeGoalkeeper: home.goalkeeper,
    homeSquad: home.xi,
    awayGoalkeeper: away.goalkeeper,
    awaySquad: away.xi,
    homeBench: home.bench,
    awayBench: away.bench,
  );
}

String _eventKey(MatchEvent e) =>
    '${e.minute}|${e.type}|${e.team}|${e.player}|${e.description}|'
    '${e.homeScore}|${e.awayScore}';

void main() {
  group('resumable simulation', () {
    test('pausing between chunks does not change the match', () {
      for (var seed = 1; seed <= 12; seed++) {
        final oneShot = _oneShot(seed);

        final match = _simulation(seed);
        // Jump around the clock the way the live ticker does: some calls land
        // on a chunk boundary, others short of the next one.
        for (var minute = 0; minute < matchMinutes; minute += 7) {
          match.simulation.advanceTo(minute);
        }
        match.simulation.advanceTo(matchMinutes);
        final piecemeal = match.simulation.finish();

        expect(piecemeal.homeGoals, oneShot.homeGoals,
            reason: 'seed $seed: home goals');
        expect(piecemeal.awayGoals, oneShot.awayGoals,
            reason: 'seed $seed: away goals');
        expect(
          piecemeal.events.map(_eventKey).toList(),
          oneShot.events.map(_eventKey).toList(),
          reason: 'seed $seed: the timeline must not depend on pausing',
        );
        expect(
          piecemeal.homeRatings
              .map((r) => '${r.playerId}|${r.rating}|${r.minutes}')
              .toList(),
          oneShot.homeRatings
              .map((r) => '${r.playerId}|${r.rating}|${r.minutes}')
              .toList(),
          reason: 'seed $seed: home ratings',
        );
        expect(
          piecemeal.awayRatings
              .map((r) => '${r.playerId}|${r.rating}|${r.minutes}')
              .toList(),
          oneShot.awayRatings
              .map((r) => '${r.playerId}|${r.rating}|${r.minutes}')
              .toList(),
          reason: 'seed $seed: away ratings',
        );
      }
    });

    test('full time is reached even when no earlier call did', () {
      final match = _simulation(4);
      match.simulation.advanceTo(0);
      expect(match.simulation.isFinished, isFalse);
      match.simulation.advanceTo(matchMinutes);
      expect(match.simulation.isFinished, isTrue);
      expect(match.simulation.minute, matchMinutes);
    });
  });

  group('red cards', () {
    test('a dismissal removes the player for the rest of the match', () {
      MatchSimulation? withRed;
      for (var seed = 1; seed <= 600 && withRed == null; seed++) {
        final simulation = _simulation(seed).simulation;
        simulation.advanceTo(matchMinutes);
        if (simulation.events
            .any((e) => e.isCard && e.extraData?['red'] == true)) {
          withRed = simulation;
        }
      }
      expect(withRed, isNotNull,
          reason: 'red cards should turn up across 600 matches');

      final simulation = withRed!;
      final reds = simulation.events
          .where((e) => e.isCard && e.extraData?['red'] == true)
          .toList();
      for (final red in reds) {
        final home = red.team == 'home';
        final id = red.extraData!['playerId'] as int;
        expect(red.description, contains('sent off'));
        expect(
          simulation.sentOff(home: home).any((p) => p.id == id),
          isTrue,
          reason: '${red.player} must be on the dismissed list',
        );
        expect(
          simulation.onPitch(home: home).any((p) => p.id == id),
          isFalse,
          reason: 'a sent-off player cannot still be on the pitch',
        );
        expect(
          simulation.events.where(
              (e) => e.minute > red.minute && e.player == red.player),
          isEmpty,
          reason: 'no later incident can involve ${red.player}',
        );
        if (red.extraData?['secondYellow'] == true) {
          expect(
            simulation.events.any((e) =>
                e.minute <= red.minute &&
                e.isCard &&
                e.player == red.player &&
                e.extraData?['red'] == false),
            isTrue,
            reason: 'a second yellow needs a first one on record',
          );
        }
      }

      for (final home in [true, false]) {
        expect(
          simulation.onPitch(home: home).length,
          10 - simulation.sentOff(home: home).length,
          reason: 'a dismissal is never replaced',
        );
      }
    });
  });

  group('manual substitutions', () {
    test('a manager-managed side never substitutes on its own', () {
      var injuries = 0;
      for (var seed = 1; seed <= 30; seed++) {
        final simulation = _simulation(seed, manualHome: true).simulation;
        simulation.advanceTo(matchMinutes);
        injuries += simulation.events
            .where((e) => e.isInjury && e.team == 'home')
            .length;
        expect(
          simulation.events.where((e) => e.type == 'sub' && e.team == 'home'),
          isEmpty,
          reason: 'seed $seed: the manager makes those calls, not the assistant',
        );
      }
      expect(injuries, greaterThan(0),
          reason: 'the fixture should include home injuries to skip over');
    });

    test('a change swaps the eleven and is reflected in the ratings', () {
      final match = _simulation(3, manualHome: true);
      final simulation = match.simulation;
      simulation.advanceTo(20);

      final off = simulation.onPitch(home: true).first;
      final on = simulation.bench(home: true)
          .firstWhere((p) => !p.isInjured && p.primaryPosition != 'GK');
      final minute = simulation.minute;

      expect(simulation.substitute(home: true, off: off, on: on), isTrue);
      expect(simulation.substitutionsUsed(home: true), 1);
      expect(simulation.substitutionsLeft(home: true), maxSubstitutions - 1);
      expect(simulation.onPitch(home: true).any((p) => p.id == on.id), isTrue);
      expect(simulation.onPitch(home: true).any((p) => p.id == off.id), isFalse);
      expect(simulation.bench(home: true).any((p) => p.id == on.id), isFalse);
      expect(simulation.events.last.type, 'sub');
      expect(simulation.events.last.minute, minute);
      expect(simulation.events.last.description,
          '${on.name} replaces ${off.name}.');

      // The change is illegal the second time: neither man is eligible now.
      expect(simulation.substitute(home: true, off: off, on: on), isFalse);
      // Keepers are never brought on mid-match.
      expect(
        simulation.substitute(
          home: true,
          off: simulation.onPitch(home: true).first,
          on: match.home.goalkeeper,
        ),
        isFalse,
      );
      // A player who is not on the pitch cannot be taken off.
      expect(
        simulation.substitute(
          home: true,
          off: match.home.xi.first,
          on: simulation.bench(home: true).first,
        ),
        isFalse,
      );

      final result = simulation.finish();
      final offRating =
          result.homeRatings.firstWhere((r) => r.playerId == off.id);
      final onRating =
          result.homeRatings.firstWhere((r) => r.playerId == on.id);
      expect(offRating.minutes, minute);
      expect(offRating.started, isTrue);
      expect(onRating.started, isFalse);
      expect(onRating.minutes, matchMinutes - minute);
    });

    test('five changes are allowed and a sixth is refused', () {
      final simulation = _simulation(5, manualHome: true).simulation;
      simulation.advanceTo(10);
      final spare = simulation.bench(home: true)
          .firstWhere((p) => !p.isInjured && p.primaryPosition != 'GK');

      for (var i = 0; i < maxSubstitutions; i++) {
        final off = simulation.onPitch(home: true).first;
        final on = simulation.bench(home: true)
            .firstWhere((p) => !p.isInjured && p.primaryPosition != 'GK');
        expect(simulation.substitute(home: true, off: off, on: on), isTrue,
            reason: 'change ${i + 1} should be allowed');
      }
      expect(simulation.substitutionsLeft(home: true), 0);
      expect(simulation.bench(home: true), isEmpty);

      expect(
        simulation.substitute(
          home: true,
          off: simulation.onPitch(home: true).first,
          on: spare,
        ),
        isFalse,
        reason: 'the bench is empty, so nothing can come on',
      );
    });
  });
}
