import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/data/continental_catalog.dart';
import 'package:football_manager_sim/core/models/continental.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/match.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/services/continental_service.dart';
import 'package:football_manager_sim/core/services/cup_service.dart';
import 'package:football_manager_sim/core/services/save_service.dart';
import 'package:football_manager_sim/core/utils/season_calendar.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';
import 'package:football_manager_sim/screens/calendar/calendar_screen.dart';
import 'package:football_manager_sim/screens/competitions/competitions_screen.dart';
import 'package:football_manager_sim/ui/ui.dart';

import '../helpers/test_hive.dart';

late Directory storageDir;

class _Harness extends ConsumerWidget {
  const _Harness(this.action);

  final void Function(WidgetRef) action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () => action(ref),
      child: const Text('go'),
    );
  }
}

Future<void> _run(
  WidgetTester tester,
  ProviderContainer container,
  void Function(WidgetRef) action,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: _Harness(action))),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pump();
}

Future<ProviderContainer> _containerFor(
  PlayerDatabase db,
  CareerSession session,
) async {
  final container = ProviderContainer(
    overrides: [
      playerDatabaseProvider.overrideWith((ref) async => db),
      careerSessionProvider.overrideWith((ref) => session),
    ],
  );
  addTearDown(container.dispose);
  await container.read(playerDatabaseProvider.future);
  return container;
}

/// A whole top-flight country in one league, with a strict reputation order:
/// club 0 is the strongest, club 119 the weakest.
PlayerDatabase _europeDatabase({int clubs = 40}) {
  final db = stubLeagueDatabase(clubs);
  for (var i = 0; i < db.teams.length; i++) {
    final team = db.teams[i];
    team.leagueId = 'premier_league';
    team.reputation = 100 - i;
  }
  return db;
}

/// A 40-club Premier League with the real cups and a Champions League field,
/// the shape the career builder produces on day one.
(PlayerDatabase, SeasonState, ContinentalState) _continentalSeason({
  int clubs = 40,
}) {
  final db = _europeDatabase(clubs: clubs);
  final ids = [for (final team in db.teams) team.id];
  final rounds = buildRounds(ids, rng: Random(11));
  final request = ContinentalService.buildRequest(
    teams: db.teams,
    leagueId: 'premier_league',
    userId: ids.first,
    year: 2026,
  )!;
  final cups = CupService.attachCompetitions(
    rounds: rounds,
    teams: db.teams,
    leagueId: 'premier_league',
    currentYear: 2026,
    continental: [request],
  );
  final comp = request.toState()!;
  final season = SeasonState(
    leagueId: 'premier_league',
    currentMatchday: comp.leagueAnchors.first,
    currentYear: 2026,
    isPreSeason: false,
    isWinterBreak: false,
    records: {for (final id in ids) id: LeagueRecord()},
    rounds: rounds,
    cups: cups,
    continental: [comp],
  );
  return (db, season, comp);
}

void _playRound(SeasonState season, int anchor, int home, int away) {
  for (final fixture in season.rounds[anchor]) {
    fixture.record(home, away);
  }
}

MatchResult _scoreFor(
  Fixture fixture,
  PlayerDatabase db, {
  required int homeGoals,
  required int awayGoals,
}) {
  final home = db.teams.firstWhere((t) => t.id == fixture.homeTeamId);
  final away = db.teams.firstWhere((t) => t.id == fixture.awayTeamId);
  return MatchResult(
    homeTeam: home.name,
    awayTeam: away.name,
    homeGoals: homeGoals,
    awayGoals: awayGoals,
    events: const [],
    homeMomentum: const [],
    awayMomentum: const [],
    fullTimeCommentary: '',
  );
}

