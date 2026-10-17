import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/player.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/transfer.dart';
import 'package:football_manager_sim/core/services/transfer_market_service.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';
import 'package:football_manager_sim/providers/transfer_market_actions.dart';

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

SeasonState _season(int matchday) => SeasonState(
      leagueId: 'test_league',
      currentMatchday: matchday,
      currentYear: 2026,
      isPreSeason: false,
      records: {for (var c = 0; c < 10; c++) 'club_$c': LeagueRecord()},
      rounds: buildRounds(
        [for (var c = 0; c < 10; c++) 'club_$c'],
        rng: Random(1),
      ),
    );

CareerSession _sessionFor(PlayerDatabase db, {int matchday = 0}) {
  final team = db.teams.first;
  return CareerSession(
    manager: Manager(
      name: 'Boss',
      age: 40,
      nationality: 'Spain',
      teamId: team.id,
    ),
    team: team,
    season: _season(matchday),
  );
}

Future<ProviderContainer> _containerFor(
  PlayerDatabase db,
  CareerSession session,
) async {
  final container = ProviderContainer(
    overrides: [
      playerDatabaseProvider.overrideWith((ref) async => db),
      careerSessionProvider.overrideWith((ref) => session),
    ],
  );
  addTearDown(container.dispose);
  // The database is a FutureProvider: read it before the market runs, or
  // every seller lookup and incoming bid sees a null database.
  await container.read(playerDatabaseProvider.future);
  return container;
}

/// A sellable target from a rival club with a long contract, so he is neither
/// a free agent nor a rival-magnet (the stub league has no elite clubs).
Player _target(PlayerDatabase db) {
  final seller = db.teams[1];
  final player = [...seller.squad]
      .where((p) => p.primaryPosition != 'GK')
      .reduce((a, b) => a.ovr >= b.ovr ? a : b);
  player
    ..contractExpiry = DateTime(2030, 6, 30)
    ..weeklyWage = 20000;
  return player;
}

