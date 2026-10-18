import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/match.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/youth_player.dart';
import 'package:football_manager_sim/core/services/cup_service.dart';
import 'package:football_manager_sim/core/services/development_service.dart';
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

/// A 4-club league (6 league rounds) with a cup (2 more matchdays) attached.
(PlayerDatabase, CareerSession) _scenario({int startMatchday = 0}) {
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
    currentMatchday: startMatchday,
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
    storageDir = await initTestHive('fms_growth_flow');
  });

  tearDownAll(() async {
    await disposeTestHive(storageDir);
  });

  testWidgets('a played matchday is also a training week', (tester) async {
    final (db, session) = _scenario();
    final user = db.teams.first;
    final container = await _containerFor(db, session);

    // A primed academy-age starter: one tick of progress away from a point.
    final prospect = user.squad.first;
    prospect.age = 19;
    prospect.hiddenAttributes['potential'] = 90;
    prospect.hiddenAttributes[DevelopmentService.progressKey] = 0.99;
    final pacBefore = prospect.pac;

    final fixture = session.season.userFixtureForRound(0, user.id)!;
    await _run(
      tester,
      container,
      (ref) => applyMatchResult(ref, _userWin(fixture, db, user.id)),
    );

    final updated = container.read(careerSessionProvider)!;
    expect(prospect.ovr, 63); // 62 -> 63 on the week's progress tipping over
    expect(prospect.pac, pacBefore + 1); // no focus set: cores move together
    expect(
      prospect.hiddenAttributes[DevelopmentService.progressKey],
      closeTo(0.0575, 1e-9), // 0.99 + (0.15 chance * 0.45 bench) - 1.0
    );
    // The rest of the squad trained too, even without minutes.
    final others = updated.team.squad.where((p) => p.id != prospect.id);
    expect(
      others.any(
        (p) =>
            ((p.hiddenAttributes[DevelopmentService.progressKey] as num?)
                    ?.toDouble() ??
                0) >
            0,
      ),
      isTrue,
    );
  });

  testWidgets('a bye week is still a training week', (tester) async {
    final db = stubLeagueDatabase(3); // odd league: someone sits out
    final ids = [for (final t in db.teams) t.id];
    final rounds = buildRounds(ids, rng: Random(3));
    final user = db.teams.first;

    var byeRound = -1;
    for (var r = 0; r < rounds.length; r++) {
      if (rounds[r].every((f) => !f.involves(user.id))) {
        byeRound = r;
        break;
      }
    }
    expect(byeRound, greaterThanOrEqualTo(0));

    final season = SeasonState(
      leagueId: 'test_league',
      currentMatchday: byeRound,
      currentYear: 2026,
      isPreSeason: false,
      isWinterBreak: false,
      records: {for (final id in ids) id: LeagueRecord()},
      rounds: rounds,
    );
    final session = CareerSession(
      manager: Manager(name: 'Boss', age: 40, nationality: 'Spain',
          teamId: user.id),
      team: user,
      season: season,
    );

    final container = await _containerFor(db, session);
    await _run(tester, container, (ref) => advancePastBye(ref));

    final updated = container.read(careerSessionProvider)!;
    expect(updated.season.currentMatchday, byeRound + 1);
    final trained = updated.team.squad.first;
    final progress =
        (trained.hiddenAttributes[DevelopmentService.progressKey] as num?)
            ?.toDouble() ??
        0;
    expect(progress, greaterThan(0));
  });

  testWidgets('the season boundary ages the world and records rival growth',
      (tester) async {
    final (db, session) = _scenario();
    final user = db.teams.first;
    final container = await _containerFor(db, session);

    // A teenage rival one tick away from growing, so the rollover has
    // something provable to record.
    final rival = db.teams[1].squad.first;
    rival.age = 18;
    rival.hiddenAttributes['potential'] = 99;
    rival.hiddenAttributes[DevelopmentService.progressKey] = 0.99;
    final rivalStartOvr = rival.ovr;

    // An academy prospect on the same clock.
    final academy = YouthPlayer(
      name: 'Academy Star',
      age: 17,
      potential: 85,
      currentStats: 60,
      position: 'ST',
      nationality: 'Spain',
      random: Random(4),
    );
    session.youthPlayers.add(academy);

    await _playSeason(tester, container, db, user.id);
    expect(container.read(careerSessionProvider)!.season.isPostSeason, isTrue);

    await _run(tester, container, (ref) => rollIntoNextSeason(ref));
    final next = container.read(careerSessionProvider)!;

    // The whole world rolled a year: squad, academy and rivals.
    expect(next.team.squad.every((p) => p.age == 25), isTrue);
    expect(next.youthPlayers.first.age, 18);
    expect(rival.age, 19);

    // The rival's growth is recorded for replay, not just applied once.
    final delta = next.worldGrowth[rival.id];
    expect(delta, isNotNull);
    expect(delta, greaterThan(0));
    expect(rival.ovr, rivalStartOvr + delta!);
    // The academy prospect trained all season (no assert on the exact
    // number: the weekly roll decides, the age clock does not).
    expect(academy.currentStats, greaterThanOrEqualTo(60));
  });
}
