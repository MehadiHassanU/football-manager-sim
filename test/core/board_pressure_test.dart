import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/transfer.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';
import 'package:football_manager_sim/providers/settings_providers.dart';

import '../helpers/test_hive.dart';

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

SeasonState _seasonFor(PlayerDatabase db, int matchday) => SeasonState(
      leagueId: 'test_league',
      currentMatchday: matchday,
      currentYear: 2026,
      isPreSeason: false,
      records: {for (final t in db.teams) t.id: LeagueRecord()},
      rounds: buildRounds([for (final t in db.teams) t.id], rng: Random(1)),
    );

CareerSession _sessionFor(PlayerDatabase db, {int matchday = 1}) {
  final team = db.teams.first;
  return CareerSession(
    manager: Manager(
      name: 'Boss',
      age: 40,
      nationality: 'Spain',
      teamId: team.id,
    ),
    team: team,
    season: _seasonFor(db, matchday),
  );
}

Future<ProviderContainer> _containerFor(
  PlayerDatabase db,
  CareerSession session, {
  List<Override> extra = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      playerDatabaseProvider.overrideWith((ref) async => db),
      careerSessionProvider.overrideWith((ref) => session),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  await container.read(playerDatabaseProvider.future);
  return container;
}

void main() {
  setUpAll(() async {
    await initTestHive('fms_board_pressure');
  });

  group('the board judges clubs by their standing', () {
    test('bigger clubs are held to a higher expectation', () {
      expect(boardExpectedPoints(90), greaterThan(boardExpectedPoints(70)));
      expect(boardExpectedPoints(70), greaterThan(boardExpectedPoints(50)));
      // The ruler is bounded in both directions.
      expect(boardExpectedPoints(150), boardExpectedPoints(100));
      expect(boardExpectedPoints(10), boardExpectedPoints(40));
    });

    testWidgets('the same losing run hurts an elite club far more',
        (tester) async {
      double? smallRisk;
      {
        final db = stubLeagueDatabase(8);
        final small = db.teams[0]..reputation = 50;
        final session = _sessionFor(db, matchday: 2);
        small.squad.clear(); // keep the fixture pure: only the seat matters
        expect(small.reputation, 50);
        session
          ..userResults.addAll([0, 0])
          ..manager.sackablePercent = 10;
        final container = await _containerFor(db, session);
        await _run(tester, container, (ref) {
          smallRisk = evaluateBoard(ref, session)?.risk;
        });
      }

      double? eliteRisk;
      {
        final db = stubLeagueDatabase(8);
        final elite = db.teams[0]..reputation = 90;
        final session = _sessionFor(db, matchday: 2);
        expect(elite.reputation, 90);
        session
          ..userResults.addAll([0, 0])
          ..manager.sackablePercent = 10;
        final container = await _containerFor(db, session);
        await _run(tester, container, (ref) {
          eliteRisk = evaluateBoard(ref, session)?.risk;
        });
      }

      expect(eliteRisk!, greaterThan(smallRisk!),
          reason: 'a club this size draws no sympathy for a losing run');
    });

    testWidgets('a winning run still buys room at the top', (tester) async {
      final db = stubLeagueDatabase(8);
      final session = _sessionFor(db, matchday: 2);
      session.team.reputation = 90;
      session
        ..manager.sackablePercent = 60
        ..userResults.addAll([3, 3]);
      final container = await _containerFor(db, session);

      await _run(tester, container, (ref) => evaluateBoard(ref, session));

      expect(session.manager.sackablePercent, lessThan(60));
    });
  });

  group('the board judges the closed window', () {
    testWidgets('a heavyweight club that made zero arrivals is punished',
        (tester) async {
      final db = stubLeagueDatabase(8);
      final session = _sessionFor(db, matchday: 4);
      session.team.reputation = 75;
      session.team
        ..budget = 90000000
        ..transferBudget = 60000000;
      session.manager.sackablePercent = 20;
      final container = await _containerFor(db, session);

      await _run(
          tester, container, (ref) => advanceTransferDesk(ref, session));

      expect(session.manager.sackablePercent, 30,
          reason: '+10 for closing the window with zero arrivals');
      expect(session.boardNote, contains('without a single arrival'));
      // The desk's own summary still ran.
      expect(
        session.transferDesk.news.any((n) => n.type == 'summary'),
        isTrue,
      );
    });

    testWidgets('a club that did business is not punished', (tester) async {
      final db = stubLeagueDatabase(8);
      final session = _sessionFor(db, matchday: 4);
      session.team.reputation = 75;
      session.manager.sackablePercent = 20;
      // A permanent arrival inside the summer window.
      session.transferDesk.ledger.add(TransferMove(
        playerId: 5001,
        playerName: 'Big Signing',
        fromClub: 'Elsewhere',
        toClub: session.team.name,
        kind: 'permanent',
        fee: 12000000,
        year: 2026,
        matchday: 1,
      ));
      final container = await _containerFor(db, session);

      await _run(
          tester, container, (ref) => advanceTransferDesk(ref, session));

      expect(session.manager.sackablePercent, 20,
          reason: 'the window earned its budget');
      expect(session.boardNote, isNot(contains('without a single arrival')));
    });

    testWidgets('small clubs escape the inactivity penalty', (tester) async {
      final db = stubLeagueDatabase(8);
      final session = _sessionFor(db, matchday: 4);
      session.team.reputation = 55;
      session.manager.sackablePercent = 20;
      final container = await _containerFor(db, session);

      await _run(
          tester, container, (ref) => advanceTransferDesk(ref, session));

      expect(session.manager.sackablePercent, 20,
          reason: 'a lean budget is a plan, not neglect');
    });
  });

  group('the rollover sanction scales with difficulty', () {
    // 8 clubs play a double round-robin: 14 matchdays.
    const finalMatchday = 14;
    for (final (difficulty, factor) in [
      ('Easy', 1.22),
      ('Normal', 1.15),
      ('Hard', 1.10),
    ]) {
      testWidgets('$difficulty: bill x $factor', (tester) async {
        final db = stubLeagueDatabase(8);
        final session = _sessionFor(db, matchday: finalMatchday);
        for (final player in session.team.squad) {
          player.weeklyWage = 20000;
        }
        session.team.wageBudget = 0;
        final container = await _containerFor(db, session, extra: [
          difficultyProvider.overrideWith((ref) => difficulty),
        ]);

        SeasonOutcome? outcome;
        await _run(tester, container, (ref) {
          outcome = rollIntoNextSeason(ref);
        });

        expect(outcome, isNotNull,
            reason: 'season must be over before a rollover runs');
        final bill = session.team.squad.fold<double>(
            0, (sum, p) => sum + p.weeklyWage);
        expect(
          session.team.wageBudget,
          closeTo(bill * factor, 1.0),
          reason:
              '$difficulty sanctions bill x $factor (bill here: $bill/wk)',
        );
      });
    }

    testWidgets('an existing ceiling is never lowered', (tester) async {
      final db = stubLeagueDatabase(8);
      final session = _sessionFor(db, matchday: 14);
      for (final player in session.team.squad) {
        player.weeklyWage = 20000;
      }
      session.team.wageBudget = 900000;
      final container = await _containerFor(db, session, extra: [
        difficultyProvider.overrideWith((ref) => 'Hard'),
      ]);

      await _run(tester, container, (ref) => rollIntoNextSeason(ref));

      expect(session.team.wageBudget, 900000,
          reason: 'a board never cuts an existing sanction');
    });
  });
}
