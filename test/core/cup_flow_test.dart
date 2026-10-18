import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/match.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/services/cup_service.dart';
import 'package:football_manager_sim/core/services/save_service.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';

import '../helpers/test_hive.dart';

late Directory storageDir;

/// Gives the tests a real [WidgetRef] for the provider functions.
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

/// A capped season (4 clubs: 6 league rounds) with the cup attached, on the
/// verge of playing the first cup round. Anchors are [2, 5]: the cup rides
/// the calendar between plain league matchdays.
(PlayerDatabase, CareerSession) _cupScenario({int? startMatchday}) {
  final db = stubLeagueDatabase(4);
  final ids = [for (final t in db.teams) t.id];
  final rounds = buildRounds(ids, rng: Random(3));
  final cup = CupService.attachCup(
    rounds: rounds,
    teamIds: ids,
    leagueId: 'test_league',
    currentYear: 2026,
  );
  final season = SeasonState(
    leagueId: 'test_league',
    // Default: sit on the first cup round, the day cups usually get noticed.
    currentMatchday: startMatchday ?? cup!.anchors[0],
    currentYear: 2026,
    isPreSeason: false,
    isWinterBreak: false,
    records: {for (final id in ids) id: LeagueRecord()},
    rounds: rounds,
    cup: cup,
  );
  final user = db.teams.first;
  final session = CareerSession(
    manager: Manager(name: 'Boss', age: 40, nationality: 'Spain',
        teamId: user.id),
    team: user,
    season: season,
  );
  return (db, session);
}

