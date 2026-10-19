import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/constants/game_constants.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/match.dart';
import 'package:football_manager_sim/core/models/player.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/tactics.dart';
import 'package:football_manager_sim/core/services/match_simulator_service.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';
import 'package:football_manager_sim/screens/match/match_screen.dart';
import 'package:football_manager_sim/ui/ui.dart';

import '../helpers/test_hive.dart';

CareerSession _session(PlayerDatabase db) {
  final team = db.teams.first;
  return CareerSession(
    manager:
        Manager(name: 'Boss', age: 40, nationality: 'Spain', teamId: team.id),
    team: team,
    season: SeasonState(
      leagueId: team.leagueId,
      currentMatchday: 0,
      currentYear: 2026,
      isPreSeason: false,
      records: {team.id: LeagueRecord(), 'rival_fc': LeagueRecord()},
      rounds: buildRounds([team.id, 'rival_fc'], rng: Random(1)),
    ),
  );
}

/// The XI and bench the match screen will field for this session, computed with
/// the same helpers so a test can name the players it wants to change.
({List<Player> xi, List<Player> bench, Player goalkeeper}) _lineup(
  CareerSession session,
) {
  final lineup = resolveMatchLineup(
    session.team.squad,
    session.tactic.formation,
    session.startXI,
    reservedIds: {
      for (final id in session.benchIds)
        if (id > 0) id,
    },
  );
  final goalkeeper = lineup.goalkeeper!;
  final bench = resolveBenchPlayers(
    session.team.squad,
    {
      goalkeeper.id,
      for (final p in lineup.outfield) p.id,
    },
    session.benchIds,
  );
  return (xi: lineup.outfield, bench: bench, goalkeeper: goalkeeper);
}

bool _userIsHome(CareerSession session) =>
    session.season
        .currentFixtureFor(session.team.id)
        ?.isHomeFor(session.team.id) ??
    true;

/// Rebuilds exactly the simulation the screen creates, so a test can pick a
/// seed that produces the incident it wants to watch.
MatchSimulation _replica(
  CareerSession session,
  PlayerDatabase db,
  Random rng,
) {
  final fixture = session.season.currentFixtureFor(session.team.id);
  final opponent = (fixture == null
          ? null
          : db.teams
              .where((t) => t.id == fixture.opponentOf(session.team.id))
              .firstOrNull) ??
      db.teams.firstWhere(
          (t) => t.leagueId == session.team.leagueId && t.id != session.team.id);
  final userHome = _userIsHome(session);
  final lineup = _lineup(session);
  final oppXi = startingOutfield(opponent.squad, session.tactic.formation);
  final oppGk =
      opponent.squad.firstWhere((p) => p.primaryPosition == 'GK');
  final oppBench = resolveBenchPlayers(
    opponent.squad,
    {
      oppGk.id,
      for (final p in oppXi) p.id,
    },
    const [],
  );
  return MatchSimulation(
    homeGoalkeeper: userHome ? lineup.goalkeeper : oppGk,
    homeSquad: userHome ? lineup.xi : oppXi,
    awayGoalkeeper: userHome ? oppGk : lineup.goalkeeper,
    awaySquad: userHome ? oppXi : lineup.xi,
    homeBench: userHome ? lineup.bench : oppBench,
    awayBench: userHome ? oppBench : lineup.bench,
    homeTactic: userHome ? session.tactic : null,
    awayTactic: userHome ? null : session.tactic,
    manualHome: userHome,
    manualAway: !userHome,
    rng: rng,
  );
}

MatchEvent? _firstPause(CareerSession session, PlayerDatabase db, int seed) {
  final userTeam = _userIsHome(session) ? 'home' : 'away';
  final simulation = _replica(session, db, Random(seed));
  simulation.advanceTo(30);
  return simulation.events
      .where((e) => pausesUserMatch(e, userTeam: userTeam))
      .firstOrNull;
}

