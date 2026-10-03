import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/youth_player.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/screens/career/career_dashboard_screen.dart';
import 'package:football_manager_sim/screens/new_career/new_career_screen.dart';
import 'package:football_manager_sim/screens/team_management/team_management_screen.dart';
import 'package:football_manager_sim/screens/transfer_market/transfer_market_screen.dart';
import 'package:football_manager_sim/ui/ui.dart';

import '../helpers/test_hive.dart';

/// The narrowest phone the app claims to support.
const Size kNarrowPhone = Size(360, 640);

CareerSession _session() {
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
    season: SeasonState(
      leagueId: team.leagueId,
      currentMatchday: 4,
      totalMatchdays: 38,
      standings: {team.id: 7, 'rival_fc': 4},
      matchdayFixtures: const ['test_fc|rival_fc'],
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

  Future<void> pumpAtNarrow(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...stubDatabaseOverrides(),
          careerSessionProvider.overrideWith((ref) => _session()),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: child),
      ),
    );
  }

  /// Taps a tab and waits for the page transition to finish. The tab bars are
  /// scrollable, so the target may start off-screen on a narrow phone.
  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('Home fits a 360 dp phone', (tester) async {
    await pumpAtNarrow(tester, const CareerDashboardScreen());
    await tester.pump();

    expect(find.text('Play match'), findsOneWidget);
    // Stat labels are upper-cased by [StatCard].
    expect(find.text('BUDGET'), findsOneWidget);
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
}
