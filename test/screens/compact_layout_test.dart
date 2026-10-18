import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/providers/data_providers.dart';
import 'package:football_manager_sim/core/models/youth_player.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/screens/career/career_dashboard_screen.dart';
import 'package:football_manager_sim/screens/league_table/league_table_screen.dart';
import 'package:football_manager_sim/screens/new_career/new_career_screen.dart';
import 'package:football_manager_sim/screens/team_management/team_management_screen.dart';
import 'package:football_manager_sim/screens/transfer_market/transfer_market_screen.dart';
import 'package:football_manager_sim/ui/ui.dart';

import '../helpers/test_hive.dart';

/// The narrowest phone the app claims to support.
const Size kNarrowPhone = Size(360, 640);

/// A season with a real schedule plus the supplied table.
SeasonState _seasonWithRecords(Map<String, LeagueRecord> records) {
  final ids = records.keys.toList();
  return SeasonState(
    leagueId: 'test_league',
    currentMatchday: 12,
    currentYear: 2026,
    isPreSeason: false,
    records: records,
    rounds: buildRounds(ids, rng: Random(2)),
  );
}

CareerSession _session({SeasonState? season}) {
  final db = stubPlayerDatabase();
  final team = db.teams.first;
  final youth = YouthPlayer(
    name: 'Kai Vega',
    age: 17,
    potential: 88,
    currentStats: 61,
    position: 'ST',
    nationality: 'Spain',
    random: Random(11),
  );
  youth.hiddenAttributes['keyAttributes'] = {
    for (final n in youth.keyAttributeNames) n: 74,
  };

  final session = CareerSession(
    manager:
        Manager(name: 'Boss', age: 40, nationality: 'Spain', teamId: team.id),
    team: team,
    season: season ??
        SeasonState(
          leagueId: team.leagueId,
          currentMatchday: 0,
          currentYear: 2026,
          isPreSeason: false,
          records: {team.id: LeagueRecord(), 'rival_fc': LeagueRecord()},
          rounds: buildRounds([team.id, 'rival_fc'], rng: Random(1)),
        ),
  );
  session.youthPlayers.add(youth);
  session.userResults.addAll(const [3, 3, 1, 0]);
  return session;
}