void main() {
  late Directory storageDir;

  setUpAll(() async {
    storageDir = await initTestHive('fms_match_substitutions');
  });

  tearDownAll(() async {
    await disposeTestHive(storageDir);
  });

  Future<void> pumpMatch(
    WidgetTester tester,
    CareerSession session,
    PlayerDatabase db, {
    Random? rng,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerDatabaseProvider.overrideWith((ref) async => db),
          careerSessionProvider.overrideWith((ref) => session),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: MatchScreen(rng: rng),
        ),
      ),
    );
    await tester.pump(); // let the database future resolve
  }

  testWidgets('the Subs button pauses the clock and makes a change',
      (tester) async {
    final db = stubPlayerDatabase();
    final session = _session(db);
    await pumpMatch(tester, session, db);

    final lineup = _lineup(session);
    final off = lineup.xi.first;
    final on = lineup.bench.first;

    await tester.tap(find.text('Kick Off'));
    await tester.pump(); // live screen
    await tester.pump(const Duration(milliseconds: 600)); // one ticker tick
    expect(find.text('Subs $maxSubstitutions'), findsOneWidget);

    // Open the change sheet: the clock must stop while it is open.
    await tester.tap(find.text('Subs $maxSubstitutions'));
    await tester.pumpAndSettle();
    expect(find.text('Substitutions'), findsOneWidget);
    expect(find.text('$maxSubstitutions of $maxSubstitutions changes left.'),
        findsOneWidget);

    // Pick both halves of the change, then confirm.
    tester
        .widget<DropdownButtonFormField<Player>>(
            find.byKey(const ValueKey('sub-off')))
        .onChanged!(off);
    await tester.pump();
    tester
        .widget<DropdownButtonFormField<Player>>(
            find.byKey(const ValueKey('sub-on')))
        .onChanged!(on);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sub-confirm')));
    await tester.pump(); // sheet pops and the ticker resumes

    expect(find.text('Subs ${maxSubstitutions - 1}'), findsOneWidget);
    expect(find.text('${on.name} replaces ${off.name}.'), findsOneWidget,
        reason: 'the change belongs in the match feed');

    // Tear the screen down so its ticker does not outlive the test.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an injury stops the clock and opens the change sheet',
      (tester) async {
    final db = stubPlayerDatabase();
    final session = _session(db);

    // Find a seed whose first interruption is an injury, not a red card.
    int? seed;
    MatchEvent? injury;
    for (var candidate = 1; candidate <= 400; candidate++) {
      final event = _firstPause(session, db, candidate);
      if (event != null && event.isInjury) {
        seed = candidate;
        injury = event;
        break;
      }
    }
    expect(injury, isNotNull,
        reason: 'no seeded match injured the manager inside 400 tries');

    await pumpMatch(tester, session, db, rng: Random(seed!));

    await tester.tap(find.text('Kick Off'));
    await tester.pump();

    // Two ticks per match minute at normal speed: pump until the sheet shows.
    final headline = '${injury!.player} is injured';
    for (var i = 0; i < (injury.minute + 6) * 2; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text(headline).evaluate().isNotEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 400)); // sheet animation

    expect(find.text(headline), findsOneWidget);
    expect(find.text('Bring on for ${injury.player}'), findsOneWidget,
        reason: 'the sheet knows exactly who has to come off');

    // The manager's bench is offered as one-tap replacements.
    final on = _lineup(session)
        .bench
        .firstWhere((p) => !p.isInjured && p.primaryPosition != 'GK');
    await tester.tap(find.widgetWithText(ListTile, on.name));
    await tester.pump(); // sheet closes and the match resumes

    expect(find.text('Subs ${maxSubstitutions - 1}'), findsOneWidget);
    expect(find.text('${on.name} replaces ${injury.player}.'), findsOneWidget,
        reason: 'the injury change appears in the feed');

    await tester.pumpWidget(const SizedBox());
  });
}