void main() {
  late Directory storageDir;

  setUpAll(() async {
    storageDir = await initTestHive('fms_transfer_market');
  });

  tearDownAll(() async {
    await disposeTestHive(storageDir);
  });

  testWidgets('a bid is countered, accepted, then terms complete the signing',
      (tester) async {
    final db = stubLeagueDatabase(10);
    final session = _sessionFor(db);
    final container = await _containerFor(db, session);
    final target = _target(db);
    final budgetBefore = session.team.transferBudget;

    await _run(tester, container, (ref) => startTransferTalk(ref, target));
    final opening = session.transferDesk.forPlayer(target.id)!;
    expect(opening.askingPrice, greaterThan(0));
    expect(opening.stage, DealStage.bidding);

    await _run(tester, container, (ref) => submitBid(ref, target, 1));
    final countered = session.transferDesk.forPlayer(target.id)!;
    expect(countered.counterOffer, opening.askingPrice,
        reason: 'a lowball is countered at the full asking price');
    expect(countered.round, 1);

    await _run(tester, container, (ref) => acceptCounterOffer(ref, target));
    final agreed = session.transferDesk.forPlayer(target.id)!;
    expect(agreed.stage, DealStage.feeAgreed);
    expect(agreed.agreedFee, opening.askingPrice);

    await _run(
      tester,
      container,
      (ref) => offerPersonalTerms(
        ref,
        target,
        wage: agreed.wageDemand,
        bonus: 0,
        years: 4,
        role: 'First Team',
      ),
    );

    expect(session.team.squad.any((p) => p.id == target.id), isTrue,
        reason: 'the signing must actually move the player');
    expect(session.team.transferBudget, lessThan(budgetBefore));
    expect(session.transferDesk.forPlayer(target.id)!.stage,
        DealStage.completed);
    expect(
      session.transferDesk.news.any((n) => n.type == 'signing'),
      isTrue,
    );
    expect(target.contractExpiry?.year, 2030);
    expect(target.weeklyWage, greaterThan(0));
  });

  testWidgets('personal terms can be rejected with the agent demand',
      (tester) async {
    final db = stubLeagueDatabase(10);
    final session = _sessionFor(db);
    final container = await _containerFor(db, session);
    final target = _target(db);

    await _run(tester, container, (ref) => startTransferTalk(ref, target));
    final asking = session.transferDesk.forPlayer(target.id)!.askingPrice;
    await _run(tester, container, (ref) => submitBid(ref, target, asking));
    expect(session.transferDesk.forPlayer(target.id)!.stage,
        DealStage.feeAgreed);

    await _run(
      tester,
      container,
      (ref) => offerPersonalTerms(
        ref,
        target,
        wage: 1000,
        bonus: 0,
        years: 3,
        role: 'First Team',
      ),
    );

    expect(session.team.squad.any((p) => p.id == target.id), isFalse);
    final negotiation = session.transferDesk.forPlayer(target.id)!;
    expect(negotiation.stage, DealStage.feeAgreed,
        reason: 'the fee stays agreed while the player haggles');
    expect(negotiation.wageDemand, greaterThan(1000));
    expect(negotiation.message, contains('agent'));
  });

  testWidgets('the window shuts the market to everyone but free agents',
      (tester) async {
    final db = stubLeagueDatabase(10);
    final session = _sessionFor(db, matchday: 15);
    final container = await _containerFor(db, session);
    final target = _target(db);

    await _run(tester, container, (ref) => startTransferTalk(ref, target));

    expect(session.transferDesk.forPlayer(target.id), isNull);
    expect(container.read(transferBlockReasonProvider), contains('window'));
  });

  testWidgets('three bids collapse the deal', (tester) async {
    final db = stubLeagueDatabase(10);
    final session = _sessionFor(db);
    final container = await _containerFor(db, session);
    final target = _target(db);

    await _run(tester, container, (ref) => startTransferTalk(ref, target));
    final asking = session.transferDesk.forPlayer(target.id)!.askingPrice;
    // A credible-but-short bid costs a round of patience each time, so the
    // third bid is the one that ends it.
    for (var i = 0; i < 3; i++) {
      await _run(
        tester,
        container,
        (ref) => submitBid(ref, target, (asking * 0.9).round()),
      );
    }

    final negotiation = session.transferDesk.forPlayer(target.id)!;
    expect(negotiation.stage, DealStage.collapsed);
    expect(negotiation.patience, 0);
    expect(negotiation.round, 3);
  });

  testWidgets('a listed player attracts a bid that can be accepted',
      (tester) async {
    final db = stubLeagueDatabase(10);
    final session = _sessionFor(db);
    final container = await _containerFor(db, session);
    final squad = session.team.squad;
    // The stub club starts at the 16-player minimum, so add cover first:
    // otherwise the squad-size rule blocks every sale.
    squad.addAll([
      stubPlayer(id: 9001, name: 'Extra A', team: session.team.name),
      stubPlayer(id: 9002, name: 'Extra B', team: session.team.name),
    ]);
    for (final player in squad) {
      player.hiddenAttributes['transferListed'] = true;
    }
    final budgetBefore = session.team.transferBudget;

    await _run(tester, container, (ref) => advanceTransferDesk(ref, session));

    expect(session.transferDesk.incomingBids, isNotEmpty,
        reason: 'a listed squad should draw at least one offer');
    final bid = session.transferDesk.incomingBids.first;
    expect(bid.fee, greaterThan(0));

    await _run(tester, container, (ref) => acceptIncomingBid(ref, bid));

    expect(session.team.squad.any((p) => p.id == bid.playerId), isFalse);
    expect(session.team.transferBudget, greaterThan(budgetBefore));
    expect(
      session.transferDesk.incomingBids.any((b) => b.playerId == bid.playerId),
      isFalse,
      reason: 'the accepted bid is settled; other offers stay live',
    );
  });

  testWidgets('a rival signs the player if the manager stalls',
      (tester) async {
    final db = stubLeagueDatabase(10);
    final session = _sessionFor(db, matchday: 2);
    final container = await _containerFor(db, session);
    final target = _target(db);
    session.transferDesk.replace(TransferNegotiation(
      playerId: target.id,
      playerName: target.name,
      sellerClub: target.currentTeam,
      askingPrice: 5000000,
      reservationPrice: 4000000,
      stage: DealStage.bidding,
      round: 1,
      patience: 2,
      lastOffer: 3000000,
      counterOffer: 4500000,
      startedMatchday: 0,
      rivalDeadlineMatchday: 2,
      wageDemand: 30000,
      requiredReputation: 70,
      message: 'They want more.',
      rivalClub: 'Club 4',
    ));

    await _run(tester, container, (ref) => advanceTransferDesk(ref, session));

    final negotiation = session.transferDesk.forPlayer(target.id)!;
    expect(negotiation.stage, DealStage.hijacked);
    expect(negotiation.message, contains('Club 4'));
    expect(session.transferDesk.news.any((n) => n.type == 'hijack'), isTrue);
  });

  testWidgets('the window closing kills unfinished talks', (tester) async {
    final db = stubLeagueDatabase(10);
    final session = _sessionFor(db, matchday: 15);
    final container = await _containerFor(db, session);
    final target = _target(db);
    session.transferDesk.replace(TransferNegotiation(
      playerId: target.id,
      playerName: target.name,
      sellerClub: target.currentTeam,
      askingPrice: 5000000,
      reservationPrice: 4000000,
      stage: DealStage.feeAgreed,
      round: 1,
      patience: 2,
      lastOffer: 5000000,
      counterOffer: 0,
      startedMatchday: 14,
      rivalDeadlineMatchday: -1,
      wageDemand: 30000,
      requiredReputation: 70,
      message: 'Fee agreed.',
      agreedFee: 5000000,
    ));

    await _run(tester, container, (ref) => advanceTransferDesk(ref, session));

    expect(session.transferDesk.forPlayer(target.id)!.stage,
        DealStage.collapsed);
  });

  testWidgets('a shut window still allows free agents', (tester) async {
    final db = stubLeagueDatabase(10);
    final session = _sessionFor(db, matchday: 15);
    final container = await _containerFor(db, session);
    final freeAgent = db.teams[2].squad.first
      ..contractExpiry = DateTime(2026, 6, 30);
    final budgetBefore = session.team.transferBudget;
    expect(TransferMarketService().isFreeAgent(freeAgent, 2026), isTrue);

    await _run(tester, container, (ref) => submitBid(ref, freeAgent, 0));
    final negotiation = session.transferDesk.forPlayer(freeAgent.id)!;
    expect(negotiation.stage, DealStage.feeAgreed);

    await _run(
      tester,
      container,
      (ref) => offerPersonalTerms(
        ref,
        freeAgent,
        wage: negotiation.wageDemand,
        bonus: 0,
        years: 2,
        role: 'First Team',
      ),
    );

    expect(session.team.squad.any((p) => p.id == freeAgent.id), isTrue);
    expect(session.team.transferBudget, budgetBefore,
        reason: 'a free agent costs no fee');
    expect(
      session.transferDesk.news.any((n) => n.type == 'signing'),
      isTrue,
    );
  });

  testWidgets('the negotiation survives a JSON round trip', (tester) async {
    final db = stubLeagueDatabase(10);
    final session = _sessionFor(db);
    final target = _target(db);
    const asking = 12300000;
    final negotiation = TransferNegotiation(
      playerId: target.id,
      playerName: target.name,
      sellerClub: target.currentTeam,
      askingPrice: asking,
      reservationPrice: 10000000,
      stage: DealStage.bidding,
      round: 1,
      patience: 2,
      lastOffer: 8000000,
      counterOffer: 11000000,
      startedMatchday: 1,
      rivalDeadlineMatchday: 3,
      wageDemand: 45000,
      requiredReputation: 74,
      message: 'They want more.',
      rivalClub: 'Club 5',
    );
    session.transferDesk.replace(negotiation);

    final restored =
        TransferDesk.fromJson(session.transferDesk.toJson());
    final copy = restored.forPlayer(target.id)!;
    expect(copy.askingPrice, asking);
    expect(copy.reservationPrice, 10000000);
    expect(copy.counterOffer, 11000000);
    expect(copy.rivalClub, 'Club 5');
    expect(copy.stage, DealStage.bidding);
  });
}
