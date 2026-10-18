import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/match.dart';
import 'package:football_manager_sim/core/models/player.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/team.dart';
import 'package:football_manager_sim/core/services/match_simulator_service.dart';
import 'package:football_manager_sim/core/services/transfer_market_service.dart';
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
      homeMomentum: const [],
      awayMomentum: const [],
      fullTimeCommentary: '',
    );

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

    test('the difficulty scale tilts simulated results towards the favourite',
        () {
      // Difficulty feeds a strength multiplier into the match simulator, and
      // the simulator's goal rates conserve the total (home + away = 2.5):
      // a boost decides WHO scores, not how many goals exist. It pushes goals
      // towards the stronger club and away from the weaker one. A season-sized
      // sample is far too noisy to see that (flips are a few fixtures a year),
      // so this measures the simulator directly across a fixed seed batch.
      final sim = MatchSimulatorService();
      final easyBoost = difficultyStrengthMultiplier('Easy');
      final hardBoost = difficultyStrengthMultiplier('Hard');
      var easyFavourite = 0;
      var easyUnderdog = 0;
      var hardFavourite = 0;
      var hardUnderdog = 0;
      for (var seed = 0; seed < 20000; seed++) {
        final easy = sim.simulateScore(
          homeStrength: 90 * easyBoost,
          awayStrength: 60 * easyBoost,
          rng: Random(seed),
        );
        final hard = sim.simulateScore(
          homeStrength: 90 * hardBoost,
          awayStrength: 60 * hardBoost,
          rng: Random(seed),
        );
        easyFavourite += easy.$1;
        easyUnderdog += easy.$2;
        hardFavourite += hard.$1;
        hardUnderdog += hard.$2;
      }
      expect(hardFavourite, greaterThan(easyFavourite),
          reason: 'Hard must push goals towards the stronger club');
      expect(hardUnderdog, lessThan(easyUnderdog),
          reason: 'and take them away from the weaker one');
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

  group('wage ceiling', () {
    Team cappedTeam(double ceiling) => Team(
          id: 'capped',
          name: 'Capped FC',
          shortName: 'CAP',
          leagueId: 'test_league',
          country: 'Spain',
          stadiumName: 'The Cap',
          stadiumCapacity: 30000,
          budget: 5000000,
          color: '#123456',
          badgeUrl: '',
          wageBudget: ceiling,
          squad: [
            for (var i = 0; i < 16; i++)
              stubPlayer(id: 80000 + i, name: 'W$i', ovr: 70)
                ..weeklyWage = 5625, // €90k/wk in total
          ],
        );

    CareerSession sessionFor(Team team) => CareerSession(
          manager: Manager(name: 'Boss', age: 40, nationality: 'Spain'),
          team: team,
          season: SeasonState(
              leagueId: 'test_league', records: {'capped': LeagueRecord()}),
        );

    testWidgets('a signing past the weekly ceiling is refused', (tester) async {
      final team = cappedTeam(100000);
      final session = sessionFor(team);
      final container = _containerFor(stubLeagueDatabase(8), session);
      final target = stubPlayer(id: 81000, name: 'Target', ovr: 70);

      await _run(
        tester,
        container,
        (ref) => buyPlayer(ref, target, 1000, wage: 20000),
      );

      expect(team.squad.any((p) => p.id == 81000), isFalse);
      final reason = container.read(transferBlockReasonProvider)!;
      expect(reason, contains('wage budget'));
      expect(reason, contains('room'));
      expect(team.transferBudget, closeTo(1500000, 1),
          reason: 'a refused signing must not spend the fee');
    });

    testWidgets('a signing inside the ceiling goes through', (tester) async {
      final team = cappedTeam(100000);
      final session = sessionFor(team);
      final container = _containerFor(stubLeagueDatabase(8), session);
      final target = stubPlayer(id: 81001, name: 'Bargain', ovr: 70);

      await _run(
        tester,
        container,
        (ref) => buyPlayer(ref, target, 1000, wage: 5000),
      );

      expect(team.squad.any((p) => p.id == 81001), isTrue);
      expect(weeklyWageBill(team), 95000);
      expect(container.read(transferBlockReasonProvider), isNull);
    });

    testWidgets('a club with no configured ceiling is never blocked',
        (tester) async {
      // Saves written before the field existed read back as 0, which has to
      // mean "no ceiling" rather than "no money".
      final team = cappedTeam(0);
      final session = sessionFor(team);
      final container = _containerFor(stubLeagueDatabase(8), session);
      final target = stubPlayer(id: 81002, name: 'Expensive', ovr: 90);

      await _run(
        tester,
        container,
        (ref) => buyPlayer(ref, target, 1000, wage: 900000),
      );

      expect(team.squad.any((p) => p.id == 81002), isTrue);
    });

    test('backfill derives the ceiling from the bill the club inherits', () {
      final team = cappedTeam(0);
      TransferMarketService().backfillTransferData([team], 2026);

      expect(team.wageBudget, closeTo(90000 * 1.15, 1),
          reason: 'the board sanctions the inherited bill plus headroom');

      // A ceiling already on the save must survive the same call.
      team.wageBudget = 123456;
      TransferMarketService().backfillTransferData([team], 2026);
      expect(team.wageBudget, 123456);
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

  group('appearances', () {
    List<PlayerRating> ratings(List<Player> squad) => [
          for (final p in squad.take(11))
            PlayerRating(
              playerName: p.name,
              position: p.primaryPosition,
              rating: 7,
              goals: 0,
              assists: 0,
              minutes: 90,
              started: true,
            ),
        ];

    MatchResult withRatings(CareerSession session, PlayerDatabase db) {
      final fixture = session.season.currentFixtureFor(session.team.id);
      final userIsHome = fixture?.isHomeFor(session.team.id) ?? true;
      final mine = ratings(session.team.squad);
      final theirs = ratings(db.teams[1].squad);
      return MatchResult(
        homeTeam: userIsHome ? session.team.name : db.teams[1].name,
        awayTeam: userIsHome ? db.teams[1].name : session.team.name,
        homeGoals: 2,
        awayGoals: 0,
        events: const [],
        // The report keeps each side's own list, in home/away order.
        homeRatings: userIsHome ? mine : theirs,
        awayRatings: userIsHome ? theirs : mine,
        homeMomentum: const [],
        awayMomentum: const [],
        fullTimeCommentary: '',
      );
    }

    testWidgets('a played fixture records apps, minutes and match rating',
        (tester) async {
      final db = stubLeagueDatabase(8);
      final session = _sessionFor(db);
      final container = _containerFor(db, session);
      final starter = session.team.squad.first;
      final bench = session.team.squad.last;
      expect(starter.gamesPlayed, 0);

      await _run(
        tester,
        container,
        (ref) => applyMatchResult(ref, withRatings(session, db)),
      );

      expect(starter.gamesPlayed, 1);
      expect(starter.minutesPlayed, 90);
      expect(starter.matchRating, 7);
      expect(bench.gamesPlayed, 0,
          reason: 'only the eleven that played get appearance credit');
    });

    testWidgets('a round whose fixture is already played credits no extras',
        (tester) async {
      final db = stubLeagueDatabase(8);
      final session = _sessionFor(db);
      final container = _containerFor(db, session);
      final result = withRatings(session, db);
      final starter = session.team.squad.first;

      await _run(tester, container, (ref) => applyMatchResult(ref, result));
      expect(starter.gamesPlayed, 1);

      // A save left pointing at a played round (a crash between the result
      // landing and the matchday advancing) must not credit him again.
      final restored = CareerSession(
        manager: session.manager,
        team: session.team,
        season: SeasonState(
          leagueId: 'test_league',
          currentMatchday: 0,
          currentYear: 2026,
          isPreSeason: false,
          records: session.season.records,
          rounds: session.season.rounds,
        ),
      );
      final restoredContainer = _containerFor(db, restored);
      await _run(
        tester,
        restoredContainer,
        (ref) => applyMatchResult(ref, result),
      );

      expect(starter.gamesPlayed, 1,
          reason: 'the fixture is already in the record');
      expect(starter.minutesPlayed, 90);
    });

    testWidgets('squad-mates who share a name keep separate season stats',
        (tester) async {
      final base = stubLeagueDatabase(8);
      final original = base.teams.first;
      // Real clubs ship like this: Gil Vicente carry two "Zé Carlos".
      final twinA = stubPlayer(
          id: 9001,
          name: 'J. Smith',
          position: 'CB',
          team: original.name,
          ovr: 76);
      final twinB = stubPlayer(
          id: 9002,
          name: 'J. Smith',
          position: 'CB',
          team: original.name,
          ovr: 72);
      final removed = {original.squad[2].id, original.squad[3].id};
      final squad = [
        for (final p in original.squad)
          if (!removed.contains(p.id)) p,
        twinA,
        twinB,
      ];
      final userTeam = Team(
        id: original.id,
        name: original.name,
        shortName: original.shortName,
        leagueId: original.leagueId,
        country: original.country,
        stadiumName: original.stadiumName,
        stadiumCapacity: original.stadiumCapacity,
        budget: original.budget,
        color: original.color,
        badgeUrl: original.badgeUrl,
        squad: squad,
      );
      final db = PlayerDatabase(
        players: [
          for (final p in base.players)
            if (!removed.contains(p.id)) p,
          twinA,
          twinB,
        ],
        teams: [userTeam, ...base.teams.skip(1)],
        leagues: base.leagues,
        playersByTeam: {...base.playersByTeam, original.id: squad},
      );

      final session = _sessionFor(db);
      final container = _containerFor(db, session);
      final fixture = session.season.currentFixtureFor(session.team.id);
      final userIsHome = fixture?.isHomeFor(session.team.id) ?? true;
      final mine = [
        for (final p in session.team.squad)
          PlayerRating(
            playerName: p.name,
            playerId: p.id,
            position: p.primaryPosition,
            rating: p.id == twinA.id ? 9 : (p.id == twinB.id ? 5 : 7),
            goals: 0,
            assists: 0,
            minutes: 90,
            started: true,
          ),
      ];
      final result = MatchResult(
        homeTeam: userIsHome ? session.team.name : db.teams[1].name,
        awayTeam: userIsHome ? db.teams[1].name : session.team.name,
        homeGoals: 2,
        awayGoals: 0,
        events: const [],
        homeRatings: userIsHome ? mine : const <PlayerRating>[],
        awayRatings: userIsHome ? const <PlayerRating>[] : mine,
        homeMomentum: const [],
        awayMomentum: const [],
        fullTimeCommentary: '',
      );

      final formA = twinA.form;
      final formB = twinB.form;
      await _run(tester, container, (ref) => applyMatchResult(ref, result));

      // Each twin is credited with his own line: the shared name merges
      // nothing.
      expect(twinA.gamesPlayed, 1);
      expect(twinB.gamesPlayed, 1);
      expect(twinA.minutesPlayed, 90);
      expect(twinB.minutesPlayed, 90);
      expect(twinA.matchRating, 9);
      expect(twinB.matchRating, 5);
      expect(twinA.form, ((formA * 2 + 9) / 3).round().clamp(1, 10));
      expect(twinB.form, ((formB * 2 + 5) / 3).round().clamp(1, 10));
      expect(twinA.morale, greaterThan(twinB.morale),
          reason: 'the 9-rated twin had the better afternoon');
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
