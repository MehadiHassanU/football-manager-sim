import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/constants/game_constants.dart';
import 'package:football_manager_sim/core/models/match.dart';
import 'package:football_manager_sim/core/models/player.dart';
import 'package:football_manager_sim/core/services/match_simulator_service.dart';

import '../helpers/test_hive.dart';

/// A prepared side: the keeper, the ten out-field starters and the spare
/// bodies on the bench.
class _Side {
  _Side(List<Player> squad)
      : goalkeeper =
            squad.firstWhere((p) => p.primaryPosition == 'GK'),
        xi = squad
            .where((p) => p.primaryPosition != 'GK')
            .take(10)
            .toList() {
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

/// Runs the full simulator on the stub clubs with a seeded RNG.
({MatchResult result, _Side home, _Side away}) play(
  int seed, {
  bool withBench = true,
  bool injureBench = false,
  bool benchKeeper = false,
}) {
  final db = stubPlayerDatabase(random: Random(seed));
  final home = _Side(db.teams[0].squad);
  final away = _Side(db.teams[1].squad);
  if (injureBench) {
    for (final p in home.bench) {
      p.isInjured = true;
    }
    for (final p in away.bench) {
      p.isInjured = true;
    }
  }
  if (benchKeeper) {
    // The freshest, best player on either bench — and still a keeper.
    home.bench.add(stubPlayer(
        id: 9001, name: 'Home Bench GK', position: 'GK', ovr: 90));
    away.bench.add(stubPlayer(
        id: 9002, name: 'Away Bench GK', position: 'GK', ovr: 90));
  }
  final result = MatchSimulatorService(rng: Random(seed * 31 + 7)).simulateMatch(
    homeGoalkeeper: home.goalkeeper,
    homeSquad: home.xi,
    homeBench: withBench ? home.bench : const [],
    awayGoalkeeper: away.goalkeeper,
    awaySquad: away.xi,
    awayBench: withBench ? away.bench : const [],
  );
  return (result: result, home: home, away: away);
}

/// The first seeded match (within [limit] seeds) that used a substitute.
({MatchResult result, _Side home, _Side away, int seed}) firstMatchWithSub(
  int limit, {
  bool withBench = true,
}) {
  for (var seed = 1; seed <= limit; seed++) {
    final match = play(seed, withBench: withBench);
    if (match.result.events.any((e) => e.type == 'sub')) {
      return (
        result: match.result,
        home: match.home,
        away: match.away,
        seed: seed,
      );
    }
  }
  fail('no seeded match used a substitute within $limit seeds');
}

void main() {
  /// The old feed invented a substitute from the eleven just to fill the
  /// event, so substitutions happened even when nobody was on the bench.
  group('substitutions need a bench', () {
    test('a match without a bench changes nobody', () {
      for (var seed = 1; seed <= 10; seed++) {
        final match = play(seed, withBench: false);
        expect(
          match.result.events.where((e) => e.type == 'sub'),
          isEmpty,
          reason: 'no bench, no changes (seed $seed)',
        );
      }
    });

    test('an injured substitute is never sent on', () {
      for (var seed = 1; seed <= 6; seed++) {
        final match = play(seed, injureBench: true);
        expect(
          match.result.events.where((e) => e.type == 'sub'),
          isEmpty,
          reason: 'a bench in the treatment room is no bench (seed $seed)',
        );
      }
    });

    test('a keeper on the bench is never sent on', () {
      var subs = 0;
      for (var seed = 1; seed <= 6; seed++) {
        final match = play(seed, benchKeeper: true);
        final events = match.result.events;
        for (final sub in events.where((e) => e.type == 'sub')) {
          expect(sub.description, isNot(contains('Bench GK')),
              reason: 'the engine never changes keepers mid-match');
        }
        subs += events.where((e) => e.type == 'sub').length;
      }
      expect(subs, greaterThan(0),
          reason: 'the freshest out-field bench still came on');
    });
  });

  group('the changes themselves', () {
    test('fresh legs arrive in the closing half-hour', () {
      final match = firstMatchWithSub(400);
      final subs = match.result.events
          .where((e) =>
              e.type == 'sub' && e.description.contains('comes on for'))
          .toList();
      expect(subs, isNotEmpty);
      for (final sub in subs) {
        expect(sub.minute, greaterThanOrEqualTo(55),
            reason: 'freshness changes are a second-half thing');
      }
      // Nobody is ever double-substituted on, and the cap holds.
      final onNames = subs.map((e) => e.description.split(' comes on')[0]);
      expect(onNames.toSet().length, onNames.length);
      for (final team in ['home', 'away']) {
        expect(
          match.result.events
              .where((e) => e.type == 'sub' && e.team == team)
              .length,
          lessThanOrEqualTo(maxSubstitutions),
        );
      }
    });

    test('an injury change comes straight from the bench', () {
      var injuryChanges = 0;
      for (var seed = 1; seed <= 25; seed++) {
        final match = play(seed);
        final result = match.result;
        for (final sub in result.events.where((e) => e.type == 'sub')) {
          if (!sub.description.contains('cannot continue')) continue;
          injuryChanges++;
          expect(
            result.events.any((e) =>
                e.type == 'injury' &&
                e.minute == sub.minute &&
                e.player == sub.player),
            isTrue,
            reason: 'the change must follow the injury it covers',
          );
        }
      }
      expect(injuryChanges, greaterThan(0),
          reason: 'injuries with fit cover should show up across 25 matches');
    });

    test('the player who came off does not play the full match', () {
      final match = firstMatchWithSub(400);
      for (final sub in match.result.events.where((e) => e.type == 'sub')) {
        final ratings =
            sub.team == 'home' ? match.result.homeRatings : match.result.awayRatings;
        final off = ratings.firstWhere((r) => r.playerName == sub.player);
        expect(off.minutes, lessThan(matchMinutes),
            reason: 'nobody who was withdrawn played the whole match');
        if (off.started) {
          expect(off.minutes, sub.minute,
              reason: 'his day ended when the change was made');
        } else {
          // A substitute can be withdrawn again. His minutes run from the
          // change that brought him on to this one.
          final arrival = match.result.events.firstWhere(
            (e) =>
                e.type == 'sub' &&
                e.description.startsWith('${sub.player} '),
            orElse: () => fail('no arrival event for ${sub.player}'),
          );
          expect(off.minutes, sub.minute - arrival.minute,
              reason: 'a substitute only plays until he is taken off again');
        }
      }
    });
  });

  group('the ratings sheet follows the changes', () {
    test('keepers and starters play ninety and substitutes get the rest', () {
      final match = firstMatchWithSub(400);
      final result = match.result;

      void checkSide(
        List<PlayerRating> ratings,
        _Side side,
        String team,
      ) {
        final subsOn =
            result.events.where((e) => e.type == 'sub' && e.team == team);
        // The keeper leads the sheet and is rated like everyone else.
        expect(ratings.first.playerName, side.goalkeeper.name);
        expect(ratings.first.minutes, matchMinutes);
        expect(ratings.first.started, isTrue);
        // Eleven starters plus one row per substitute used.
        expect(ratings, hasLength(11 + subsOn.length));
        expect(ratings.where((r) => !r.started), hasLength(subsOn.length));
        for (final r in ratings) {
          expect(r.minutes, inInclusiveRange(0, matchMinutes));
        }
        // The same player never appears twice.
        expect(
          ratings.map((r) => r.playerName).toSet().length,
          ratings.length,
        );
      }

      checkSide(result.homeRatings, match.home, 'home');
      checkSide(result.awayRatings, match.away, 'away');
    });

    test('substitutes who were never used get no rating at all', () {
      final match = firstMatchWithSub(400);
      final result = match.result;

      for (final entry in [
        (side: match.home, team: 'home', ratings: result.homeRatings),
        (side: match.away, team: 'away', ratings: result.awayRatings),
      ]) {
        final usedNames = {
          for (final sub in result.events
              .where((e) => e.type == 'sub' && e.team == entry.team))
            sub.description.split(' comes on')[0].split(' replaces')[0],
        };
        final startedNames = {
          entry.side.goalkeeper.name,
          for (final p in entry.side.xi) p.name,
        };
        for (final r in entry.ratings) {
          expect(
            startedNames.contains(r.playerName) ||
                usedNames.contains(r.playerName),
            isTrue,
            reason: '${r.playerName} is rated but never played',
          );
        }
      }
    });
  });
}
