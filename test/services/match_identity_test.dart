import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/match.dart';
import 'package:football_manager_sim/core/models/player.dart';
import 'package:football_manager_sim/core/services/match_simulator_service.dart';

import '../helpers/test_hive.dart';

/// The shape of a real club in the shipped data: two players who share a name.
/// Gil Vicente carry two "Zé Carlos" and Degerfors IF two "Sebastian Ohlsson".
List<Player> _twinSquad() => [
      stubPlayer(id: 1, name: 'Keeper', position: 'GK', ovr: 78),
      for (var i = 2; i <= 11; i++)
        stubPlayer(
          id: i,
          name: i == 5 || i == 6 ? 'J. Smith' : 'Squad $i',
          position: 'CB',
          ovr: 74,
          random: Random(i),
        ),
      for (var i = 12; i <= 16; i++)
        stubPlayer(
          id: i,
          name: 'Sub $i',
          position: 'CM',
          ovr: 70,
          random: Random(i),
        ),
    ];

/// Plays one seeded match with the twin squad as the home side.
MatchResult _play(int seed) {
  final squad = _twinSquad();
  return MatchSimulatorService(rng: Random(seed)).simulateMatch(
    homeGoalkeeper: squad.first,
    homeSquad: [
      for (final p in squad)
        if (p.id >= 2 && p.id <= 11) p,
    ],
    awayGoalkeeper:
        stubPlayer(id: 900, name: 'Opp keeper', position: 'GK', ovr: 74),
    awaySquad: [
      for (var i = 901; i <= 910; i++)
        stubPlayer(id: i, name: 'Opp $i', position: 'CB', ovr: 72),
    ],
    homeBench: [
      for (final p in squad)
        if (p.id >= 12) p,
    ],
  );
}

void main() {
  test('twin names keep their own rating lines', () {
    final result = _play(4);
    final twins =
        result.homeRatings.where((r) => r.playerName == 'J. Smith').toList();

    expect(twins, hasLength(2));
    expect({for (final t in twins) t.playerId}, {5, 6});
    // Every line of the report is id-labelled, so nothing downstream has to
    // guess who a line belongs to.
    for (final rating in result.homeRatings) {
      expect(rating.playerId, isNotNull,
          reason: '${rating.playerName} came back without an id');
    }
  });

  test('only the twin who actually came off loses minutes', () {
    for (var seed = 1; seed <= 200; seed++) {
      final result = _play(seed);
      final subsOff = result.events
          .where((e) =>
              e.type == 'sub' && e.team == 'home' && e.player == 'J. Smith')
          .toList();
      if (subsOff.length != 1) continue;
      final offAt = subsOff.single.minute;
      if (offAt >= 90) continue; // a change at the whistle changes nothing

      final twins = result.homeRatings
          .where((r) => r.playerName == 'J. Smith')
          .toList();
      expect(twins, hasLength(2));
      // The twin taken off at [offAt] is the only reduced line; his namesake
      // must stay on a full 90. Under name-keyed minutes both men shared the
      // one entry, so both read back the same reduced figure.
      expect(
        {for (final t in twins) t.minutes},
        {offAt, 90},
        reason: 'seed $seed: the twin taken off at $offAt should be the only '
            'one with reduced minutes',
      );
      return;
    }
    fail('no seed in 1..200 took exactly one J. Smith off before full time');
  });

  test('injury events point at their player by id', () {
    var checked = 0;
    for (var seed = 1; seed <= 80 && checked == 0; seed++) {
      final result = _play(seed);
      final squad = _twinSquad();
      for (final event in result.events) {
        if (event.type != 'injury' || event.team != 'home') continue;
        checked++;
        final id = event.extraData?['playerId'];
        expect(id, isA<int>(), reason: 'seed $seed carried no player id');
        final player = squad.firstWhere((p) => p.id == id);
        expect(player.name, event.player,
            reason: 'the id must belong to the player named on the event');
      }
    }
    expect(checked, greaterThan(0), reason: 'no injury rolled in 80 seeds');
  });
}
