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
import 'package:football_manager_sim/core/services/development_service.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';

import '../helpers/test_hive.dart';

/// The save/restore half of the development flow.
///
/// Lives in its own file because it performs an explicit, awaited save: the
/// fire-and-forget auto-saves of a season's worth of matchdays from other
/// tests in a file would still be holding Hive's per-box write queues when
/// this test starts (their completions are scheduled in an already-dead
/// fake-async zone), deadlocking the awaited write. A fresh test file gets a
/// fresh Hive backend.
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

/// A 4-club league (6 league rounds) with a cup (2 more matchdays) attached.
(PlayerDatabase, CareerSession) _scenario() {
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
    currentMatchday: 0,
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

/// The scoreline in FIXTURE orientation: the user's club wins 1-0.
MatchResult _userWin(Fixture fixture, PlayerDatabase db, String userId) {
  final home = fixture.isHomeFor(userId);
  return MatchResult(
    homeTeam: db.teams.firstWhere((t) => t.id == fixture.homeTeamId).name,
    awayTeam: db.teams.firstWhere((t) => t.id == fixture.awayTeamId).name,
    homeGoals: home ? 1 : 0,
    awayGoals: home ? 0 : 1,
    events: const [],
    playerRatings: const [],
    homeMomentum: const [],
    awayMomentum: const [],
    fullTimeCommentary: '',
  );
}

/// Plays every matchday of the calendar (league and cup), surviving the
/// winter break, until the season reaches its post-season state.
Future<void> _playSeason(
  WidgetTester tester,
  ProviderContainer container,
  PlayerDatabase db,
  String userId,
) async {
  for (var step = 0; step < 40; step++) {
    var current = container.read(careerSessionProvider)!;
    if (current.season.isWinterBreak) {
      await _run(tester, container, (ref) => resumeFromWinterBreak(ref));
      current = container.read(careerSessionProvider)!;
    }
    final round = current.season.currentMatchday;
    if (round >= current.season.totalMatchdays) break;

    final fixture = current.season.userFixtureForRound(round, userId);
    if (fixture == null) {
      await _run(tester, container, (ref) => advancePastBye(ref));
      continue;
    }
    await _run(
      tester,
      container,
      (ref) => applyMatchResult(ref, _userWin(fixture, db, userId)),
    );
  }
}

void main() {
  setUpAll(() async {
    storageDir = await initTestHive('fms_growth_persist');
  });

  tearDownAll(() async {
    await disposeTestHive(storageDir);
  });

  testWidgets('season growth replays onto the rebuilt world at restore',
      (tester) async {
    final (dbA, sessionA) = _scenario();
    final user = dbA.teams.first;
    final containerA = ProviderContainer(
      overrides: [
        playerDatabaseProvider.overrideWith((ref) async => dbA),
        careerSessionProvider.overrideWith((ref) => sessionA),
      ],
    );
    addTearDown(containerA.dispose);
    await containerA.read(playerDatabaseProvider.future);

    // A teenage rival one tick away from growing, so the season has
    // something provable to record.
    final rival = dbA.teams[1].squad.first;
    rival.age = 18;
    rival.hiddenAttributes['potential'] = 99;
    rival.hiddenAttributes[DevelopmentService.progressKey] = 0.99;
    final baseOvr = rival.ovr;

    await _playSeason(tester, containerA, dbA, user.id);
    await _run(tester, containerA, (ref) => rollIntoNextSeason(ref));
    final rolled = containerA.read(careerSessionProvider)!;
    final delta = rolled.worldGrowth[rival.id];
    expect(delta, isNotNull);
    expect(delta, greaterThan(0));

    // Flush the matchday auto-saves, then save the career explicitly and
    // wait for the real Hive write to land.
    await settleRealAsync(tester);
    var saved = false;
    await _run(tester, containerA, (ref) {
      saveCareerNow(ref).then((ok) => saved = ok);
    });
    expect(await waitForReal(tester, () => saved), isTrue);

    // A brand-new world: the CSV ratings are fresh and any previous growth
    // must be layered back on from the save.
    final dbB = stubLeagueDatabase(4);
    final containerB = ProviderContainer(
      overrides: [
        playerDatabaseProvider.overrideWith((ref) async => dbB),
      ],
    );
    addTearDown(containerB.dispose);
    await containerB.read(playerDatabaseProvider.future);

    var restored = false;
    await _run(tester, containerB, (ref) {
      tryRestoreCareer(ref).then((ok) => restored = ok);
    });
    expect(await waitForReal(tester, () => restored), isTrue);

    final sessionB = containerB.read(careerSessionProvider);
    expect(sessionB, isNotNull);
    expect(sessionB!.worldGrowth[rival.id], delta);

    final rebuiltRival = dbB.players.firstWhere((p) => p.id == rival.id);
    expect(rebuiltRival.ovr, baseOvr + delta!);
  });
}
