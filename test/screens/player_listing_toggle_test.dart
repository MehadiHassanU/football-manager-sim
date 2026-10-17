import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';
import 'package:football_manager_sim/screens/team_management/team_management_screen.dart';
import 'package:football_manager_sim/ui/ui.dart';

import '../helpers/test_hive.dart';

/// The switches used to flip the player's hidden attributes but never the
/// widget, because the session was re-emitted as the same instance.
void main() {
  late Directory storageDir;

  setUpAll(() async {
    storageDir = await initTestHive('fms_listing_toggle');
  });

  tearDownAll(() async {
    await disposeTestHive(storageDir);
  });

  testWidgets('transfer and loan switches update on screen', (tester) async {
    final db = stubPlayerDatabase(random: Random(6));
    final team = db.teams.first;
    final session = CareerSession(
      manager: Manager(name: 'Boss', age: 40, nationality: 'Spain'),
      team: team,
      season: SeasonState(leagueId: team.leagueId),
    );
    // Sorted by OVR descending, so the top-rated player is listed first.
    final player =
        ([...team.squad]..sort((a, b) => b.ovr.compareTo(a.ovr))).first;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerDatabaseProvider.overrideWith((ref) async => db),
          careerSessionProvider.overrideWith((ref) => session),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const TeamManagementScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text(player.name));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Role & Contract'));
    await tester.pumpAndSettle();

    SwitchListTile listedTile() => tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'Transfer listed'),
        );

    expect(listedTile().value, isFalse);

    await tester.ensureVisible(find.text('Transfer listed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transfer listed'));
    await tester.pumpAndSettle();

    expect(transferListingOf(player).$1, isTrue);
    expect(listedTile().value, isTrue,
        reason: 'the switch must show the state it just wrote');
    expect(find.textContaining('Asking'), findsOneWidget,
        reason: 'listing a player surfaces the asking price');

    await tester.ensureVisible(find.text('Loan listed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Loan listed'));
    await tester.pumpAndSettle();

    expect(loanListingOf(player), isTrue);
    final loanTile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Loan listed'),
    );
    expect(loanTile.value, isTrue);
    expect(tester.takeException(), isNull);
  });
}
