import 'dart:io';
import 'dart:math';

import 'package:football_manager_sim/core/models/fixture.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/transfer.dart';
import 'package:football_manager_sim/core/services/transfer_market_service.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';
import 'package:football_manager_sim/screens/transfer_market/transfer_market_screen.dart';
import 'package:football_manager_sim/ui/ui.dart';

import '../helpers/test_hive.dart';

void main() {
  late Directory storageDir;

  setUpAll(() async {
    storageDir = await initTestHive('fms_transfer_hub');
  });

  tearDownAll(() async {
    await disposeTestHive(storageDir);
  });

  Future<CareerSession> pumpHub(WidgetTester tester) async {
    final db = stubLeagueDatabase(10);
    // Every player has a long contract, so no row is a free agent and a bid
    // actually has to move money.
    for (final club in db.teams) {
      for (final player in club.squad) {
        player.contractExpiry = DateTime(2030, 6, 30);
      }
    }
    // Same repair the career start does, so wages and reputation are set.
    TransferMarketService().backfillTransferData(db.teams, 2026);
    final team = db.teams.first;
    team.transferBudget = 200000000;
    final session = CareerSession(
      manager: Manager(
        name: 'Boss',
        age: 40,
        nationality: 'Spain',
        teamId: team.id,
      ),
      team: team,
      season: SeasonState(
        leagueId: 'test_league',
        currentMatchday: 0,
        currentYear: 2026,
        isPreSeason: false,
        records: {for (var c = 0; c < 10; c++) 'club_$c': LeagueRecord()},
        rounds: buildRounds(
          [for (var c = 0; c < 10; c++) 'club_$c'],
          rng: Random(1),
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerDatabaseProvider.overrideWith((ref) async => db),
          careerSessionProvider.overrideWith((ref) => session),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const TransferMarketScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  Finder dialogTextField() => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );

  testWidgets('an accepted bid walks through fee, terms and a signing',
      (tester) async {
    final session = await pumpHub(tester);

    expect(find.text('Transfer Hub'), findsOneWidget);
    expect(find.textContaining('Summer window'), findsOneWidget);
    expect(find.text('Market'), findsOneWidget);
    expect(find.text('Talks'), findsOneWidget);
    expect(find.text('News'), findsOneWidget);

    final budgetBefore = session.team.transferBudget;
    // The market rows expose the asking price, not a hidden formula price.
    expect(find.textContaining('€'), findsWidgets);

    await tester.tap(find.byIcon(Icons.gavel).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Bid for'), findsOneWidget);
    expect(find.textContaining('want'), findsWidgets);

    // The dialog is prefilled with the asking price, so submitting as-is is
    // the "pay what they want" path.
    await tester.tap(find.text('Send bid'));
    await tester.pumpAndSettle();

    expect(find.text('Fee agreed'), findsOneWidget);
    await tester.tap(find.text('Discuss terms'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Terms for'), findsOneWidget);
    expect(find.textContaining('reputation'), findsWidgets);

    await tester.tap(find.text('Offer contract'));
    await tester.pumpAndSettle();

    expect(session.team.transferBudget, lessThan(budgetBefore));
    expect(
      session.transferDesk.negotiations.any(
        (n) => n.stage == DealStage.completed,
      ),
      isTrue,
    );

    await tester.tap(find.text('News'));
    await tester.pumpAndSettle();
    expect(find.textContaining('signs for'), findsOneWidget);
  });

  testWidgets('a lowball is countered and shows in Talks', (tester) async {
    final session = await pumpHub(tester);

    await tester.tap(find.byIcon(Icons.gavel).first);
    await tester.pumpAndSettle();
    await tester.enterText(dialogTextField(), '1');
    await tester.tap(find.text('Send bid'));
    await tester.pumpAndSettle();

    expect(find.text('Bid rejected'), findsOneWidget);
    final message = tester
        .widget<Text>(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('They want'),
        ))
        .data!;
    expect(message, contains('€'));
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Talks').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Round 1/3'), findsOneWidget);
    expect(find.textContaining('Accept €'), findsOneWidget);
    expect(find.text('Walk away'), findsOneWidget);

    final negotiation = session.transferDesk.negotiations.single;
    expect(negotiation.counterOffer, negotiation.askingPrice);
  });

  testWidgets('My Players lists a squad player for offers', (tester) async {
    final session = await pumpHub(tester);
    final player = session.team.squad.first;

    await tester.tap(find.text('My Players'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Contract to'), findsWidgets);

    await tester.tap(find.byIcon(Icons.sell_outlined).first);
    await tester.pumpAndSettle();

    expect(transferListingOf(player).$1, isTrue);
    expect(find.textContaining('listed'), findsWidgets);
    expect(find.text('Offers'), findsOneWidget);
  });
}
