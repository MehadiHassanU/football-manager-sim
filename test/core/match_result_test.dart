import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/constants/game_constants.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/match.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/sponsorship.dart';
import 'package:football_manager_sim/core/models/team.dart';
import 'package:football_manager_sim/core/services/financial_service.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';
import 'package:football_manager_sim/screens/career/career_dashboard_screen.dart';

import '../helpers/test_hive.dart';

/// Applies [result] when tapped, which is how the tests get hold of a real
/// [WidgetRef] for the provider functions.
class _ApplyResult extends ConsumerWidget {
  const _ApplyResult(this.result);

  final MatchResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () => applyMatchResult(ref, result),
      child: const Text('apply'),
    );
  }
}

MatchResult _scoreline(
  Fixture fixture,
  Team home,
  Team away, {
  required int homeGoals,
  required int awayGoals,
}) =>
    MatchResult(
      homeTeam: home.name,
      awayTeam: away.name,
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      events: const [],
      homeMomentum: const [],
      awayMomentum: const [],
      fullTimeCommentary: '',
    );

CareerSession _sessionFor(PlayerDatabase db, int clubCount, int startRound) {
  final ids = [for (final t in db.teams) t.id];
  final userTeam = db.teams.first;
  return CareerSession(
    manager: Manager(
      name: 'Boss',
      age: 40,
      nationality: 'Spain',
      teamId: userTeam.id,
    ),
    team: userTeam,
    season: SeasonState(
      leagueId: 'test_league',
      currentMatchday: startRound,
      currentYear: 2026,
      isPreSeason: false,
      records: {for (final id in ids) id: LeagueRecord()},
      rounds: buildRounds(ids, rng: Random(1)),
    ),
  );
}

