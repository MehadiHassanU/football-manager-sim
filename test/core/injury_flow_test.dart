import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/match.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/services/development_service.dart';
import 'package:football_manager_sim/core/services/injury_service.dart';
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

/// A 4-club league (6 league rounds), ready to play from matchday 0.
(PlayerDatabase, CareerSession) _scenario() {
  final db = stubLeagueDatabase(4);
  final ids = [for (final t in db.teams) t.id];
  final rounds = buildRounds(ids, rng: Random(3));
  final season = SeasonState(
    leagueId: 'test_league',
    currentMatchday: 0,
    currentYear: 2026,
    isPreSeason: false,
    isWinterBreak: false,
    records: {for (final id in ids) id: LeagueRecord()},
    rounds: rounds,
  );
  final user = db.teams.first;
  final session = CareerSession(
    manager: Manager(
      name: 'Boss',
      age: 40,
      nationality: 'Spain',
      teamId: user.id,
    ),
    team: user,
    season: season,
  );
  return (db, session);
}

/// The scoreline in FIXTURE orientation: the user's club wins 1-0.
MatchResult _userWin(
  Fixture fixture,
  PlayerDatabase db,
  String userId, {
  List<MatchEvent> events = const [],
}) {
  final home = fixture.isHomeFor(userId);
  return MatchResult(
    homeTeam: db.teams.firstWhere((t) => t.id == fixture.homeTeamId).name,
    awayTeam: db.teams.firstWhere((t) => t.id == fixture.awayTeamId).name,
    homeGoals: home ? 1 : 0,
    awayGoals: home ? 0 : 1,
    events: events,
    playerRatings: const [],
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
    storageDir = await initTestHive('fms_injury_flow');
  });

  tearDownAll(() async {
    await disposeTestHive(storageDir);
  });

  testWidgets('a scare in the match report can land in the treatment room',
      (tester) async {
    final (db, session) = _scenario();
    final user = db.teams.first;
    final container = await _containerFor(db, session);

    // The aftermath of a scare is deterministic per player and matchday, so
    // the test picks a name that will become a real absence.
    final victim = user.squad.firstWhere((p) =>
        InjuryService.rollMatchInjury(p,
            leagueId: 'test_league', year: 2026, matchday: 0) !=
        null);
    final injury = InjuryService.rollMatchInjury(victim,
        leagueId: 'test_league', year: 2026, matchday: 0)!;

    final fixture = session.season.userFixtureForRound(0, user.id)!;
    final userIsHome = fixture.isHomeFor(user.id);
    await _run(
      tester,
      container,
      (ref) => applyMatchResult(
        ref,
        _userWin(
          fixture,
          db,
          user.id,
          events: [
            MatchEvent(
              type: 'injury',
              team: userIsHome ? 'home' : 'away',
              player: victim.name,
              description: '${victim.name} pulls up and needs treatment.',
              minute: 23,
            ),
          ],
        ),
      ),
    );

    final updated = container.read(careerSessionProvider)!;
    expect(victim.isInjured, isTrue);
    expect(victim.injuryType, injury.type);
    expect(
      victim.injuryReturnDate,
      InjuryService.dateOfMatchday(2026, injury.weeks),
    );
    // He did not train this week: the injury landed before the week's work.
    expect(victim.hiddenAttributes[DevelopmentService.progressKey], isNull);
    // The medical staff put it in the news.
    expect(
      updated.transferDesk.news
          .any((n) => n.type == 'injury' && n.title.contains(victim.name)),
      isTrue,
    );
    // The rest of the squad trained normally.
    final others = updated.team.squad.where((p) => p.id != victim.id);
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

  testWidgets('a due return clears the treatment room and trains again',
      (tester) async {
    final (db, session) = _scenario();
    final user = db.teams.first;
    final container = await _containerFor(db, session);

    final returning = user.squad.first;
    returning
      ..isInjured = true
      ..injuryType = 'Knock'
      ..injuryReturnDate = InjuryService.dateOfMatchday(2026, 0);

    final fixture = session.season.userFixtureForRound(0, user.id)!;
    await _run(
      tester,
      container,
      (ref) => applyMatchResult(ref, _userWin(fixture, db, user.id)),
    );

    expect(returning.isInjured, isFalse);
    expect(returning.injuryType, isNull);
    expect(returning.injuryReturnDate, isNull);
    // Fit again means on the training grass again.
    expect(
      returning.hiddenAttributes[DevelopmentService.progressKey],
      isNotNull,
    );
  });
}
