import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/data/competition_catalog.dart';
import 'package:football_manager_sim/core/models/cup.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/team.dart';
import 'package:football_manager_sim/core/services/cup_service.dart';
import 'package:football_manager_sim/core/utils/season_calendar.dart';

/// A club with just enough identity for the cup pool.
Team _club(String id, String leagueId, int reputation) => Team(
      id: id,
      name: id,
      shortName: id,
      leagueId: leagueId,
      country: 'England',
      stadiumName: '$id Park',
      stadiumCapacity: 30000,
      budget: 20000000,
      color: '#123456',
      badgeUrl: '',
      reputation: reputation,
    );

/// The English pyramid: 20 Premier League clubs, then 24 in each division.
List<Team> _englishPyramid() {
  const leagues = [
    'premier_league',
    'efl_championship',
    'efl_league_one',
    'efl_league_two',
  ];
  final teams = <Team>[];
  var reputation = 95;
  for (var division = 0; division < leagues.length; division++) {
    for (var i = 0; i < (division == 0 ? 20 : 24); i++) {
      teams.add(_club('c${teams.length}', leagues[division],
          (reputation - i).clamp(30, 95)));
    }
    reputation -= 12;
  }
  return teams;
}

/// An English season with its three competitions spliced in.
SeasonState _englishSeason(List<Team> teams) {
  final premierClubs =
      teams.where((t) => t.leagueId == 'premier_league').map((t) => t.id).toList();
  final rounds = buildRounds(premierClubs, rng: Random(7));
  final cups = CupService.attachCompetitions(
    rounds: rounds,
    teams: teams,
    leagueId: 'premier_league',
    currentYear: 2026,
  );
  return SeasonState(
    leagueId: 'premier_league',
    currentYear: 2026,
    isPreSeason: false,
    records: {for (final id in premierClubs) id: LeagueRecord()},
    rounds: rounds,
    cups: cups,
  );
}