void main() {
  late Directory storageDir;

  setUpAll(() async {
    storageDir = await initTestHive('fms_compact_layout');
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

  /// Same as [pumpAtNarrow] but with a caller-supplied career, so a test can
  /// put the season into a particular state.
  Future<void> pumpSessionAtNarrow(
    WidgetTester tester,
    CareerSession session,
    Widget child, {
    PlayerDatabase? db,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (db != null)
            playerDatabaseProvider.overrideWith((ref) async => db)
          else
            ...stubDatabaseOverrides(),
          careerSessionProvider.overrideWith((ref) => session),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: child),
      ),
    );
  }

  Future<void> pumpAtNarrow(WidgetTester tester, Widget child) async {
    await pumpSessionAtNarrow(tester, _session(), child);
  }

  /// Taps a tab and waits for the page transition to finish. Both squad tab
  /// bars fill the width, so every label is on screen and a direct tap is
  /// safe. (Calling `ensureVisible` first would walk up to the surrounding
  /// `TabBarView` and scroll the page itself.)
  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('Home fits a 360 dp phone', (tester) async {
    await pumpAtNarrow(tester, const CareerDashboardScreen());
    await tester.pump();

    expect(find.text('Play match'), findsOneWidget);
    // The four season numbers live on one strip; every label must fit.
    for (final label in ['POS', 'PTS', 'W-D-L', 'BUDGET']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('the finances sheet fits a 360 dp phone', (tester) async {
    final session = _session();
    await pumpSessionAtNarrow(tester, session, const CareerDashboardScreen());
    await tester.pump();

    // The Fixtures button pair lives on the opponent preview sheet.
    final opponentId = session.season
        .currentFixtureFor(session.team.id)!
        .opponentOf(session.team.id)!;
    final opponent = stubPlayerDatabase()
        .teams
        .firstWhere((t) => t.id == opponentId);
    await tester.tap(find.text(opponent.name).first);
    await tester.pumpAndSettle();
    expect(find.text('League table'), findsOneWidget);

    await tester.ensureVisible(find.text('Finances'));
    await tester.tap(find.text('Finances'));
    await tester.pumpAndSettle();

    expect(find.text('Club finances'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Transfer budget'), findsOneWidget);
    expect(find.text('Gate receipts'), findsOneWidget);
    expect(find.text('Broadcast money'), findsOneWidget);
    // A RenderFlex overflow inside the sheet fails the test here.
  });

  testWidgets('Squad screen fits and opens every tab', (tester) async {
    await pumpAtNarrow(tester, const TeamManagementScreen());
    await tester.pump();

    expect(find.text('16 of 16 players'), findsOneWidget);

    for (final label in ['Transfers', 'Tactics', 'Youth']) {
      await openTab(tester, label);
      expect(tester.takeException(), isNull, reason: 'tab "$label" overflowed');
    }
  });

  testWidgets('Squad tabs share the width evenly', (tester) async {
    await pumpAtNarrow(tester, const TeamManagementScreen());
    await tester.pump();

    final barFinder = find.byType(TabBar).first;
    expect(tester.widget<TabBar>(barFinder).isScrollable, isFalse,
        reason: 'the four tabs must fill the width, not hug the left edge');

    // In a fill bar each tab owns one quarter; its centred label must sit at
    // the middle of that quarter (1/8, 3/8, 5/8, 7/8 across the bar).
    final barRect = tester.getRect(barFinder);
    final centres = [
      for (final label in ['Squad', 'Transfers', 'Tactics', 'Youth'])
        tester.getCenter(find.text(label)).dx,
    ]..sort();
    for (var i = 0; i < centres.length; i++) {
      expect(
        centres[i],
        closeTo(barRect.left + barRect.width * (2 * i + 1) / 8, 2.0),
        reason: 'tab ${i + 1} must sit in its own quarter of the bar',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Squad Transfers tab shows the market, not a dead-end button',
      (tester) async {
    await pumpAtNarrow(tester, const TeamManagementScreen());
    await tester.pump();
    await openTab(tester, 'Transfers');

    expect(find.text('Open Transfer Hub'), findsNothing,
        reason: 'the tab itself is the market');
    expect(find.text('Transfer budget'), findsOneWidget);
    expect(find.text('Away 15'), findsOneWidget,
        reason: 'the strongest signable player is listed in the market');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tactics renders the formation preview and category tabs',
      (tester) async {
    await pumpAtNarrow(tester, const TeamManagementScreen());
    await tester.pump();
    await openTab(tester, 'Tactics');

    expect(find.text('4-4-2'), findsOneWidget);
    expect(find.text('Approach'), findsOneWidget);

    await openTab(tester, 'Transitions');
    expect(find.text('Offside trap'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Youth academy renders the prospect card', (tester) async {
    await pumpAtNarrow(tester, const TeamManagementScreen());
    await tester.pump();
    await openTab(tester, 'Youth');

    expect(find.text('Kai Vega'), findsOneWidget);
    expect(find.text('First-team readiness'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Transfer Hub fits and opens every tab', (tester) async {
    await pumpAtNarrow(tester, const TransferMarketScreen());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Transfer Hub'), findsOneWidget);
    for (final label in ['Shortlist', 'Offers', 'My Players']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('New Career lists leagues and clubs without overflow',
      (tester) async {
    await pumpAtNarrow(tester, const NewCareerScreen());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('MANAGER'), findsOneWidget);
    expect(find.text('Test League'), findsOneWidget);
    // The club list sits below the fold on a 360 dp phone: scroll to it.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -320));
    await tester.pumpAndSettle();
    expect(find.text('Test FC'), findsOneWidget);
    // The CTA stays disabled until a club is chosen.
    final cta = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start Career'),
    );
    expect(cta.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('League table fits a 360 dp phone', (tester) async {
    // Real numbers so the played/GD/points columns are all filled.
    final records = <String, LeagueRecord>{};
    for (var i = 0; i < 6; i++) {
      final won = 5 + i % 3;
      final drawn = i % 2;
      records['club_$i'] = LeagueRecord(
        played: 12,
        won: won,
        drawn: drawn,
        lost: 12 - won - drawn,
        goalsFor: 18 - i,
        goalsAgainst: 14 + i,
      );
    }
    final session = _session(season: _seasonWithRecords(records));
    final league = stubLeagueDatabase(6);

    await pumpSessionAtNarrow(tester, session, const LeagueTableScreen(),
        db: league);
    await tester.pump();

    expect(find.text('Pts'), findsOneWidget);
    expect(find.text('GD'), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      expect(find.text('Club $i'), findsOneWidget, reason: 'Club $i');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home shows the winter break state without overflow',
      (tester) async {
    // A two-club season has two rounds, so the break falls on round 1.
    final session = _session(
      season: SeasonState(
        leagueId: 'test_league',
        currentMatchday: 1,
        currentYear: 2026,
        isPreSeason: false,
        isWinterBreak: true,
        records: {'test_fc': LeagueRecord(), 'rival_fc': LeagueRecord()},
        rounds: buildRounds(['test_fc', 'rival_fc'], rng: Random(1)),
      ),
    );

    await pumpSessionAtNarrow(tester, session, const CareerDashboardScreen());
    await tester.pump();

    expect(find.text('Resume season'), findsOneWidget);
    expect(find.textContaining('Winter break'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home explains a league with no schedule', (tester) async {
    // A league can lose enough clubs to the squad filter that no round-robin
    // can be built; the hero must not show a dead "Play match" button.
    final session = _session(
      season: SeasonState(
        leagueId: 'test_league',
        currentYear: 2026,
        isPreSeason: false,
        records: {'test_fc': LeagueRecord()},
      ),
    );

    await pumpSessionAtNarrow(tester, session, const CareerDashboardScreen());
    await tester.pump();

    expect(find.text('No fixtures'), findsOneWidget);
    expect(find.textContaining('No schedule could be built'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'No fixtures'),
    );
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
