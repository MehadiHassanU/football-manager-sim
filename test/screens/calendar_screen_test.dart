import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/services/cup_service.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';
import 'package:football_manager_sim/screens/calendar/calendar_screen.dart';
import 'package:football_manager_sim/screens/career/career_dashboard_screen.dart';
import 'package:football_manager_sim/ui/ui.dart';

import '../helpers/test_hive.dart';

/// The narrowest phone the app claims to support.
const Size kNarrowPhone = Size(360, 640);

/// A four-club season with the cup spliced in — enough calendar for a
/// phone-sized check: league rounds, cup rounds midweek, a winter break.
(CareerSession, PlayerDatabase) _calendarCareer({int currentMatchday = 0}) {
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
    currentMatchday: currentMatchday,
    currentYear: 2026,
    isPreSeason: false,
    records: {for (final id in ids) id: LeagueRecord()},
    rounds: rounds,
    cup: cup,
  );
  final team = db.teams.first;
  final session = CareerSession(
    manager: Manager(
        name: 'Boss', age: 40, nationality: 'Spain', teamId: team.id),
    team: team,
    season: season,
  );
  return (session, db);
}

void main() {
  late Directory storageDir;

  setUpAll(() async {
    storageDir = await initTestHive('fms_calendar_screen');
  });

  tearDownAll(() async {
    await disposeTestHive(storageDir);
  });

  setUp(() {
    // Any RenderFlex overflow or layout exception fails the test that pumps.
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = kNarrowPhone;
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
    addTearDown(() {
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    CareerSession session,
    PlayerDatabase db, {
    Widget child = const CalendarScreen(),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerDatabaseProvider.overrideWith((ref) async => db),
          careerSessionProvider.overrideWith((ref) => session),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: child),
      ),
    );
    // The database provider is a future: the first frame may still be
    // loading, the second shows resolved club names.
    await tester.pump();
  }

  /// A view tall enough that a whole season builds at once, for assertions
  /// about rows below the fold on a real phone.
  void useTallView() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize =
        const Size(360, 1600);
  }

  testWidgets('a 360 dp phone shows the season, dated and marked up',
      (tester) async {
    final (session, db) = _calendarCareer();
    await pumpScreen(tester, session, db);

    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Season 2026/27'), findsOneWidget);
    expect(find.text('Matchday 1 of 8'), findsOneWidget);
    // Round 0 of the round clock: 1 August of the season year.
    expect(find.text('Sat 1 Aug'), findsOneWidget);
    expect(find.text('NEXT UP'), findsOneWidget);
    // The first cup tie reads as midweek.
    expect(find.text('Tue 11 Aug'), findsOneWidget);
    expect(find.textContaining('Semi-finals'), findsOneWidget);
    expect(find.text('August 2026'), findsOneWidget);
  });

  testWidgets('the whole season lists the break and every cup stage',
      (tester) async {
    useTallView();
    final (session, db) = _calendarCareer(currentMatchday: 2);
    await pumpScreen(tester, session, db);

    expect(find.text('Winter break'), findsOneWidget);
    expect(find.textContaining('· Final'), findsOneWidget);
    // Round 2 is the first cup tie, so it is the marked-up row now.
    expect(find.text('NEXT UP'), findsOneWidget);
  });

  testWidgets('a drawn cup tie shows which way the shootout went',
      (tester) async {
    useTallView();
    final (session, db) = _calendarCareer();
    final cup = session.season.cup!;
    final tie = session.season
        .userFixtureForRound(cup.anchors[0], session.team.id)!;
    tie.record(1, 1);
    // The verdict the bracket used, resolved the same way the full-time
    // screen and the bracket do.
    final note = CupService.shootoutNote(
      season: session.season,
      tie: tie,
      teamId: session.team.id,
      homeGoals: 1,
      awayGoals: 1,
    )!;
    // The career has moved on past the cup round.
    final advanced = CareerSession(
      manager: session.manager,
      team: session.team,
      season: SeasonState(
        leagueId: session.season.leagueId,
        currentMatchday: cup.anchors[0] + 1,
        currentYear: session.season.currentYear,
        isPreSeason: false,
        records: session.season.records,
        rounds: session.season.rounds,
        cup: cup,
      ),
    );

    await pumpScreen(tester, advanced, db);

    final suffix = note.advanced ? 'won on pens' : 'lost on pens';
    expect(find.textContaining('D 1–1'), findsOneWidget);
    expect(find.textContaining('· $suffix'), findsOneWidget);
  });

  testWidgets('a career with no drawn season gets an empty state',
      (tester) async {
    final (session, db) = _calendarCareer();
    final empty = CareerSession(
      manager: session.manager,
      team: session.team,
      season: SeasonState(leagueId: 'test_league', currentYear: 2026),
    );
    await pumpScreen(tester, empty, db);

    expect(find.text('No schedule'), findsOneWidget);
  });

  testWidgets('Home offers the schedule beside the table', (tester) async {
    final (session, db) = _calendarCareer();
    await pumpScreen(tester, session, db, child: const CareerDashboardScreen());

    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Table'), findsOneWidget);
  });
}
