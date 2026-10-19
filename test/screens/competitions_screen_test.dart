import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/services/cup_service.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';
import 'package:football_manager_sim/screens/competitions/competitions_screen.dart';
import 'package:football_manager_sim/ui/ui.dart';

import '../helpers/test_hive.dart';

/// A four-club top-flight season with the country's three competitions: the
/// FA Cup and EFL Cup (semi-final and final) plus the Community Shield.
(CareerSession, PlayerDatabase) _competitionCareer() {
  final db = stubLeagueDatabase(4);
  for (final team in db.teams) {
    team.leagueId = 'premier_league';
  }
  final ids = [for (final team in db.teams) team.id];
  final rounds = buildRounds(ids);
  final cups = CupService.attachCompetitions(
    rounds: rounds,
    teams: db.teams,
    leagueId: 'premier_league',
    currentYear: 2026,
  );
  final season = SeasonState(
    leagueId: 'premier_league',
    currentYear: 2026,
    isPreSeason: false,
    records: {for (final id in ids) id: LeagueRecord()},
    rounds: rounds,
    cups: cups,
  );
  final team = db.teams.first;
  final session = CareerSession(
    manager:
        Manager(name: 'Boss', age: 40, nationality: 'England', teamId: team.id),
    team: team,
    season: season,
  );
  session.trophies.add('FA Cup 2025');
  return (session, db);
}

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    CareerSession session,
    PlayerDatabase db,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerDatabaseProvider.overrideWith((ref) async => db),
          careerSessionProvider.overrideWith((ref) => session),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const CompetitionsScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize =
        const Size(360, 2000);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
    addTearDown(() {
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });
  });

  testWidgets('lists every competition, the club route and the cabinet',
      (tester) async {
    final (session, db) = _competitionCareer();
    await pumpScreen(tester, session, db);

    expect(find.text('Competitions'), findsOneWidget);
    expect(find.text('FA Cup'), findsOneWidget);
    expect(find.text('EFL Cup'), findsOneWidget);
    expect(find.text('FA Community Shield'), findsOneWidget);
    expect(find.text('YOUR ROUTE'), findsWidgets);
    expect(find.text('BRACKET'), findsWidgets);
    expect(find.text('TROPHY CABINET'), findsOneWidget);
    expect(find.text('FA Cup 2025'), findsOneWidget);
    // The FA Cup route has a semi-final tie drawn at attach time.
    expect(find.textContaining('Semi-finals —'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a 360 dp phone renders the screen without overflowing',
      (tester) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize =
        const Size(360, 640);
    final (session, db) = _competitionCareer();
    await pumpScreen(tester, session, db);
    expect(find.text('Competitions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cup winner is named once the final is played', (tester) async {
    final (session, db) = _competitionCareer();
    final season = session.season;
    final faCup = season.cups.firstWhere((c) => c.id == 'fa_cup');
    // Play the semi-finals, advance, then play the final. The user's club
    // wins both 2-0 so the card should read Champions.
    for (var pass = 0; pass < 2; pass++) {
      for (final anchor in faCup.anchors) {
        for (final fixture in season.rounds[anchor]) {
          if (fixture.played) continue;
          final isUser = fixture.involves(session.team.id);
          if (isUser) {
            final home = fixture.homeTeamId == session.team.id;
            fixture.record(home ? 2 : 0, home ? 0 : 2);
          } else {
            fixture.record(1, 0);
          }
        }
      }
      CupService.progressCup(season);
    }
    // Make sure the user's next opponent is beatable when it is the user's
    // turn in the final; the loop above records every user tie 2-0, but the
    // final only exists after round one, so a third pass covers it.
    for (final anchor in faCup.anchors) {
      for (final fixture in season.rounds[anchor]) {
        if (!fixture.played && fixture.involves(session.team.id)) {
          final home = fixture.homeTeamId == session.team.id;
          fixture.record(home ? 2 : 0, home ? 0 : 2);
        }
      }
    }
    final winner = CupService.winnerOf(season, faCup);
    expect(winner, session.team.id);

    await pumpScreen(tester, session, db);
    expect(find.textContaining('Champions'), findsWidgets);
  });
}
