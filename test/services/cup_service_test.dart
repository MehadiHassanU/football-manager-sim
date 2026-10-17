import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/cup.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/services/cup_service.dart';

/// Builds a season whose schedule already has a cup spliced in, keeping the
/// rounds list the single source of truth (cup rounds live inside it).
SeasonState _seasonWithCup(int clubCount, {int year = 2026}) {
  final ids = [for (var i = 0; i < clubCount; i++) 'club_$i'];
  final rounds = buildRounds(ids, rng: Random(1));
  final cup = CupService.attachCup(
    rounds: rounds,
    teamIds: ids,
    leagueId: 'test_league',
    currentYear: year,
  );
  return SeasonState(
    leagueId: 'test_league',
    currentYear: year,
    isPreSeason: false,
    records: {for (final id in ids) id: LeagueRecord()},
    rounds: rounds,
    cup: cup,
  );
}

/// A fresh 8-club season: 14 league rounds, quarter-final / semi-final /
/// final spliced at deterministic anchors.
SeasonState _eightClubSeason() => _seasonWithCup(8);

Set<String> _participantsOf(List<Fixture> round) => {
      for (final f in round) ...[f.homeTeamId, f.awayTeamId],
    };

/// Replays one cup round by giving every tie a fixed home win/end score so
/// the winners can be predicted exactly.
void _recordRound(SeasonState season, List<Fixture> round, int home, int away) {
  for (final f in round) {
    f.record(home, away);
  }
  CupService.progressCup(season);
}