void main() {
  setUpAll(() async {
    storageDir = await initTestHive('fms_continental');
  });

  tearDownAll(() async {
    await disposeTestHive(storageDir);
  });

  group('qualification', () {
    test('the region and the real competition names come from the catalog', () {
      expect(ContinentalCatalog.regionOf('premier_league'),
          ContinentalCatalog.europe);
      expect(
          ContinentalCatalog.regionOf('lpf'), ContinentalCatalog.southAmerica);
      expect(
          ContinentalCatalog.regionOf('mls'), ContinentalCatalog.northAmerica);
      expect(ContinentalCatalog.regionOf('a_league'), ContinentalCatalog.asia);
      expect(ContinentalCatalog.regionOf('test_league'), isNull);
      // South American clubs are filed under the competition labels rather
      // than a league: they belong in the field, not in a career.
      expect(
        ContinentalCatalog.regionOf('libertadores'),
        ContinentalCatalog.southAmerica,
      );
      expect(ContinentalCatalog.qualifiesFrom('libertadores'), isFalse);
      expect(ContinentalCatalog.qualifiesFrom('premier_league'), isTrue);

      final europe = ContinentalCatalog.competitionsOf(
        ContinentalCatalog.europe,
      );
      expect(europe.map((c) => c.id), ['ucl', 'uel', 'uecl']);
      expect(europe.first.name, 'UEFA Champions League');
      expect(europe.first.clubCount, 36);
      expect(europe.first.leagueGames, 8);
      expect(europe.last.leagueGames, 6);
    });

    test('season one is seeded by reputation: top 36 in, 110th out', () {
      final db = _europeDatabase(clubs: 120);
      final ids = [for (final team in db.teams) team.id];

      final top = ContinentalService.buildRequest(
        teams: db.teams,
        leagueId: 'premier_league',
        userId: ids[0],
        year: 2026,
      );
      expect(top, isNotNull);
      expect(top!.id, 'ucl');
      expect(top.clubIds, hasLength(36));
      expect(top.clubIds, contains(ids[0]));

      final europa = ContinentalService.buildRequest(
        teams: db.teams,
        leagueId: 'premier_league',
        userId: ids[39],
        year: 2026,
      );
      expect(europa, isNotNull);
      expect(europa!.id, 'uel');

      final conference = ContinentalService.buildRequest(
        teams: db.teams,
        leagueId: 'premier_league',
        userId: ids[79],
        year: 2026,
      );
      expect(conference, isNotNull);
      expect(conference!.id, 'uecl');

      final out = ContinentalService.buildRequest(
        teams: db.teams,
        leagueId: 'premier_league',
        userId: ids[110],
        year: 2026,
      );
      expect(out, isNull);
    });

    test('last season decides the entry, not this season\'s reputation', () {
      final db = _europeDatabase(clubs: 120);
      final weak = db.teams[110]; // a small club, by reputation
      ContinentalRequest? requestFor(int position) =>
          ContinentalService.buildRequest(
            teams: db.teams,
            leagueId: 'premier_league',
            userId: weak.id,
            year: 2027,
            previousPosition: position,
            previousLeagueId: 'premier_league',
          );

      final champions = requestFor(3);
      expect(champions, isNotNull);
      expect(champions!.id, 'ucl');
      expect(champions.clubIds, contains(weak.id));

      expect(requestFor(5)!.id, 'uel');
      expect(requestFor(7)!.id, 'uecl');
      expect(requestFor(8), isNull);

      // A promoted club's old position belongs to another division, so it is
      // back to reputation (and out of the 108 European places).
      expect(
        ContinentalService.buildRequest(
          teams: db.teams,
          leagueId: 'premier_league',
          userId: weak.id,
          year: 2027,
          previousPosition: 1,
          previousLeagueId: 'efl_championship',
        ),
        isNull,
      );
    });

    test('only a top flight qualifies', () {
      final db = _europeDatabase(clubs: 120);
      // Put the test club in the Championship: the country catalog knows it,
      // but it is not the top league.
      db.teams[0].leagueId = 'efl_championship';
      final request = ContinentalService.buildRequest(
        teams: db.teams,
        leagueId: 'efl_championship',
        userId: db.teams[0].id,
        year: 2026,
      );
      expect(request, isNull);

      // A league outside the catalog gets no continental football at all.
      db.teams[1].leagueId = 'test_league';
      expect(
        ContinentalService.buildRequest(
          teams: db.teams,
          leagueId: 'test_league',
          userId: db.teams[1].id,
          year: 2026,
        ),
        isNull,
      );
    });
  });

  group('league phase', () {
    test('the draw gives every club one game per matchday, no repeats', () {
      final (_, season, comp) = _continentalSeason();
      expect(comp.clubIds, hasLength(36));
      expect(comp.leagueAnchors, hasLength(8));
      expect(comp.knockoutAnchors, hasLength(9));

      final opponents = <String, Set<String>>{
        for (final id in comp.clubIds) id: <String>{},
      };
      for (final anchor in comp.leagueAnchors) {
        final round = season.rounds[anchor];
        expect(round, hasLength(18));
        final seen = <String>{};
        for (final fixture in round) {
          expect(fixture.competition, 'ucl');
          expect(seen.add(fixture.homeTeamId), isTrue);
          expect(seen.add(fixture.awayTeamId), isTrue);
          expect(
            opponents[fixture.homeTeamId]!.add(fixture.awayTeamId),
            isTrue,
            reason: 'the draw repeated a pairing',
          );
          expect(
            opponents[fixture.awayTeamId]!.add(fixture.homeTeamId),
            isTrue,
            reason: 'the draw repeated a pairing',
          );
        }
        expect(seen, hasLength(36));
      }
      for (final entry in opponents.entries) {
        expect(entry.value, hasLength(8));
      }
    });

    test('the table counts league-phase points only', () {
      final (_, season, comp) = _continentalSeason();
      _playRound(season, comp.leagueAnchors[0], 3, 0);
      final table = ContinentalService.tableOf(season, comp);
      expect(table, hasLength(36));
      expect(table.where((row) => row.record.played == 1), hasLength(36));
      expect(table.first.record.points, 3);
      expect(table.first.record.goalDifference, 3);

      // League rounds never touch the continental table, and the continental
      // rounds never touch the league table.
      expect(season.records.values.every((r) => r.played == 0), isTrue);
    });

    test('the knockout dates are midweeks and never clash with a cup', () {
      final (_, season, comp) = _continentalSeason();
      final dates = <DateTime>{
        for (final cup in season.cups)
          for (final anchor in cup.anchors)
            SeasonCalendar.dateOf(season, anchor),
      };
      for (final anchor in [
        ...comp.leagueAnchors,
        ...comp.knockoutAnchors,
      ]) {
        final date = SeasonCalendar.dateOf(season, anchor);
        expect(date.weekday, DateTime.wednesday);
        expect(
          dates.add(date),
          isTrue,
          reason: 'two competitions share $date',
        );
      }
    });
  });

  group('knockouts', () {
    test('the league phase seeds a play-off, then a sixteen-club bracket', () {
      final (_, season, comp) = _continentalSeason();
      // Every league-phase home side wins 2-1, so the table has a strict
      // order by home games and the seeds are stable.
      for (final anchor in comp.leagueAnchors) {
        _playRound(season, anchor, 2, 1);
      }
      expect(season.rounds[comp.knockoutAnchors[0]], isEmpty);
      ContinentalService.progress(season);

      final leg1 = season.rounds[comp.knockoutAnchors[0]];
      final leg2 = season.rounds[comp.knockoutAnchors[1]];
      expect(leg1, hasLength(8));
      expect(leg2, hasLength(8));
      expect(season.rounds[comp.knockoutAnchors[2]], isEmpty);

      final table = ContinentalService.tableOf(season, comp);
      final expected = {
        for (var i = 8; i < 24; i++) table[i].teamId,
      };
      final actual = {
        for (final fixture in leg1) ...[
          fixture.homeTeamId,
          fixture.awayTeamId,
        ],
      };
      expect(actual, expected);
      // The better seed (9th) hosts the second leg.
      final first = leg1.first;
      expect(first.homeTeamId, table[23].teamId);
      expect(first.awayTeamId, table[8].teamId);
      final returnLeg = leg2.firstWhere(
        (f) =>
            f.homeTeamId == first.awayTeamId &&
            f.awayTeamId == first.homeTeamId,
      );
      expect(returnLeg.homeTeamId, table[8].teamId);

      // One tie is an aggregate comeback, the rest hold home advantage.
      first.record(2, 0);
      returnLeg.record(3, 0); // better seed wins the tie 3-2 on aggregate
      for (var i = 1; i < leg1.length; i++) {
        leg1[i].record(1, 0);
        leg2[i].record(1, 0);
      }
      expect(
        ContinentalService.tieWinner(season, comp, first),
        table[8].teamId,
      );

      ContinentalService.progress(season);
      final r16 = season.rounds[comp.knockoutAnchors[2]];
      expect(r16, hasLength(8));
      final sixteen = {
        for (final fixture in r16) ...[
          fixture.homeTeamId,
          fixture.awayTeamId,
        ],
      };
      expect(sixteen, hasLength(16));
      for (var i = 0; i < 8; i++) {
        expect(sixteen, contains(table[i].teamId));
      }
      expect(ContinentalService.winnerOf(season, comp), isNull);
    });

    test('the bracket runs from the play-off to a single-leg final', () {
      final (_, season, comp) = _continentalSeason();
      for (final anchor in comp.leagueAnchors) {
        _playRound(season, anchor, 2, 1);
      }
      ContinentalService.progress(season);

      // Complete each two-legged stage: every home side wins its leg 1-0, so
      // the aggregate is level and the seeded shootout decides each tie.
      for (var stage = 0; stage < 4; stage++) {
        _playRound(season, comp.knockoutAnchors[stage * 2], 1, 0);
        _playRound(season, comp.knockoutAnchors[stage * 2 + 1], 1, 0);
        ContinentalService.progress(season);
        expect(
          season.rounds[comp.knockoutAnchors[(stage + 1) * 2]],
          isNotEmpty,
        );
      }

      final finalRound = season.rounds[comp.knockoutAnchors[8]];
      expect(finalRound, hasLength(1));
      expect(season.rounds[comp.knockoutAnchors[7]], hasLength(2));
      final finalTie = finalRound.single;
      finalTie.record(2, 1);
      final winner = ContinentalService.winnerOf(season, comp);
      expect(winner, finalTie.homeTeamId);
      final loser = finalTie.awayTeamId;
      expect(
        ContinentalService.clubExitLabel(season, comp, loser),
        'Runners-up',
      );
      expect(
        ContinentalService.clubExitLabel(season, comp, winner!),
        'Winners',
      );
      expect(ContinentalService.stageLabel(2, 1), 'Quarter-finals · 1st leg');
      expect(ContinentalService.stageLabel(4, 1), 'Final');
    });

    test('a leg note follows the aggregate and the tie seed', () {
      final (_, season, comp) = _continentalSeason();
      for (final anchor in comp.leagueAnchors) {
        _playRound(season, anchor, 2, 1);
      }
      ContinentalService.progress(season);

      final leg1 = season.rounds[comp.knockoutAnchors[0]].first;
      final leg2 = season.rounds[comp.knockoutAnchors[1]].firstWhere(
        (f) =>
            f.homeTeamId == leg1.awayTeamId && f.awayTeamId == leg1.homeTeamId,
      );
      final firstNote = ContinentalService.legNote(
        season: season,
        comp: comp,
        fixture: leg1,
        teamId: leg1.homeTeamId,
        homeGoals: 2,
        awayGoals: 0,
      );
      expect(firstNote, isNotNull);
      expect(firstNote!.advanced, isFalse);
      expect(firstNote.text, contains('First leg'));

      leg1.record(2, 0);
      final secondNote = ContinentalService.legNote(
        season: season,
        comp: comp,
        fixture: leg2,
        teamId: leg2.awayTeamId,
        homeGoals: 1,
        awayGoals: 2,
      );
      // The club that was away in the second leg wins 4-1 on aggregate.
      expect(secondNote, isNotNull);
      expect(secondNote!.advanced, isTrue);
      expect(secondNote.text, contains('Aggregate'));
    });
  });

  test('the competition round-trips through the save', () async {
    final (_, season, comp) = _continentalSeason();
    final save = SaveService();
    await save.saveSeason(season);
    final loaded = await save.loadSeason();

    expect(loaded, isNotNull);
    expect(loaded!.continental, hasLength(1));
    final after = loaded.continental.single;
    expect(after.id, comp.id);
    expect(after.name, comp.name);
    expect(after.region, comp.region);
    expect(after.clubIds, comp.clubIds);
    expect(after.leagueRounds, comp.leagueRounds);
    expect(after.leagueAnchors, comp.leagueAnchors);
    expect(after.knockoutAnchors, comp.knockoutAnchors);
    expect(loaded.rounds.length, season.rounds.length);
    expect(loaded.rounds[comp.leagueAnchors.first], hasLength(18));
    expect(
      loaded.rounds[comp.leagueAnchors.first].first.competition,
      comp.id,
    );
  });

  testWidgets('a continental night pays the club and never the league table',
      (tester) async {
    final (db, season, comp) = _continentalSeason();
    final user = db.teams.first;
    final session = CareerSession(
      manager: Manager(
        name: 'Boss',
        age: 40,
        nationality: 'England',
        teamId: user.id,
      ),
      team: user,
      season: season,
    );
    final container = await _containerFor(db, session);

    final fixture =
        season.userFixtureForRound(season.currentMatchday, user.id)!;
    expect(fixture.competition, 'ucl');
    final revenueBefore = user.revenue;

    await _run(
      tester,
      container,
      (ref) => applyMatchResult(
        ref,
        _scoreFor(fixture, db, homeGoals: 2, awayGoals: 0),
      ),
    );

    final updated = container.read(careerSessionProvider)!;
    final updatedComp = updated.season.continental.single;
    expect(updated.season.records[user.id]!.played, 0);
    expect(updated.season.records[user.id]!.points, 0);
    expect(updatedComp.rewardedRounds, contains(comp.leagueAnchors.first));
    expect(updated.team.revenue, greaterThan(revenueBefore));
    final table = ContinentalService.tableOf(updated.season, updatedComp);
    expect(
      table.firstWhere((row) => row.teamId == user.id).record.played,
      1,
    );
  });

  testWidgets('the Competitions screen shows the continental route and table',
      (tester) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(360, 2400);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
    addTearDown(() {
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });

    final (db, season, comp) = _continentalSeason();
    final user = db.teams.first;
    final session = CareerSession(
      manager: Manager(
        name: 'Boss',
        age: 40,
        nationality: 'England',
        teamId: user.id,
      ),
      team: user,
      season: season,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerDatabaseProvider.overrideWith((ref) async => db),
          careerSessionProvider.overrideWith((ref) => session),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const CompetitionsScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('UEFA Champions League'), findsOneWidget);
    expect(find.text('YOUR ROUTE'), findsWidgets);
    expect(find.text('League phase table'), findsOneWidget);
    expect(find.text('KNOCKOUTS'), findsOneWidget);
    expect(find.textContaining('League phase —'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new career draws the continental competition at kick-off',
      (tester) async {
    final db = _europeDatabase();
    final container = ProviderContainer(
      overrides: [
        playerDatabaseProvider.overrideWith((ref) async => db),
      ],
    );
    addTearDown(container.dispose);
    await container.read(playerDatabaseProvider.future);

    final user = db.teams.first;
    await _run(
      tester,
      container,
      (ref) => startNewCareer(
        ref,
        manager: Manager(
          name: 'Boss',
          age: 40,
          nationality: 'England',
          teamId: user.id,
        ),
        team: user,
      ),
    );

    final session = container.read(careerSessionProvider);
    expect(session, isNotNull);
    final comp = session!.season.continental.single;
    expect(comp.id, 'ucl');
    expect(comp.clubIds, contains(user.id));
    expect(comp.leagueAnchors, hasLength(8));
    expect(comp.knockoutAnchors, hasLength(9));
    expect(
      session.season.rounds[comp.leagueAnchors.first],
      hasLength(18),
    );
    expect(
      session.season.rounds[comp.knockoutAnchors.first],
      isEmpty,
    );
  });

  testWidgets('a drawn continental night is not a shootout', (tester) async {
    final (db, season, comp) = _continentalSeason();
    final user = db.teams.first;
    final fixture = season.userFixtureForRound(
      comp.leagueAnchors.first,
      user.id,
    )!;
    fixture.record(1, 1);
    final session = CareerSession(
      manager: Manager(
        name: 'Boss',
        age: 40,
        nationality: 'England',
        teamId: user.id,
      ),
      team: user,
      season: season,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerDatabaseProvider.overrideWith((ref) async => db),
          careerSessionProvider.overrideWith((ref) => session),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const CalendarScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('League phase'), findsWidgets);
    expect(find.textContaining('pens'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unqualified club is told how to get in', (tester) async {
    final db = _europeDatabase(clubs: 40);
    final ids = [for (final team in db.teams) team.id];
    final rounds = buildRounds(ids, rng: Random(3));
    final leagueClubs = db.teams.take(20).toList();
    final season = SeasonState(
      leagueId: 'premier_league',
      currentMatchday: 0,
      currentYear: 2026,
      isPreSeason: false,
      isWinterBreak: false,
      records: {for (final team in leagueClubs) team.id: LeagueRecord()},
      rounds: rounds,
      cups: CupService.attachCompetitions(
        rounds: rounds,
        teams: leagueClubs,
        leagueId: 'premier_league',
        currentYear: 2026,
      ),
    );
    final team = leagueClubs.last;
    final session = CareerSession(
      manager: Manager(
        name: 'Boss',
        age: 40,
        nationality: 'England',
        teamId: team.id,
      ),
      team: team,
      season: season,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerDatabaseProvider.overrideWith((ref) async => db),
          careerSessionProvider.overrideWith((ref) => session),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const CompetitionsScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('CONTINENTAL FOOTBALL'), findsOneWidget);
    expect(find.text('Not qualified this season'), findsOneWidget);
    expect(find.textContaining('UEFA Champions League'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