void main() {
  group('competition catalog', () {
    test('England runs the FA Cup, the EFL Cup and the Community Shield', () {
      final catalog = CompetitionCatalog.forLeague('premier_league')!;
      expect(catalog.country, 'England');
      expect(catalog.cups.map((c) => c.name), [
        'FA Cup',
        'EFL Cup',
        'FA Community Shield',
      ]);
      expect(catalog.leagues, contains('efl_league_two'));
    });

    test('every catalogued league resolves to a country and a cup', () {
      for (final catalog in CompetitionCatalog.all) {
        for (final league in catalog.leagues) {
          expect(CompetitionCatalog.countryOf(league), catalog.country,
              reason: '$league should map back to ${catalog.country}');
          expect(CompetitionCatalog.forLeague(league)!.cups, isNotEmpty);
        }
      }
    });

    test('the real leagues in the dataset resolve to their real cups', () {
      expect(
          CompetitionCatalog.forLeague('bundesliga')!.cups.first.name,
          'DFB-Pokal');
      expect(CompetitionCatalog.forLeague('laliga_ea_sports')!.cups.first.name,
          'Copa del Rey');
      expect(
          CompetitionCatalog.forLeague('serie_a_enilive')!.cups.first.name,
          'Coppa Italia');
      expect(
          CompetitionCatalog.forLeague('ligue_1_mcdonald_s')!.cups.first.name,
          'Coupe de France');
      expect(CompetitionCatalog.forLeague('liga_portugal')!.cups[1].name,
          'Taça da Liga');
      expect(CompetitionCatalog.forLeague('scottish_prem')!.cups[1].name,
          'Scottish League Cup');
    });
  });

  group('country cups', () {
    test('draws the FA Cup from all 92 league clubs', () {
      final teams = _englishPyramid();
      final season = _englishSeason(teams);
      final faCup = season.cups.firstWhere((c) => c.id == 'fa_cup');

      expect(faCup.name, 'FA Cup');
      expect(faCup.roundNames, [
        'Preliminary round',
        'Round of 64',
        'Round of 32',
        'Round of 16',
        'Quarter-finals',
        'Semi-finals',
        'Final',
      ]);
      expect(faCup.ties, [28, 32, 16, 8, 4, 2, 1]);

      final entrants = [
        for (final list in faCup.entrants.values) ...list,
      ];
      expect(entrants, hasLength(92));
      expect(entrants.toSet(), hasLength(92),
          reason: 'every club enters exactly once');
      // The bottom 56 play the preliminary round; the top flight and the
      // strongest Championship clubs join at the round of 64.
      expect(faCup.entrants[0], hasLength(56));
      expect(faCup.entrants[1], hasLength(36));
      expect(
        faCup.entrants[1]!,
        containsAll([
          for (final t in teams.where((t) => t.leagueId == 'premier_league'))
            t.id,
        ]),
      );
    });

    test('splices every cup round between league matchdays with unique anchors',
        () {
      final teams = _englishPyramid();
      final season = _englishSeason(teams);
      expect(season.cups, hasLength(3));
      expect(
        season.cups.map((c) => c.kind),
        [CupKind.national, CupKind.leagueCup, CupKind.superCup],
      );

      final anchors = <int>[];
      for (final cup in season.cups) {
        expect(cup.anchors, isNotEmpty);
        for (var i = 1; i < cup.anchors.length; i++) {
          expect(cup.anchors[i], greaterThan(cup.anchors[i - 1]),
              reason: '${cup.name} rounds must run in order');
        }
        anchors.addAll(cup.anchors);
      }
      expect(anchors.toSet(), hasLength(anchors.length),
          reason: 'two competitions cannot share a matchday');
      expect(season.rounds, hasLength(38 + 7 + 7 + 1));
      for (final cup in season.cups) {
        expect(season.rounds[cup.anchors.first], isNotEmpty,
            reason: 'round 0 of every cup is drawn at attach');
        for (final anchor in cup.anchors.skip(1)) {
          expect(season.rounds[anchor], isEmpty,
              reason: 'later rounds wait for the bracket to reach them');
        }
      }
    });

    test('league rounds stay on Saturdays and cup rounds on midweek dates', () {
      final teams = _englishPyramid();
      final season = _englishSeason(teams);
      final cupRounds = {
        for (final cup in season.cups) ...cup.anchors,
      };
      for (var round = 0; round < season.rounds.length; round++) {
        final date = SeasonCalendar.dateOf(season, round);
        if (cupRounds.contains(round)) {
          expect(date.weekday, DateTime.wednesday,
              reason: 'cup round $round should be midweek');
        } else {
          expect(date.weekday, DateTime.saturday,
              reason: 'league round $round should be a Saturday');
        }
      }
      final last = SeasonCalendar.dateOf(season, season.rounds.length - 1);
      expect(last.year, 2027,
          reason: 'the season must finish by the following summer');
      expect(last.month, lessThan(8));
    });

    test('the super cup is played before the opening league match', () {
      final teams = _englishPyramid();
      final season = _englishSeason(teams);
      final shield = season.cups.singleWhere((c) => c.kind == CupKind.superCup);
      expect(shield.anchors, [0]);
      expect(shield.entrants[0], hasLength(2));
      final kickoff = SeasonCalendar.dateOf(season, shield.anchors.first);
      final opening = SeasonCalendar.dateOf(season, 1);
      expect(kickoff.isBefore(opening), isTrue);
      expect(shield.ties, [1]);
    });

    test('a full bracket progresses to a decided winner', () {
      final teams = _englishPyramid();
      final season = _englishSeason(teams);

      // Play every fixture in order, filling each bracket round as it comes.
      for (var pass = 0; pass < season.rounds.length + 8; pass++) {
        for (final round in season.rounds) {
          for (final fixture in round) {
            if (!fixture.played) fixture.record(1, 0);
          }
        }
        CupService.progressCup(season);
      }

      for (final cup in season.cups) {
        expect(CupService.isDecided(season, cup), isTrue,
            reason: '${cup.name} should reach a final');
        expect(CupService.winnerOf(season, cup), isNotNull);
      }
      final faCup = season.cups.firstWhere((c) => c.id == 'fa_cup');
      expect(CupService.isDecided(season, faCup), isTrue);
      // Every round was drawn and every tie played.
      for (final anchor in faCup.anchors) {
        expect(season.rounds[anchor], isNotEmpty);
        expect(season.rounds[anchor].every((f) => f.played), isTrue);
      }
    });

    test('a club knocked out early sees no further cup dates', () {
      final teams = _englishPyramid();
      final season = _englishSeason(teams);
      final user = teams.last.id; // a League Two club, in the prelim
      final faCup = season.cups.firstWhere((c) => c.id == 'fa_cup');
      final first = season.rounds[faCup.anchors.first];
      final tie = first.firstWhere((f) => f.involves(user));
      final isHome = tie.homeTeamId == user;
      tie.record(isHome ? 0 : 1, isHome ? 1 : 0);
      for (final fixture in first) {
        if (!fixture.played) fixture.record(1, 0);
      }
      CupService.progressCup(season);
      expect(CupService.clubIsAlive(season, user, cup: faCup), isFalse);
      expect(CupService.clubExitLabel(season, user, cup: faCup),
          'Out in the Preliminary round');
    });
  });

  test('unknown leagues keep the legacy single cup', () {
    final ids = [for (var i = 0; i < 8; i++) 'stub_$i'];
    final teams = [for (final id in ids) _club(id, 'test_league', 60)];
    final rounds = buildRounds(ids, rng: Random(1));
    final cups = CupService.attachCompetitions(
      rounds: rounds,
      teams: teams,
      leagueId: 'test_league',
      currentYear: 2026,
    );
    expect(cups, hasLength(1));
    expect(cups.single.name, 'National Cup');
    expect(cups.single.roundNames, isEmpty);
  });
}
