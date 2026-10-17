import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';
import 'package:football_manager_sim/screens/career/career_dashboard_screen.dart';
import 'package:football_manager_sim/screens/new_career/new_career_screen.dart';

import '../helpers/test_hive.dart';

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

Widget _wrap(Widget child, ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: child),
  );
}

/// Same, but with a real router, for the paths that actually navigate.
/// Starting a career calls `context.go('/home')`, which throws without one.
Widget _wrapRoutered(Widget child, ProviderContainer container) {
  final router = GoRouter(
    initialLocation: '/new-career',
    routes: [
      GoRoute(path: '/new-career', builder: (_, __) => child),
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Center(child: Text('Home'))),
      ),
    ],
  );
  addTearDown(router.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  late Directory storageDir;

  setUpAll(() async {
    storageDir = await initTestHive('fms_onboarding_home');
  });

  tearDownAll(() async {
    await disposeTestHive(storageDir);
  });

  /// New Career builds its club list lazily inside a [CustomScrollView], so on
  /// the default 600dp-tall test surface the clubs never get built and cannot
  /// be found. A tall surface forces the whole sliver to lay out.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('nationalities provider', () {
    test('derives a sorted, de-duplicated list from the real data', () {
      final db = stubLeagueDatabase(4);
      final container = ProviderContainer(
        overrides: [playerDatabaseProvider.overrideWith((ref) async => db)],
      );
      addTearDown(container.dispose);

      final nations = container.read(nationalitiesProvider);

      expect(nations, isNotEmpty);
      expect(nations, orderedEquals(List<String>.from(nations)..sort()));
      expect(nations.toSet().length, nations.length,
          reason: 'the CSV repeats a nationality thousands of times');
    });
  });

  group('New Career', () {
    testWidgets('summarises the club before the career is committed',
        (tester) async {
      useTallSurface(tester);
      final db = stubLeagueDatabase(6);
      final container = ProviderContainer(
        overrides: [playerDatabaseProvider.overrideWith((ref) async => db)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(const NewCareerScreen(), container));
      expect(
        await waitForReal(
            tester, () => find.text('Club 0').evaluate().isNotEmpty),
        isTrue,
        reason: 'the New Career screen must finish loading the database',
      );

      // Nothing is chosen yet, so the CTA explains what is missing.
      expect(find.text('Pick a league and a club to continue'), findsOneWidget);

      await tester.tap(find.text('Club 0'));
      await tester.pump();

      // Choosing the club reveals budget and squad strength, which were
      // previously invisible until after the career had been created.
      expect(find.textContaining('players · avg'), findsOneWidget);
      expect(find.text('Start career at C0'), findsOneWidget);
    });

    testWidgets('refuses to overwrite a saved career without confirmation',
        (tester) async {
      useTallSurface(tester);
      final db = stubLeagueDatabase(6);
      final container = ProviderContainer(
        overrides: [
          playerDatabaseProvider.overrideWith((ref) async => db),
          hasSaveProvider.overrideWith((ref) async => true),
        ],
      );
      addTearDown(container.dispose);
      // `testWidgets` runs in a fake-async zone where a provider Timer never
      // fires, so this future only resolves inside [WidgetTester.runAsync].
      await tester.runAsync(() => container.read(hasSaveProvider.future));

      await tester.pumpWidget(_wrap(const NewCareerScreen(), container));
      expect(
        await waitForReal(
            tester, () => find.text('Club 0').evaluate().isNotEmpty),
        isTrue,
      );
      await tester.tap(find.text('Club 0'));
      await tester.pump();

      await tester.tap(find.text('Start career at C0'));
      await tester.pumpAndSettle();

      expect(find.text('Replace your current career?'), findsOneWidget);
      expect(container.read(careerSessionProvider), isNull,
          reason: 'the dialog must block the career until it is confirmed');

      await tester.tap(find.text('Keep current'));
      await tester.pumpAndSettle();
      expect(container.read(careerSessionProvider), isNull);
    });

    testWidgets('starts without a prompt when no career is saved',
        (tester) async {
      useTallSurface(tester);
      final db = stubLeagueDatabase(6);
      final container = ProviderContainer(
        overrides: [
          playerDatabaseProvider.overrideWith((ref) async => db),
          hasSaveProvider.overrideWith((ref) async => false),
        ],
      );
      addTearDown(container.dispose);
      // `testWidgets` runs in a fake-async zone where a provider Timer never
      // fires, so this future only resolves inside [WidgetTester.runAsync].
      await tester.runAsync(() => container.read(hasSaveProvider.future));

      await tester
          .pumpWidget(_wrapRoutered(const NewCareerScreen(), container));
      expect(
        await waitForReal(
            tester, () => find.text('Club 0').evaluate().isNotEmpty),
        isTrue,
      );
      await tester.tap(find.text('Club 0'));
      await tester.pump();

      await tester.tap(find.text('Start career at C0'));
      await tester.pumpAndSettle();

      expect(find.text('Replace your current career?'), findsNothing);
      expect(container.read(careerSessionProvider), isNotNull);
      expect(find.text('Home'), findsOneWidget,
          reason: 'starting a career must navigate on to the dashboard');
    });
  });

  group('Home dashboard', () {
    testWidgets('shows the board objective and the current position',
        (tester) async {
      final db = stubLeagueDatabase(8);
      final session = _sessionFor(db);
      final container = ProviderContainer(
        overrides: [careerSessionProvider.overrideWith((ref) => session)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(const CareerDashboardScreen(), container));
      await tester.pump();

      // Eight clubs means the board expects a top-four finish.
      expect(find.textContaining('Board target: finish in the top 4 of 8'),
          findsOneWidget);
    });

    testWidgets('tapping the fixture opens the opponent preview sheet',
        (tester) async {
      final db = stubLeagueDatabase(8);
      final session = _sessionFor(db);
      final container = ProviderContainer(
        overrides: [
          careerSessionProvider.overrideWith((ref) => session),
          playerDatabaseProvider.overrideWith((ref) async => db),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(const CareerDashboardScreen(), container));
      await tester.pump();

      final opponentId = session.season
          .currentFixtureFor(session.team.id)!
          .opponentOf(session.team.id)!;
      final opponent = db.teams.firstWhere((t) => t.id == opponentId);

      // The fixture hero is the tap target for scouting the opposition. Tapping
      // the "Play match" button would navigate instead, so aim at the crest row.
      await tester.tap(find.text(opponent.name).first);
      await tester.pumpAndSettle();

      expect(find.text('Key players'), findsOneWidget);
      expect(find.text('League table'), findsOneWidget);
    });
  });
}