void main() {
  test('an 8-club cup splices quarter-final, semi-final and final anchors',
      () {
    final season = _eightClubSeason();
    final cup = season.cup!;

    // 14 league rounds + 3 cup rounds. Anchors land between league matchdays
    // and compensate for the rounds inserted before them.
    expect(cup.anchors, [3, 8, 12]);
    expect(season.rounds.length, 17);

    // Round 0 is drawn immediately: four ties, every club enters once.
    final first = season.rounds[cup.anchors[0]];
    expect(first.length, 4);
    final participants = _participantsOf(first);
    expect(participants.length, 8);
    for (final fixture in first) {
      expect(fixture.competition, 'cup');
      expect(fixture.played, isFalse);
    }

    // The league schedule itself is untouched: 8 clubs over 14 matchdays is
    // 56 ties, none of them tagged cup.
    final leagueFixtures = [for (final r in season.rounds) ...r]
        .where((f) => f.competition == 'league')
        .toList();
    expect(leagueFixtures.length, 56);
  });

  test('anchors stay at valid, strictly increasing calendar positions at scale',
      () {
    final season = _seasonWithCup(20);
    final cup = season.cup!;

    // 38 league rounds + 5 bracket rounds (20 -> 10 -> 5 -> 3 -> 2 -> 1).
    expect(cup.anchors.length, 5);
    expect(season.rounds.length, 43);

    for (var k = 1; k < cup.anchors.length; k++) {
      expect(cup.anchors[k], greaterThan(cup.anchors[k - 1]));
    }
    for (final anchor in cup.anchors) {
      expect(anchor, inExclusiveRange(0, season.rounds.length - 1));
    }
    // Round 0 holds every club: ten ties from twenty entrants.
    expect(season.rounds[cup.anchors[0]].length, 10);
    expect(CupService.roundNameOf(season, 0), 'Round of 20');
  });

  test('a league too small or a calendar too short gets no cup', () {
    final ids = ['a', 'b', 'c'];
    final rounds = buildRounds(ids, rng: Random(1));
    final cup = CupService.attachCup(
      rounds: rounds,
      teamIds: ids,
      leagueId: 'test_league',
      currentYear: 2026,
    );
    expect(cup, isNull);
    // Untouched schedule: three clubs still means a 6-matchday double
    // round-robin, just without a cup riding on it.
    expect(rounds.length, 6);
  });

  test('round names follow the bracket stage', () {
    final season = _eightClubSeason();
    expect(CupService.roundNameOf(season, 0), 'Quarter-finals');
    expect(CupService.roundNameOf(season, 1), 'Semi-finals');
    expect(CupService.roundNameOf(season, 2), 'Final');
    expect(CupService.roundNameOf(season, 3), 'Cup'); // out of range
  });

  test('completed rounds breed the next round from their winners only', () {
    final season = _eightClubSeason();
    final cup = season.cup!;
    final first = season.rounds[cup.anchors[0]];

    // Every first-round tie goes to the home side 2-0.
    final expectedWinners = {for (final f in first) f.homeTeamId};
    _recordRound(season, first, 2, 0);

    final second = season.rounds[cup.anchors[1]];
    expect(second.length, 2);
    final survivors = _participantsOf(second);
    expect(survivors.difference(expectedWinners), isEmpty);
    for (final f in second) {
      expect(f.competition, 'cup');
    }

    // Idempotent: progress again and nothing changes.
    CupService.progressCup(season);
    expect(season.rounds[cup.anchors[1]].length, 2);
  });

  test('drawn ties are decided by seeded penalties, deterministically', () {
    SeasonState drawnScenario() {
      final season = _eightClubSeason();
      final cup = season.cup!;
      _recordRound(season, season.rounds[cup.anchors[0]], 1, 1); // all draws
      return season;
    }

    final first = drawnScenario();
    final second = drawnScenario();
    // Same inputs, same seed: the shootout winners must be identical.
    expect(
      _participantsOf(second.rounds[second.cup!.anchors[1]]),
      _participantsOf(first.rounds[first.cup!.anchors[1]]),
    );
  });

  test('odd brackets record a bye and carry the team into the next round', () {
    final season = _seasonWithCup(5);
    final cup = season.cup!;

    // Five entrants: two ties plus a recorded bye. 10 league rounds + 3 cup.
    expect(cup.anchors, [2, 6, 9]);
    expect(season.rounds.length, 13);
    final first = season.rounds[cup.anchors[0]];
    expect(first.length, 2);
    expect(cup.byes[0], isNotNull);
    expect(
        _participantsOf(first).contains(cup.byes[0]!), isFalse);

    _recordRound(season, first, 2, 0);

    // The bye team joins the two winners: three contenders, one tie plus a
    // new trailing bye.
    final second = season.rounds[cup.anchors[1]];
    expect(second.length, 1);
    expect(cup.byes[1], isNotNull);
    final survivors = _participantsOf(second);
    expect(survivors.length, 2);
    expect(survivors.contains(cup.byes[1]!), isFalse);
  });

  test('the final decides the cup, and knocked-out clubs stop being alive',
      () {
    final season = _eightClubSeason();
    final cup = season.cup!;
    final quarters = season.rounds[cup.anchors[0]];

    _recordRound(season, quarters, 2, 0);
    final semiSurvivors = _participantsOf(season.rounds[cup.anchors[1]]);

    // Before the semis are played the winners of the last round are alive.
    final semifinal = season.rounds[cup.anchors[1]];
    final aliveAfterQuarters = {
      for (final id in semiSurvivors) id: CupService.clubIsAlive(season, id),
    };
    expect(aliveAfterQuarters.values, everyElement(isTrue));

    _recordRound(season, semifinal, 2, 0);
    final finalists =
        _participantsOf(season.rounds[cup.anchors[2]]);
    expect(finalists.length, 2);

    // Both finalists alive while the final is still to be played.
    for (final id in finalists) {
      expect(CupService.clubIsAlive(season, id), isTrue);
    }

    _recordRound(season, season.rounds[cup.anchors[2]], 1, 0);
    final winner = CupService.cupWinnerOf(season);
    expect(winner, isNotNull);
    expect(finalists.contains(winner), isTrue);

    // The bracket is decided: nobody is "alive" any more.
    for (final id in semiSurvivors) {
      expect(CupService.clubIsAlive(season, id), isFalse);
    }
    // Losers of the quarter-finals were knocked out at that stage.
    for (final f in quarters) {
      expect(CupService.clubIsAlive(season, f.awayTeamId), isFalse);
    }
  });

  test('an unfinished cup has no winner yet', () {
    final season = _eightClubSeason();
    expect(CupService.cupWinnerOf(season), isNull);
    _recordRound(season, season.rounds[season.cup!.anchors[0]], 2, 0);
    expect(CupService.cupWinnerOf(season), isNull);
  });

  test('cup state round-trips through JSON, byes included', () {
    final season = _seasonWithCup(5);
    final cup = season.cup!;
    final json = cup.toJson();
    final restored = CupState.fromJson(json);

    expect(restored.name, cup.name);
    expect(restored.anchors, cup.anchors);
    expect(restored.byes[0], cup.byes[0]);

    // And a fixture keeps its competition tag through persistence.
    final fixture = season.rounds[cup.anchors[0]].first;
    final restoredFixture = Fixture.fromJson(fixture.toJson());
    expect(restoredFixture.competition, 'cup');
    expect(restoredFixture.homeTeamId, fixture.homeTeamId);
    expect(restoredFixture.awayTeamId, fixture.awayTeamId);
  });

  test('the draw is seeded by league and year, not wall-clock', () {
    final a = _seasonWithCup(8);
    final b = _seasonWithCup(8, year: 2027);

    String pairingsOf(SeasonState s) {
      final cup = s.cup!;
      return [
        for (final f in s.rounds[cup.anchors[0]]) f.toJson().toString(),
      ].join('|');
    }
    expect(pairingsOf(a), isNot(pairingsOf(b)));
  });
}
