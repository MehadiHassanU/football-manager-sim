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

  testWidgets('a deal agreed with the window shut joins when it reopens',
      (tester) async {
    final db = stubLeagueDatabase(10);
    // Matchday 6 is shut: the summer window closes after 3 and the winter one
    // opens on 7 for this 18-round stub schedule.
    final session = _sessionFor(db, matchday: 6);
    final container = await _containerFor(db, session);
    final target = _target(db);
    final seller = target.currentTeam;
    final budgetBefore = session.team.transferBudget;

    expect(TransferWindow.of(session.season).isOpen, isFalse);

    await _run(tester, container, (ref) => startTransferTalk(ref, target));
    final asking = session.transferDesk.forPlayer(target.id)!.askingPrice;
    await _run(tester, container, (ref) => submitBid(ref, target, asking));
    final agreed = session.transferDesk.forPlayer(target.id)!;
    expect(agreed.stage, DealStage.feeAgreed);

    final demand = agreed.wageDemand;
    await _run(
      tester,
      container,
      (ref) => offerPersonalTerms(
        ref,
        target,
        wage: demand,
        bonus: 0,
        years: 4,
        role: 'First Team',
      ),
    );

    // Agreed and paid for, but not registered while the window is shut.
    expect(session.team.squad.any((p) => p.id == target.id), isFalse);
    expect(session.team.transferBudget, budgetBefore - asking,
        reason: 'the fee is committed at agreement');
    expect(session.transferDesk.pendingSignings, hasLength(1));
    final pending = session.transferDesk.pendingSignings.single;
    expect(pending.playerId, target.id);
    expect(pending.fromClub, seller);
    expect(pending.fee, asking);
    expect(pending.committed, asking);
    expect(pending.wage, demand);
    expect(session.transferDesk.forPlayer(target.id)!.stage,
        DealStage.pendingRegistration);
    expect(session.transferDesk.ledger, isEmpty,
        reason: 'the move is recorded when he actually arrives');
    expect(session.transferDesk.news.first.title, contains('agrees to join'));

    // The agreed deal cannot be negotiated (or paid for) a second time.
    await _run(tester, container, (ref) => startTransferTalk(ref, target));
    expect(container.read(transferBlockReasonProvider),
        contains('already agreed'));
    expect(session.transferDesk.pendingSignings, hasLength(1));

    // Matchday 7 reopens the winter window: the registration goes through.
    final reopened = CareerSession(
      manager: session.manager,
      team: session.team,
      season: _season(7),
      transferDesk: session.transferDesk,
    );
    expect(TransferWindow.of(reopened.season).isOpen, isTrue);

    await _run(tester, container, (ref) => advanceTransferDesk(ref, reopened));

    expect(session.team.squad.any((p) => p.id == target.id), isTrue);
    expect(session.transferDesk.pendingSignings, isEmpty);
    expect(session.team.transferBudget, budgetBefore - asking,
        reason: 'the committed fee must not be charged twice');
    final move = session.transferDesk.ledger.single;
    expect(move.playerId, target.id);
    expect(move.toClub, session.team.name);
    expect(move.matchday, 7);
    expect(target.currentTeam, session.team.name);
    expect(target.weeklyWage, demand);
    expect(target.contractExpiry?.year, 2030);
    expect(
      db.teams
          .firstWhere((t) => t.name == seller)
          .squad
          .any((p) => p.id == target.id),
      isFalse,
      reason: 'the selling club lets him go on registration',
    );
    expect(
      session.transferDesk.news.any((n) => n.title.contains('registers')),
      isTrue,
    );
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

  testWidgets('pending signings survive the desk JSON', (tester) async {
    final desk = TransferDesk(pendingSignings: [
      const PendingSigning(
        playerId: 42,
        playerName: 'Kai Vega',
        fromClub: 'Club 1',
        fee: 5000000,
        bonus: 500000,
        wage: 30000,
        contractYears: 4,
        role: 'First Team',
        agreedYear: 2026,
        agreedMatchday: 6,
      ),
    ]);

    final restored = TransferDesk.fromJson(desk.toJson());

    expect(restored.pendingSignings, hasLength(1));
    final pending = restored.pendingSignings.single;
    expect(pending.playerId, 42);
    expect(pending.playerName, 'Kai Vega');
    expect(pending.fromClub, 'Club 1');
    expect(pending.committed, 5500000);
    expect(pending.wage, 30000);
    expect(pending.contractYears, 4);
    expect(pending.agreedMatchday, 6);
  });

  testWidgets('the ledger replays a signing onto a fresh database',
      (tester) async {
    final db = stubLeagueDatabase(10);
    final session = _sessionFor(db);
    final container = await _containerFor(db, session);
    final target = _target(db);
    final seller = target.currentTeam;

    // A free agent: no fee to negotiate, straight to terms.
    target.contractExpiry = DateTime(2026, 6, 30);
    final demand = TransferMarketService().wageDemand(target, session.team);
    await _run(tester, container, (ref) => submitBid(ref, target, 0));
    await _run(
      tester,
      container,
      (ref) => offerPersonalTerms(
        ref,
        target,
        wage: demand,
        bonus: 0,
        years: 3,
        role: 'First Team',
      ),
    );

    expect(session.team.squad.any((p) => p.id == target.id), isTrue);
    expect(session.transferDesk.ledger, isNotEmpty);

    // Restart: every squad comes back from the CSV, then the ledger replays.
    final fresh = stubLeagueDatabase(10);
    TransferMarketService().applyTransferLedger(
      players: fresh.players,
      teams: fresh.teams,
      moves: session.transferDesk.ledger,
      userClub: session.team.name,
    );

    final replayed = fresh.players.firstWhere((p) => p.id == target.id);
    expect(replayed.currentTeam, session.team.name);
    final oldClub = fresh.teams.firstWhere((t) => t.name == seller);
    expect(oldClub.squad.any((p) => p.id == target.id), isFalse,
        reason: 'the selling club must not keep him after a reload');

    // Replaying again changes nothing.
    TransferMarketService().applyTransferLedger(
      players: fresh.players,
      teams: fresh.teams,
      moves: session.transferDesk.ledger,
      userClub: session.team.name,
    );
    final oldClub2 = fresh.teams.firstWhere((t) => t.name == seller);
    expect(oldClub2.squad.where((p) => p.id == target.id), isEmpty);
  });

  testWidgets('the ledger moves a sold player into the buyer squad',
      (tester) async {
    final db = stubLeagueDatabase(10);
    final session = _sessionFor(db);
    final container = await _containerFor(db, session);
    final squad = session.team.squad;
    squad.addAll([
      stubPlayer(id: 9001, name: 'Extra A', team: session.team.name),
      stubPlayer(id: 9002, name: 'Extra B', team: session.team.name),
    ]);
    for (final player in squad) {
      player.hiddenAttributes['transferListed'] = true;
    }

    await _run(tester, container, (ref) => advanceTransferDesk(ref, session));
    final bid = session.transferDesk.incomingBids.first;
    await _run(tester, container, (ref) => acceptIncomingBid(ref, bid));

    final move = session.transferDesk.ledger
        .firstWhere((m) => m.playerId == bid.playerId);
    expect(move.toClub, bid.club);
    expect(move.fee, bid.fee);

    final fresh = stubLeagueDatabase(10);
    TransferMarketService().applyTransferLedger(
      players: fresh.players,
      teams: fresh.teams,
      moves: session.transferDesk.ledger,
      userClub: session.team.name,
    );
    final buyer = fresh.teams.firstWhere((t) => t.name == bid.club);
    expect(buyer.squad.any((p) => p.id == bid.playerId), isTrue,
        reason: 'the buyer must actually own him after a reload');
    final replayed = fresh.players.firstWhere((p) => p.id == bid.playerId);
    expect(replayed.currentTeam, bid.club);
  });

  testWidgets('a hijack really moves the player to the rival', (tester) async {
    final db = stubLeagueDatabase(10);
    final session = _sessionFor(db, matchday: 2);
    final container = await _containerFor(db, session);
    final target = _target(db);
    final seller = target.currentTeam;
    session.transferDesk.replace(TransferNegotiation(
      playerId: target.id,
      playerName: target.name,
      sellerClub: seller,
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

    expect(target.currentTeam, 'Club 4');
    final rival = db.teams.firstWhere((t) => t.name == 'Club 4');
    expect(rival.squad.any((p) => p.id == target.id), isTrue);
    expect(db.teams.firstWhere((t) => t.name == seller).squad.any(
          (p) => p.id == target.id,
        ),
        isFalse);

    final move = session.transferDesk.ledger
        .firstWhere((m) => m.playerId == target.id);
    expect(move.toClub, 'Club 4');
    expect(move.kind, 'permanent');
  });

  testWidgets('a loaned-out player comes back at the rollover',
      (tester) async {
    final db = stubLeagueDatabase(10);
    final session = _sessionFor(db);
    final container = await _containerFor(db, session);
    final squad = session.team.squad;
    squad.addAll([
      stubPlayer(id: 9001, name: 'Extra A', team: session.team.name),
      stubPlayer(id: 9002, name: 'Extra B', team: session.team.name),
    ]);
    for (final player in squad) {
      player
        ..hiddenAttributes['loanListed'] = true
        // The stub squads are wage-less, so set a real wage: a loaned-out
        // player's parent club keeps paying its share of it.
        ..weeklyWage = 20000;
    }
    final before = {for (final p in squad) p.id: p.weeklyWage};

    await _run(tester, container, (ref) => advanceTransferDesk(ref, session));
    final offer = session.transferDesk.incomingBids.firstWhere(
      (b) => b.isLoan,
      orElse: () => throw StateError('expected a loan offer'),
    );
    await _run(tester, container, (ref) => acceptLoanOffer(ref, offer));

    expect(session.team.squad.any((p) => p.id == offer.playerId), isFalse,
        reason: 'he is playing elsewhere for the season');
    expect(session.transferDesk.loans, hasLength(1));
    expect(session.team.loanedOutWages, greaterThan(0),
        reason: 'the club still pays its share of his wage');

    // Season end: everyone comes home.
    final loanedOut = session.transferDesk.loans.single;
    final postSeason = _sessionFor(db).season;
    final ending = CareerSession(
      manager: session.manager,
      team: session.team,
      season: SeasonState(
        leagueId: 'test_league',
        currentMatchday: 18,
        currentYear: postSeason.currentYear,
        isPreSeason: false,
        records: postSeason.records,
        rounds: postSeason.rounds,
      ),
      transferDesk: session.transferDesk,
    );
    final nextContainer = await _containerFor(db, ending);
    await _run(tester, nextContainer, (ref) => rollIntoNextSeason(ref));

    final returned = ending.team.squad
        .firstWhere((p) => p.id == loanedOut.playerId);
    expect(returned.weeklyWage, before[loanedOut.playerId]);
    expect(ending.transferDesk.loans, isEmpty);
    expect(ending.team.loanedOutWages, 0);
  });

  testWidgets('a borrowed player goes home at the rollover', (tester) async {
    final db = stubLeagueDatabase(10);
    final session = _sessionFor(db);
    final container = await _containerFor(db, session);
    final owner = db.teams[1];
    // Chosen before the filler arrives, so the target is a real database
    // player rather than the squad padding.
    final target = _target(db)..hiddenAttributes['transferListed'] = true;
    final fullWage = target.weeklyWage;
    // The stub clubs sit at the 16-player minimum, which blocks loans.
    owner.squad.add(stubPlayer(
      id: 9100,
      name: 'Depth',
      team: owner.name,
      ovr: 60,
    ));

    await _run(
      tester,
      container,
      (ref) => offerLoanDeal(ref, target, wageSharePercent: 50),
    );

    expect(session.team.squad.any((p) => p.id == target.id), isTrue);
    expect(target.hiddenAttributes['onLoanFrom'], owner.name);
    expect(target.weeklyWage, fullWage * 0.5,
        reason: 'he only costs the borrowing club its share');
    expect(session.transferDesk.loans, hasLength(1));

    final postSeason = _sessionFor(db).season;
    final ending = CareerSession(
      manager: session.manager,
      team: session.team,
      season: SeasonState(
        leagueId: 'test_league',
        currentMatchday: 18,
        currentYear: postSeason.currentYear,
        isPreSeason: false,
        records: postSeason.records,
        rounds: postSeason.rounds,
      ),
      transferDesk: session.transferDesk,
    );
    final nextContainer = await _containerFor(db, ending);
    await _run(tester, nextContainer, (ref) => rollIntoNextSeason(ref));

    expect(ending.team.squad.any((p) => p.id == target.id), isFalse);
    expect(target.weeklyWage, fullWage);
    expect(target.hiddenAttributes.containsKey('onLoanFrom'), isFalse);
    expect(owner.squad.any((p) => p.id == target.id), isTrue,
        reason: 'he belongs to his parent club again');
  });

  testWidgets('the day after deadline day reports what the window did',
      (tester) async {
    final db = stubLeagueDatabase(10);
    // Matchday 4: the summer window shut after matchday 3.
    final session = _sessionFor(db, matchday: 4);
    final container = await _containerFor(db, session);
    session.transferDesk.recordMove(TransferMove(
      playerId: 4242,
      playerName: 'Marquee Man',
      fromClub: 'Club 3',
      toClub: session.team.name,
      kind: 'permanent',
      fee: 5000000,
      wage: 40000,
      year: 2026,
      matchday: 2,
    ));

    await _run(tester, container, (ref) => advanceTransferDesk(ref, session));

    final summary = session.transferDesk.news
        .firstWhere((n) => n.type == 'summary');
    expect(summary.title, contains('summer window'));
    expect(summary.body, contains('1 signing'));
    expect(summary.body, contains('€5.0M spent'));

    // The same matchday cannot publish the same summary twice.
    await _run(tester, container, (ref) => advanceTransferDesk(ref, session));
    expect(session.transferDesk.news.where((n) => n.type == 'summary'),
        hasLength(1));
  });

  testWidgets('the winter summary counts only the winter business',
      (tester) async {
    final db = stubLeagueDatabase(10);
    // The winter window runs 7-12 in this 18-round league, so matchday 13 is
    // the morning after its deadline.
    final session = _sessionFor(db, matchday: 13);
    final container = await _containerFor(db, session);
    const moves = <(int, int)>[(1, 2), (2, 10)];
    for (final (id, matchday) in moves) {
      session.transferDesk.recordMove(TransferMove(
        playerId: 5000 + id,
        playerName: 'Player $id',
        fromClub: 'Club 3',
        toClub: session.team.name,
        kind: 'permanent',
        fee: 1000000,
        wage: 20000,
        year: 2026,
        matchday: matchday,
      ));
    }

    await _run(tester, container, (ref) => advanceTransferDesk(ref, session));

    final summary =
        session.transferDesk.news.firstWhere((n) => n.type == 'summary');
    expect(summary.title, contains('winter window'));
    expect(summary.body, contains('1 signing'),
        reason: 'the summer signing belongs to the summer summary');
    expect(summary.body, contains('€1.0M spent'));
  });

  testWidgets('a squad at the minimum draws no offers and is told why',
      (tester) async {
    final db = stubLeagueDatabase(10);
    final session = _sessionFor(db);
    final container = await _containerFor(db, session);
    expect(session.team.squad, hasLength(16));
    for (final p in session.team.squad) {
      p..hiddenAttributes['transferListed'] = true
        // Real wages, or the ceiling test above would leak in here.
        ..weeklyWage = 0;
    }

    await _run(tester, container, (ref) => advanceTransferDesk(ref, session));

    expect(session.transferDesk.incomingBids, isEmpty,
        reason: 'an offer nobody can accept is worse than no offer');
    expect(
      session.transferDesk.news.any((n) => n.type == 'minimum'),
      isTrue,
    );

    // With cover added, the offers start arriving again.
    session.team.squad
        .add(stubPlayer(id: 9300, name: 'Cover', team: session.team.name));
    await _run(tester, container, (ref) => advanceTransferDesk(ref, session));
    expect(session.transferDesk.incomingBids, isNotEmpty);
  });

  testWidgets('an offer to loan a player out is refused at the minimum',
      (tester) async {
    final db = stubLeagueDatabase(10);
    final session = _sessionFor(db);
    final container = await _containerFor(db, session);
    final player = session.team.squad.first;
    final bid = IncomingBid(
      playerId: player.id,
      playerName: player.name,
      club: 'Club 4',
      fee: 0,
      matchday: 1,
      kind: 'loan',
      wageSharePercent: 100,
    );

    await _run(tester, container, (ref) => acceptLoanOffer(ref, bid));

    expect(session.transferDesk.loans, isEmpty);
    expect(session.team.squad.any((p) => p.id == player.id), isTrue,
        reason: 'he stays: the squad cannot go below 16');
    expect(container.read(transferBlockReasonProvider), contains('16'));
  });

  testWidgets('a loan is refused when its wage share breaks the ceiling',
      (tester) async {
    final db = stubLeagueDatabase(10);
    final session = _sessionFor(db);
    final container = await _containerFor(db, session);
    final owner = db.teams[1];
    final target = _target(db)..hiddenAttributes['transferListed'] = true;
    owner.squad.add(stubPlayer(
      id: 9200,
      name: 'Depth',
      team: owner.name,
      ovr: 60,
    ));
    // €100 of room against a wage that costs thousands a week.
    session.team.wageBudget = weeklyWageBill(session.team) + 100;

    await _run(
      tester,
      container,
      (ref) => offerLoanDeal(ref, target, wageSharePercent: 100),
    );

    expect(session.team.squad.any((p) => p.id == target.id), isFalse);
    expect(
      container.read(transferBlockReasonProvider),
      contains('wage budget'),
    );

    // With the ceiling raised, the same loan goes through: the block was the
    // ceiling, not the paperwork.
    session.team.wageBudget += target.weeklyWage * 2;
    await _run(
      tester,
      container,
      (ref) => offerLoanDeal(ref, target, wageSharePercent: 100),
    );
    expect(session.team.squad.any((p) => p.id == target.id), isTrue);
  });

  testWidgets('an ignored starter becomes unsettled and then asks to leave',
      (tester) async {
    final db = stubLeagueDatabase(10);
    final session = _sessionFor(db, matchday: 6);
    final container = await _containerFor(db, session);
    final team = session.team;
    team.matchesPlayed = 6;
    final star = ([...team.squad]..sort((a, b) => b.ovr.compareTo(a.ovr)))
        .first;
    for (final p in team.squad) {
      p.minutesPlayed = p.id == star.id ? 0 : 6 * 90;
    }

    await _run(tester, container, (ref) => assessSquadHappiness(ref, session));

    expect(unsettledOf(star), isTrue,
        reason: 'your best player is not getting minutes');
    expect(star.requestedTransfer, isFalse,
        reason: 'a warning comes before the request');
    expect(
      session.transferDesk.news.any(
          (n) => n.type == 'unsettled' && n.title.contains(star.name)),
      isTrue,
    );

    // Still no minutes two matchdays later: he hands in a request, which is
    // what makes the market bring offers for him.
    final later = CareerSession(
      manager: session.manager,
      team: team,
      season: _season(9),
      transferDesk: session.transferDesk,
    );
    await _run(tester, container, (ref) => assessSquadHappiness(ref, later));

    expect(star.requestedTransfer, isTrue);
    expect(session.transferDesk.news.any((n) => n.type == 'request'), isTrue);
  });

  testWidgets('a promise buys patience, and minutes settle him again',
      (tester) async {
    final db = stubLeagueDatabase(10);
    final session = _sessionFor(db, matchday: 6);
    final container = await _containerFor(db, session);
    final team = session.team;
    team.matchesPlayed = 6;
    final star = ([...team.squad]..sort((a, b) => b.ovr.compareTo(a.ovr)))
        .first;
    for (final p in team.squad) {
      p.minutesPlayed = p.id == star.id ? 0 : 6 * 90;
    }

    CareerSession at(int matchday) => CareerSession(
          manager: session.manager,
          team: team,
          season: _season(matchday),
          transferDesk: session.transferDesk,
        );

    await _run(tester, container, (ref) => assessSquadHappiness(ref, session));
    await _run(tester, container, (ref) => promisePlayingTime(ref, star));
    expect(star.hiddenAttributes['minutesPromise'], 6);

    // Two matchdays on the promise is still holding.
    await _run(tester, container, (ref) => assessSquadHappiness(ref, at(8)));
    expect(star.requestedTransfer, isFalse,
        reason: 'a promise buys three matchdays');

    // The promise is broken, so he asks to leave.
    await _run(tester, container, (ref) => assessSquadHappiness(ref, at(9)));
    expect(star.requestedTransfer, isTrue);

    // Minutes arrive at last: the complaint clears and the request is
    // withdrawn, so the story can end well.
    star.minutesPlayed = 9 * 90;
    await _run(tester, container, (ref) => assessSquadHappiness(ref, at(11)));
    expect(unsettledOf(star), isFalse);
    expect(star.requestedTransfer, isFalse);
  });
}
