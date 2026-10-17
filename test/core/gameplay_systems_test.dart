import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/match.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/team.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';
import 'package:football_manager_sim/providers/settings_providers.dart';
import 'package:football_manager_sim/screens/match/match_screen.dart';

import '../helpers/test_hive.dart';

/// Gives the tests a real [WidgetRef] for the provider functions, which all
/// take one rather than a plain `Ref`.
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

/// Pumps [_Harness] into a container with [overrides] and runs it once.
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

CareerSession _sessionFor(PlayerDatabase db) {
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
      currentMatchday: 0,
      currentYear: 2026,
      isPreSeason: false,
      records: {for (final id in ids) id: LeagueRecord()},
      rounds: buildRounds(ids, rng: Random(1)),
    ),
  );
}

ProviderContainer _containerFor(
  PlayerDatabase db,
  CareerSession session, {
  List<Override> extra = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      playerDatabaseProvider.overrideWith((ref) async => db),
      careerSessionProvider.overrideWith((ref) => session),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

MatchResult _scoreline({int homeGoals = 0, int awayGoals = 0}) => MatchResult(
      homeTeam: 'Home',
      awayTeam: 'Away',
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      events: const [],
      playerRatings: const [],
      homeMomentum: const [],
      awayMomentum: const [],
      fullTimeCommentary: '',
    );

/// Total goals scored across every club after [matchdays] results were applied
/// under the supplied difficulty.
int _leagueGoalsAfter(CareerSession session, int matchdays) {
  var goals = 0;
  for (final r in session.season.records.values) {
    goals += r.goalsFor;
  }
  return goals;
}

void main() {
  late Directory storageDir;

  setUpAll(() async {
    storageDir = await initTestHive('fms_gameplay_systems');
  });

  tearDownAll(() async {
    await disposeTestHive(storageDir);
  });

  group('difficulty setting', () {
    test('multiplier orders Easy below Normal below Hard', () {
      expect(difficultyStrengthMultiplier('Easy'),
          lessThan(difficultyStrengthMultiplier('Normal')));
      expect(difficultyStrengthMultiplier('Hard'),
          greaterThan(difficultyStrengthMultiplier('Normal')));
      expect(difficultyStrengthMultiplier('Normal'), 1.0,
          reason: 'Normal must stay a neutral 1.0 so existing saves are '
              'unaffected');
    });

    testWidgets('Hard produces more league goals than Easy over a season run',
        (tester) async {
      // The round RNG is seeded from league/year/round and not from the clock,
      // so the only thing that can differ between these two runs is the
      // strength the difficulty setting feeds the simulator.
      Future<int> runAt(String difficulty) async {
        final db = stubLeagueDatabase(8);
        final session = _sessionFor(db);
        final container = _containerFor(db, session, extra: [
          difficultyProvider.overrideWith((ref) => difficulty),
        ]);
        for (var round = 0; round < 10; round++) {
          final fixture = session.season.currentFixtureFor(session.team.id);
          if (fixture == null) break;
          final userIsHome = fixture.isHomeFor(session.team.id);
          await _run(
            tester,
            container,
            (ref) =>
                applyMatchResult(ref, _scoreline(homeGoals: 1, awayGoals: 1)),
          );
          expect(userIsHome, isA<bool>());
        }
        return _leagueGoalsAfter(session, 10);
      }

      final easy = await runAt('Easy');
      final hard = await runAt('Hard');

      expect(hard, greaterThan(easy),
          reason: 'Hard must scale the opposition up (easy=$easy, '
              'hard=$hard)');
    });

    testWidgets('difficulty leaves the manager\'s own club untouched',
        (tester) async {
      final db = stubLeagueDatabase(8);
      final session = _sessionFor(db);
      final container = _containerFor(db, session, extra: [
        difficultyProvider.overrideWith((ref) => 'Hard'),
      ]);
      await _run(
        tester,
        container,
        (ref) => applyMatchResult(ref, _scoreline(homeGoals: 3, awayGoals: 0)),
      );
      expect(session.team.goalsFor, 3,
          reason: 'the user scores the fixture they simulated, whatever the '
              'difficulty');
    });
  });

  group('board and sacking', () {
    testWidgets('a losing streak raises the sack-risk gauge', (tester) async {
      final db = stubLeagueDatabase(8);
      final session = _sessionFor(db);
      session.manager.sackablePercent = 20;
      final container = _containerFor(db, session);

      BoardVerdict? verdict;
      await _run(tester, container, (ref) {
        session.userResults.add(0);
        verdict = evaluateBoard(ref, session);
      });

      expect(verdict, isNotNull);
      expect(session.manager.sackablePercent, greaterThan(20),
          reason: 'losing should raise the risk the Home screen shows');
      expect(verdict!.sacked, isFalse);
    });

    testWidgets('a winning streak lowers the sack-risk gauge', (tester) async {
      final db = stubLeagueDatabase(8);
      final session = _sessionFor(db);
      session.manager.sackablePercent = 60;
      final container = _containerFor(db, session);

      await _run(tester, container, (ref) {
        session.userResults.add(3);
        evaluateBoard(ref, session);
      });

      expect(session.manager.sackablePercent, lessThan(60));
    });

    testWidgets('reaching the threshold sacks the manager when enabled',
        (tester) async {
      final db = stubLeagueDatabase(8);
      final session = _sessionFor(db);
      // Start at the threshold: one evaluation must be enough to end it.
      session.manager.sackablePercent = 99;
      final container = _containerFor(db, session);

      BoardVerdict? verdict;
      await _run(tester, container, (ref) {
        session.userResults.add(0);
        verdict = evaluateBoard(ref, session);
      });

      expect(verdict!.sacked, isTrue);
      expect(session.manager.sackablePercent, 100);
      expect(verdict!.reason, contains('Sacked'));
    });

    testWidgets('the threshold does nothing when sacking is disabled',
        (tester) async {
      final db = stubLeagueDatabase(8);
      final session = _sessionFor(db);
      session.manager.sackablePercent = 99;
      final container = _containerFor(db, session, extra: [
        isSackingEnabledProvider.overrideWith((ref) => false),
      ]);

      BoardVerdict? verdict;
      await _run(tester, container, (ref) {
        session.userResults.add(0);
        verdict = evaluateBoard(ref, session);
      });

      expect(verdict!.sacked, isFalse);
    });

    testWidgets('sack-risk setting moves the value the Home gauge reads',
        (tester) async {
      final db = stubLeagueDatabase(8);
      final session = _sessionFor(db);
      final container = _containerFor(db, session, extra: [
        sackablePercentProvider.overrideWith((ref) => 42),
      ]);

      await _run(tester, container, syncSackRiskToManager);

      expect(session.manager.sackablePercent, 42,
          reason: 'the settings slider and the Home meter were reading two '
              'separate copies of this value');
    });

    testWidgets('the board states its verdict on the session for Home to show',
        (tester) async {
      final db = stubLeagueDatabase(8);
      final session = _sessionFor(db);
      session.manager.sackablePercent = 20;
      final container = _containerFor(db, session);

      BoardVerdict? verdict;
      await _run(tester, container, (ref) {
        session.userResults.add(0);
        verdict = evaluateBoard(ref, session);
      });

      expect(session.boardNote, verdict!.reason,
          reason: 'the Home screen reads the note, so it must be recorded on '
              'the session rather than only returned');
      expect(session.boardNote, isNotEmpty);
    });

    testWidgets('a rebuild that does not re-evaluate keeps the board note',
        (tester) async {
      final db = stubLeagueDatabase(8);
      final ids = [for (final t in db.teams) t.id];
      final userTeam = db.teams.first;
      // Paused at the winter break: resuming rebuilds the session but is not a
      // match, so the board must not speak and must not move.
      final session = CareerSession(
        manager: Manager(
            name: 'Boss', age: 40, nationality: 'Spain', teamId: userTeam.id),
        team: userTeam,
        season: SeasonState(
          leagueId: 'test_league',
          currentYear: 2026,
          isPreSeason: false,
          isWinterBreak: true,
          records: {for (final id in ids) id: LeagueRecord()},
          rounds: buildRounds(ids, rng: Random(1)),
        ),
      );
      session.boardNote = 'The board is watching closely.';
      final riskBefore = session.manager.sackablePercent;
      final container = _containerFor(db, session);

      await _run(tester, container, resumeFromWinterBreak);

      final after = container.read(careerSessionProvider)!;
      expect(after.boardNote, 'The board is watching closely.',
          reason: '_rebuildSession replaces the session and must carry the '
              'note across, or Home silently loses it');
      expect(after.manager.sackablePercent, riskBefore,
          reason: 'no match was played, so the board risk must not move');
    });

    testWidgets('sacking the manager clears the career and the save',
        (tester) async {
      final db = stubLeagueDatabase(8);
      final session = _sessionFor(db);
      final container = _containerFor(db, session);

      await _run(tester, container, (ref) async {
        expect(await sackManager(ref), isTrue);
      });

      expect(container.read(careerSessionProvider), isNull,
          reason: 'a sacked career must not stay active in memory');
    });
  });

  group('FFP enforcement', () {
    /// A club with no schedule left and no banked revenue, so any signing
    /// breaches the wage-ratio limit.
    Team brokeTeam() => Team(
          id: 'broke',
          name: 'Broke FC',
          shortName: 'BRK',
          leagueId: 'test_league',
          country: 'Spain',
          stadiumName: 'Nowhere',
          stadiumCapacity: 1000,
          budget: 5000000,
          color: '#000000',
          badgeUrl: '',
          squad: [
            for (var i = 0; i < 16; i++)
              stubPlayer(id: 90000 + i, name: 'P$i', ovr: 70),
          ],
          revenue: 0,
        );

    testWidgets('blocks a signing that would breach the wage ratio',
        (tester) async {
      final team = brokeTeam();
      final session = CareerSession(
        manager: Manager(name: 'Boss', age: 40, nationality: 'Spain'),
        team: team,
        season: SeasonState(
            leagueId: 'test_league', records: {'broke': LeagueRecord()}),
      );
      final container = _containerFor(
        stubLeagueDatabase(8),
        session,
        extra: [ffpEnabledProvider.overrideWith((ref) => true)],
      );
      final target = stubPlayer(id: 777, name: 'Target', ovr: 85);

      await _run(tester, container, (ref) => buyPlayer(ref, target, 1000));

      expect(team.squad.any((p) => p.id == 777), isFalse);
      expect(container.read(transferBlockReasonProvider), contains('FFP'));
    });

    testWidgets('allows the same signing with enforcement off', (tester) async {
      final team = brokeTeam();
      final session = CareerSession(
        manager: Manager(name: 'Boss', age: 40, nationality: 'Spain'),
        team: team,
        season: SeasonState(
            leagueId: 'test_league', records: {'broke': LeagueRecord()}),
      );
      final container = _containerFor(
        stubLeagueDatabase(8),
        session,
        extra: [ffpEnabledProvider.overrideWith((ref) => false)],
      );
      final target = stubPlayer(id: 778, name: 'Target', ovr: 85);

      await _run(tester, container, (ref) => buyPlayer(ref, target, 1000));

      expect(team.squad.any((p) => p.id == 778), isTrue);
      expect(container.read(transferBlockReasonProvider), isNull);
    });
  });

  group('commentary settings', () {
    final events = [
      MatchEvent(
          type: 'goal', team: 'A', player: 'X', description: 'Goal', minute: 3),
      MatchEvent(
          type: 'chance',
          team: 'A',
          player: 'Y',
          description: 'Chance',
          minute: 10),
      MatchEvent(
          type: 'card',
          team: 'B',
          player: 'Z',
          description: 'Card',
          minute: 20),
      MatchEvent(
          type: 'commentary',
          team: 'B',
          player: '-',
          description: 'Ball in play',
          minute: 30),
    ];

    test('off removes the whole feed', () {
      final filtered =
          applyCommentarySettings(events, enabled: false, level: 'all');
      expect(filtered, isEmpty);
    });

    test('key events drops chances and running commentary', () {
      final filtered =
          applyCommentarySettings(events, enabled: true, level: 'keyEvents');
      expect(filtered.map((e) => e.type), ['goal', 'card']);
    });

    test('all keeps every event', () {
      final filtered =
          applyCommentarySettings(events, enabled: true, level: 'all');
      expect(filtered.length, events.length);
    });
  });

  group('theme setting', () {
    test('themeModeOf maps the stored value', () {
      expect(themeModeOf('light'), ThemeMode.light);
      expect(themeModeOf('dark'), ThemeMode.dark);
      expect(themeModeOf('system'), ThemeMode.system);
      expect(themeModeOf('anything else'), ThemeMode.system,
          reason: 'an unknown value must fall back, not crash the app');
    });

    testWidgets('reset restores every setting to its default', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(difficultyProvider.notifier).state = 'Hard';
      container.read(themeModeProvider.notifier).state = 'light';
      container.read(ffpEnabledProvider.notifier).state = true;
      container.read(sackablePercentProvider.notifier).state = 90;

      await _run(tester, container, resetSettingsToDefaults);

      expect(container.read(difficultyProvider), 'Normal');
      expect(container.read(themeModeProvider), 'system');
      expect(container.read(ffpEnabledProvider), isFalse);
      expect(container.read(sackablePercentProvider), 5.0);
    });
  });
}