ProviderContainer _containerFor(PlayerDatabase db, CareerSession session) {
  final container = ProviderContainer(
    overrides: [
      playerDatabaseProvider.overrideWith((ref) async => db),
      careerSessionProvider.overrideWith((ref) => session),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  late Directory storageDir;
  const clubCount = 8;

  setUpAll(() async {
    storageDir = await initTestHive('fms_match_result');
  });

  tearDownAll(() async {
    await disposeTestHive(storageDir);
  });

  testWidgets('a home win settles the matchday books exactly once',
      (tester) async {
    final db = stubLeagueDatabase(clubCount);
    final ids = [for (final t in db.teams) t.id];
    final rounds = buildRounds(ids, rng: Random(1));
    final homeRound = [
      for (var r = 0; r < rounds.length; r++)
        if (rounds[r].any((f) => f.homeTeamId == ids.first)) r,
    ].first;

    final session = _sessionFor(db, clubCount, homeRound);
    final container = _containerFor(db, session);
    final fixture = session.season.currentFixtureFor(session.team.id)!;
    expect(fixture.isHomeFor(session.team.id), isTrue);

    final home = db.teams.firstWhere((t) => t.id == fixture.homeTeamId);
    final away = db.teams.firstWhere((t) => t.id == fixture.awayTeamId);
    final budgetBefore = session.team.budget;
    final transferBefore = session.team.transferBudget;
    final revenueBefore = session.team.revenue;
    final finance = FinancialService();
    final gate = finance.estimateGateReceipts(session.team);
    final broadcast = finance.broadcastPerMatch(session.team.reputation);
    final wages =
        finance.calculateWageBill(session.team) + session.team.loanedOutWages;
    // No kit deals on a session built by hand, so income is gate + broadcast.
    final net = gate + broadcast - wages;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: _ApplyResult(
              _scoreline(fixture, home, away, homeGoals: 2, awayGoals: 1),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apply'));
    await tester.pump();

    expect(session.team.budget, budgetBefore + net.round(),
        reason: 'a home match should settle exactly once');
    expect(session.team.revenue, revenueBefore + gate + broadcast,
        reason: 'gate and broadcast money are season revenue');
    expect(session.team.transferBudget,
        closeTo(transferBefore + net * kTransferBudgetRelease, 0.01),
        reason: 'the board frees its share of the net cash');

    final after = container.read(careerSessionProvider)!;
    expect(after.season.currentMatchday, homeRound + 1);
    expect(after.season.records[session.team.id]!.played, 1);
    expect(after.season.records[session.team.id]!.won, 1);
    expect(after.season.records[fixture.awayTeamId]!.lost, 1);
  });

  testWidgets('an away win pays the away week and follows the fixture',
      (tester) async {
    final db = stubLeagueDatabase(clubCount);
    final ids = [for (final t in db.teams) t.id];
    final rounds = buildRounds(ids, rng: Random(1));
    final awayRound = [
      for (var r = 0; r < rounds.length; r++)
        if (rounds[r].any((f) => f.awayTeamId == ids.first)) r,
    ].first;

    final session = _sessionFor(db, clubCount, awayRound);
    final container = _containerFor(db, session);
    final fixture = session.season.currentFixtureFor(session.team.id)!;
    expect(fixture.isHomeFor(session.team.id), isFalse);

    final home = db.teams.firstWhere((t) => t.id == fixture.homeTeamId);
    final away = db.teams.firstWhere((t) => t.id == fixture.awayTeamId);
    final budgetBefore = session.team.budget;
    final revenueBefore = session.team.revenue;
    final finance = FinancialService();
    final broadcast = finance.broadcastPerMatch(session.team.reputation);
    final wages =
        finance.calculateWageBill(session.team) + session.team.loanedOutWages;
    final net = broadcast - wages;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: _ApplyResult(
              _scoreline(fixture, home, away, homeGoals: 0, awayGoals: 2),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apply'));
    await tester.pump();

    expect(session.team.budget, budgetBefore + net.round(),
        reason: 'an away week banks broadcast money but no gate receipts');
    expect(session.team.revenue, revenueBefore + broadcast,
        reason: 'gate receipts must only be credited at home');

    final after = container.read(careerSessionProvider)!;
    // The away side wins 2-0, so the points must follow the fixture. The old
    // call site hardcoded userIsHome: true and would have booked a 0-2 defeat.
    expect(after.season.records[session.team.id]!.won, 1);
    expect(after.season.records[session.team.id]!.goalsFor, 2);
    expect(after.season.records[fixture.homeTeamId]!.lost, 1);
    expect(after.season.records[fixture.homeTeamId]!.goalsAgainst, 2);
  });

  testWidgets('every other club in the round also plays', (tester) async {
    final db = stubLeagueDatabase(clubCount);
    final session = _sessionFor(db, clubCount, 0);
    final container = _containerFor(db, session);
    final fixture = session.season.currentFixtureFor(session.team.id)!;
    final userId = session.team.id;

    final home = db.teams.firstWhere((t) => t.id == fixture.homeTeamId);
    final away = db.teams.firstWhere((t) => t.id == fixture.awayTeamId);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: _ApplyResult(
              _scoreline(fixture, home, away, homeGoals: 2, awayGoals: 1),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apply'));
    await tester.pump();

    final after = container.read(careerSessionProvider)!;
    // An eight-club round is four fixtures: every club plays exactly once.
    for (final entry in after.season.records.entries) {
      expect(entry.value.played, 1, reason: entry.key);
    }
    expect(after.season.records.keys.length, clubCount);
    expect(after.season.records.containsKey(userId), isTrue);
    expect(after.team.leaguePosition, after.season.positionOf(userId));
  });

  testWidgets('a bye advances the round and still plays the rivals',
      (tester) async {
    // Seven clubs means one of them sits out each round.
    final db = stubLeagueDatabase(7);
    final ids = [for (final t in db.teams) t.id];
    final rounds = buildRounds(ids, rng: Random(1));
    final byeRound = [
      for (var r = 0; r < rounds.length; r++)
        if (!rounds[r].any((f) => f.involves(ids.first))) r,
    ].first;

    final session = _sessionFor(db, 7, byeRound);
    final container = _containerFor(db, session);
    final userId = session.team.id;

    expect(session.season.isByeRound(userId), isTrue);

    // A bye week still settles books: the kit pays its weekly instalment and
    // the wage bill goes out; no match means no gate and no broadcast money.
    final budgetBefore = session.team.budget;
    final transferBefore = session.team.transferBudget;
    session.team.squad.first.weeklyWage = 5000;
    session.sponsorships.add(Sponsorship(
      slot: SponsorSlot.front,
      brand: 'Volt Energy',
      annualValue: 5200000,
      startYear: session.season.currentYear,
      durationYears: 2,
    ));
    const expectedNet = 5200000 / 52 - 5000;

    // Driven through the real dashboard button rather than the provider.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CareerDashboardScreen()),
      ),
    );
    expect(find.text('Skip matchday'), findsOneWidget);
    await tester.tap(find.text('Skip matchday'));
    await tester.pump();

    final after = container.read(careerSessionProvider)!;
    expect(after.season.currentMatchday, byeRound + 1);
    expect(after.season.records[userId]!.played, 0,
        reason: 'a bye is not a match');
    for (final id in ids.where((id) => id != userId)) {
      expect(after.season.records[id]!.played, greaterThan(0), reason: id);
    }
    expect(after.team.budget, budgetBefore + expectedNet.round(),
        reason: 'a bye week still banks kit money and pays wages');
    expect(after.team.transferBudget,
        closeTo(transferBefore + expectedNet * kTransferBudgetRelease, 0.01));
  });

  testWidgets('goals and assists fold into the squad season totals',
      (tester) async {
    final db = stubLeagueDatabase(clubCount);
    final ids = [for (final t in db.teams) t.id];
    final rounds = buildRounds(ids, rng: Random(1));
    final homeRound = [
      for (var r = 0; r < rounds.length; r++)
        if (rounds[r].any((f) => f.homeTeamId == ids.first)) r,
    ].first;

    final session = _sessionFor(db, clubCount, homeRound);
    final container = _containerFor(db, session);
    final fixture = session.season.currentFixtureFor(session.team.id)!;
    expect(fixture.isHomeFor(session.team.id), isTrue);

    final striker =
        session.team.squad.firstWhere((p) => p.primaryPosition == 'ST');
    expect(striker.goals, 0);
    expect(striker.assists, 0);

    final home = db.teams.firstWhere((t) => t.id == fixture.homeTeamId);
    final away = db.teams.firstWhere((t) => t.id == fixture.awayTeamId);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: _ApplyResult(MatchResult(
              homeTeam: home.name,
              awayTeam: away.name,
              homeGoals: 2,
              awayGoals: 1,
              events: const [],
              homeRatings: [
                PlayerRating(
                  playerName: striker.name,
                  playerId: striker.id,
                  position: 'ST',
                  rating: 7.6,
                  goals: 2,
                  assists: 1,
                  minutes: 90,
                  started: true,
                ),
              ],
              homeMomentum: const [],
              awayMomentum: const [],
              fullTimeCommentary: '',
            )),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apply'));
    await tester.pump();

    expect(striker.goals, 2, reason: 'both goals must be credited');
    expect(striker.assists, 1);
    expect(striker.gamesPlayed, 1);
    // The decimal rating reaches the squad without being rounded away.
    expect(striker.matchRating, 7.6);
  });

  testWidgets('a league result folds both sides into the season scorers',
      (tester) async {
    final db = stubLeagueDatabase(clubCount);
    final ids = [for (final t in db.teams) t.id];
    final rounds = buildRounds(ids, rng: Random(1));
    final homeRound = [
      for (var r = 0; r < rounds.length; r++)
        if (rounds[r].any((f) => f.homeTeamId == ids.first)) r,
    ].first;

    final session = _sessionFor(db, clubCount, homeRound);
    final container = _containerFor(db, session);
    final fixture = session.season.currentFixtureFor(session.team.id)!;
    expect(fixture.isHomeFor(session.team.id), isTrue);

    final userStriker =
        session.team.squad.firstWhere((p) => p.primaryPosition == 'ST');
    final rival = db.teams.firstWhere((t) => t.id == fixture.awayTeamId);
    final rivalStriker =
        rival.squad.firstWhere((p) => p.primaryPosition == 'ST');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: _ApplyResult(MatchResult(
              homeTeam: db.teams.first.name,
              awayTeam: rival.name,
              homeGoals: 2,
              awayGoals: 1,
              events: const [],
              homeRatings: [
                PlayerRating(
                  playerName: userStriker.name,
                  playerId: userStriker.id,
                  position: 'ST',
                  rating: 8.1,
                  goals: 2,
                  assists: 0,
                  minutes: 90,
                  started: true,
                ),
              ],
              awayRatings: [
                PlayerRating(
                  playerName: rivalStriker.name,
                  playerId: rivalStriker.id,
                  position: 'ST',
                  rating: 7.0,
                  goals: 1,
                  assists: 0,
                  minutes: 90,
                  started: true,
                ),
              ],
              homeMomentum: const [],
              awayMomentum: const [],
              fullTimeCommentary: '',
            )),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apply'));
    await tester.pump();

    final after = container.read(careerSessionProvider)!;
    final mine = after.season.scorers[userStriker.id];
    final theirs = after.season.scorers[rivalStriker.id];
    expect(mine, isNotNull, reason: 'the user side belongs on the list too');
    expect(mine!.goals, 2);
    expect(mine.clubId, fixture.homeTeamId);
    expect(theirs, isNotNull, reason: 'rival scorers are attributed as well');
    expect(theirs!.goals, 1);
    expect(theirs.clubId, fixture.awayTeamId);
  });
}