/// The scoreline in FIXTURE orientation, so the recorded goals land on the
/// right side of the tie.
MatchResult _scoreFor(Fixture fixture, PlayerDatabase db,
    {required int homeGoals, required int awayGoals}) {
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

void main() {
  setUpAll(() async {
    // One Hive backend for the file: opened outside the fake-async zone,
    // the way every other flow test does it.
    storageDir = await initTestHive('fms_cup_flow');
  });

  tearDownAll(() async {
    await disposeTestHive(storageDir);
  });

  testWidgets('cup results decide the bracket but never the league table',
      (tester) async {
    final (db, session) = _cupScenario();
    final user = db.teams.first;
    final cup = session.season.cup!;
    final container = await _containerFor(db, session);

    final fixture =
        session.season.userFixtureForRound(cup.anchors[0], user.id)!;
    expect(fixture.competition, 'cup');

    // Win the tie 3-0 (fixture orientation decides which side gets the 3).
    final homeWin = fixture.isHomeFor(user.id);
    await _run(
      tester,
      container,
      (ref) => applyMatchResult(
        ref,
        _scoreFor(fixture, db, homeGoals: homeWin ? 3 : 0,
            awayGoals: homeWin ? 0 : 3),
      ),
    );

    final updated = container.read(careerSessionProvider)!;

    // Both clubs' league records are untouched: a knockout tie is not a
    // points event.
    expect(updated.season.records[fixture.homeTeamId]!.played, 0);
    expect(updated.season.records[fixture.awayTeamId]!.played, 0);
    expect(updated.season.records[fixture.homeTeamId]!.points, 0);
    expect(updated.season.records[fixture.awayTeamId]!.points, 0);

    // The game state still counts the match (appearances, form, career
    // totals) — cups exist, they just do not pay league points.
    expect(updated.team.matchesPlayed, 1);
    expect(updated.userResults, isNotEmpty);

    // And the bracket moved on: the next cup round has the club in it.
    final second = updated.season.rounds[cup.anchors[1]];
    expect(second, isNotEmpty);
    expect(second.any((f) => f.involves(user.id) && !f.played), isTrue);
  });

  testWidgets('losing the tie knocks the club out, and the board says so',
      (tester) async {
    final (db, session) = _cupScenario();
    final user = db.teams.first;
    final cup = session.season.cup!;
    final container = await _containerFor(db, session);

    final fixture =
        session.season.userFixtureForRound(cup.anchors[0], user.id)!;
    final homeWin = fixture.isHomeFor(user.id);
    // Lose 0-3.
    await _run(
      tester,
      container,
      (ref) => applyMatchResult(
        ref,
        _scoreFor(fixture, db, homeGoals: homeWin ? 0 : 3,
            awayGoals: homeWin ? 3 : 0),
      ),
    );

    final updated = container.read(careerSessionProvider)!;

    // The next round is drawn without the eliminated club.
    final second = updated.season.rounds[cup.anchors[1]];
    expect(second, isNotEmpty);
    expect(second.any((f) => f.involves(user.id)), isFalse);
    expect(CupService.clubIsAlive(updated.season, user.id), isFalse);

    // The board's note names the competition and the exit.
    expect(updated.boardNote, contains('Out of the National Cup'));
  });

  testWidgets('a club that wins every tie lifts the cup and stops losing '
      'board patience', (tester) async {
    final (db, session) = _cupScenario(startMatchday: 0);
    final user = db.teams.first;
    final cup = session.season.cup!;
    final container = await _containerFor(db, session);

    // Play the whole calendar: league ties 1-0 (fixture orientation!),
    // cup ties 3-0, and the winter break pause when the season parks there.
    var leagueWins = 0;
    for (var step = 0; step < 40; step++) {
      var current = container.read(careerSessionProvider)!;
      if (current.season.isWinterBreak) {
        await _run(tester, container, (ref) => resumeFromWinterBreak(ref));
        current = container.read(careerSessionProvider)!;
      }
      final round = current.season.currentMatchday;
      if (round >= current.season.totalMatchdays) break;

      final fixture =
          current.season.userFixtureForRound(round, user.id);
      if (fixture == null) {
        await _run(tester, container, (ref) => advancePastBye(ref));
        continue;
      }
      final isCup = fixture.competition == 'cup';
      final homeWin = fixture.isHomeFor(user.id);
      final homeGoals = homeWin ? (isCup ? 3 : 1) : 0;
      final awayGoals = homeWin ? 0 : (isCup ? 3 : 1);
      if (!isCup) leagueWins++;
      await _run(
        tester,
        container,
        (ref) => applyMatchResult(
          ref,
          _scoreFor(fixture, db, homeGoals: homeGoals, awayGoals: awayGoals),
        ),
      );
      final after = container.read(careerSessionProvider)!;
      if (after.trophies.isNotEmpty) break;
    }

    final finalSeason = container.read(careerSessionProvider)!;
    expect(finalSeason.trophies, ['National Cup 2026']);

    // Four league ties come before the final (rounds 0, 1, 3, 4): only they
    // pay points — the two cup ties that complete the run never touch the
    // table.
    expect(leagueWins, 4);
    expect(finalSeason.team.points, 12);
    expect(finalSeason.team.matchesPlayed, 6);
    expect(finalSeason.boardNote, contains('Champions'));
    expect(finalSeason.boardNote, contains('National Cup'));
    expect(
      CupService.cupWinnerOf(finalSeason.season),
      user.id,
    );
    // The season ran to its full merged length: 6 league rounds + 2 cup.
    expect(cup.anchors.length, 2);
    expect(finalSeason.season.currentMatchday,
        greaterThanOrEqualTo(cup.anchors[1] + 1));
  });

  test('a cupped season round-trips through the save with its bracket intact',
      () async {
    final (db, session) = _cupScenario();
    final cup = session.season.cup!;

    // Play round 0 fully through the service directly: one tie drawn.
    final first = session.season.rounds[cup.anchors[0]];
    first[0].record(2, 1);
    first[1].record(0, 0);
    CupService.progressCup(session.season);
    // The user's club (first team) was in fixture[0] or [1]: nothing else
    // needed — persistence must carry the whole bracket either way.

    final save = SaveService();
    await save.saveSeason(session.season);
    final loaded = await save.loadSeason();

    expect(loaded, isNotNull);
    expect(loaded!.cup, isNotNull);
    expect(loaded.cup!.name, cup.name);
    expect(loaded.cup!.anchors, cup.anchors);
    expect(loaded.rounds.length, session.season.rounds.length);
    expect(db.teams.length, 4); // scenario sanity while we are here

    final restoredFirst = loaded.rounds[cup.anchors[0]];
    expect(restoredFirst.length, first.length);
    for (var i = 0; i < first.length; i++) {
      expect(restoredFirst[i].competition, 'cup');
      expect(restoredFirst[i].homeTeamId, first[i].homeTeamId);
      expect(restoredFirst[i].awayGoals, first[i].awayGoals);
      expect(restoredFirst[i].played, isTrue);
    }
    // The progressed second round survived too, still empty/pending.
    expect(loaded.rounds[cup.anchors[1]].length,
        session.season.rounds[cup.anchors[1]].length);
  });
}
