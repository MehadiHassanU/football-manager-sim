import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/cup.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/services/cup_service.dart';
import 'package:football_manager_sim/core/services/injury_service.dart';
import 'package:football_manager_sim/core/utils/season_calendar.dart';

/// Four clubs: six league rounds with the cup spliced in at anchors [2, 5].
(SeasonState, CupState) _cuppedSeason({int currentMatchday = 0}) {
  final ids = [for (var i = 0; i < 4; i++) 'club_$i'];
  final rounds = buildRounds(ids, rng: Random(3));
  final cup = CupService.attachCup(
    rounds: rounds,
    teamIds: ids,
    leagueId: 'test_league',
    currentYear: 2026,
  )!;
  final season = SeasonState(
    leagueId: 'test_league',
    currentMatchday: currentMatchday,
    currentYear: 2026,
    isPreSeason: false,
    records: {for (final id in ids) id: LeagueRecord()},
    rounds: rounds,
    cup: cup,
  );
  return (season, cup);
}

void main() {
  test('the round clock is the same one injuries use', () {
    expect(SeasonCalendar.dateOfRound(2026, 0), DateTime(2026, 8, 1));
    expect(SeasonCalendar.dateOfRound(2026, 3), DateTime(2026, 8, 22));
    expect(
      InjuryService.dateOfMatchday(2026, 3),
      SeasonCalendar.dateOfRound(2026, 3),
      reason: 'the physio and the schedule must read one clock',
    );
  });

  test('dates, months and the season label read like a fixture list', () {
    expect(SeasonCalendar.formatDate(DateTime(2026, 8, 15)), 'Sat 15 Aug');
    expect(SeasonCalendar.formatDate(DateTime(2026, 8, 11)), 'Tue 11 Aug');
    expect(SeasonCalendar.monthLabel(DateTime(2026, 8, 15)), 'August 2026');
    expect(SeasonCalendar.seasonLabel(2026), '2026/27');
    expect(SeasonCalendar.seasonLabel(2099), '2099/00');
  });

  test('a cupped season lists league ties, cup ties and the winter break',
      () {
    final (season, cup) = _cuppedSeason();
    final entries = SeasonCalendar.build(season, 'club_0');

    expect(cup.anchors, [2, 5]);
    // Six league ties + two cup ties + the winter-break marker.
    expect(entries, hasLength(9));
    expect(
      entries.where((e) => e.kind == CalendarEntryKind.winterBreak),
      hasLength(1),
    );

    final first = entries.first;
    expect(first.kind, CalendarEntryKind.fixture);
    expect(first.fixture!.involves('club_0'), isTrue);
    expect(first.date, DateTime(2026, 8, 1));

    final cupRows = entries.where((e) => e.isCup).toList();
    expect(cupRows, hasLength(2));
    expect(cupRows[0].cupRoundLabel, 'Semi-finals');
    expect(cupRows[0].date, DateTime(2026, 8, 11),
        reason: 'cup ties read midweek, four days before the league rhythm');
    expect(cupRows[1].cupRoundLabel, 'Final');
    expect(cupRows[1].kind, CalendarEntryKind.cupSlot,
        reason: 'the bracket only draws a round when the one before is done');
    expect(cupRows[1].date, DateTime(2026, 9, 1));
  });

  test('an eliminated club sees no future cup date', () {
    final (season, cup) = _cuppedSeason();
    final semis = season.rounds[cup.anchors[0]];
    for (final fixture in semis) {
      if (fixture.involves('club_0')) {
        // The user loses the semi-final, whichever side he is on.
        final isHome = fixture.homeTeamId == 'club_0';
        fixture.record(isHome ? 0 : 1, isHome ? 1 : 0);
      } else {
        fixture.record(1, 0);
      }
    }
    CupService.progressCup(season);

    expect(CupService.clubIsAlive(season, 'club_0'), isFalse);
    final entries = SeasonCalendar.build(season, 'club_0');
    expect(
      entries.where((e) => e.kind == CalendarEntryKind.cupSlot),
      isEmpty,
      reason: 'a knockout is final: no more cup dates for the club',
    );
    // The semi-final he did play is still there, with its result.
    final semi = entries
        .singleWhere((e) => e.kind == CalendarEntryKind.fixture && e.isCup);
    expect(semi.fixture!.played, isTrue);
  });

  test('the round the season sits on is flagged; the break marker is not', () {
    final (season, _) = _cuppedSeason(currentMatchday: 5);
    final entries = SeasonCalendar.build(season, 'club_0');
    final current = entries.where((e) => e.isCurrent).toList();
    expect(current, hasLength(1));
    expect(current.single.round, 5);
    expect(current.single.isCup, isTrue);

    final (atBreak, _) = _cuppedSeason(currentMatchday: 4);
    final marked =
        SeasonCalendar.build(atBreak, 'club_0').where((e) => e.isCurrent);
    expect(marked, hasLength(1));
    expect(marked.single.kind, CalendarEntryKind.fixture,
        reason: 'the break row marks the pause, the fixture row is what plays');
    expect(marked.single.round, 4);
  });

  test('a recorded cup bye gets a row of its own', () {
    final ids = ['a', 'b', 'c', 'd'];
    final rounds = buildRounds(ids, rng: Random(3));
    rounds.insert(2, [
      Fixture(
        homeTeamId: 'b',
        awayTeamId: 'c',
        round: 2,
        leg: 0,
        competition: 'cup',
      ),
    ]);
    final season = SeasonState(
      leagueId: 'test_league',
      currentYear: 2026,
      isPreSeason: false,
      records: {for (final id in ids) id: LeagueRecord()},
      rounds: rounds,
      cup: CupState(
        name: 'National Cup',
        anchors: [2],
        ties: [1],
        byes: {0: 'a'},
      ),
    );

    final entries = SeasonCalendar.build(season, 'a');
    final bye = entries.singleWhere((e) => e.kind == CalendarEntryKind.bye);
    expect(bye.round, 2);
    expect(bye.cupRoundLabel, 'Final');
    expect(bye.date, DateTime(2026, 8, 11));
    expect(bye.isCup, isTrue);
  });

  test('a league bye is only news while the season is sitting on it', () {
    final ids = ['a', 'b', 'c'];
    final rounds = buildRounds(ids, rng: Random(3));

    SeasonState seasonAt(int round) => SeasonState(
          leagueId: 'test_league',
          currentMatchday: round,
          currentYear: 2026,
          isPreSeason: false,
          records: {for (final id in ids) id: LeagueRecord()},
          rounds: rounds,
        );

    final byeRound = List.generate(rounds.length, (r) => r).firstWhere(
      (r) => seasonAt(r).userFixtureForRound(r, 'a') == null,
      orElse: () => -1,
    );
    expect(byeRound, greaterThanOrEqualTo(0),
        reason: 'three clubs must produce a bye for somebody');

    final entries = SeasonCalendar.build(seasonAt(byeRound), 'a');
    final byes = entries.where((e) => e.kind == CalendarEntryKind.bye).toList();
    expect(byes, hasLength(1), reason: 'only the current bye earns a row');
    expect(byes.single.isCurrent, isTrue);
    expect(byes.single.cupRoundLabel, isNull);
  });

  test('an undrawn season has no rows', () {
    expect(
      SeasonCalendar.build(SeasonState(leagueId: 'test_league'), 'a'),
      isEmpty,
    );
  });
}
