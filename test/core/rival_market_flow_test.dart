import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/team.dart';
import 'package:football_manager_sim/core/models/transfer.dart';
import 'package:football_manager_sim/core/services/rival_market_service.dart';
import 'package:football_manager_sim/core/services/transfer_market_service.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';

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
      records: {for (var c = 0; c < 4; c++) 'club_$c': LeagueRecord()},
      rounds: buildRounds(
        [for (var c = 0; c < 4; c++) 'club_$c'],
        rng: Random(1),
      ),
    );

CareerSession _sessionFor(PlayerDatabase db, {int matchday = 1}) {
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
  CareerSession session, {
  RivalTransferService? rivalService,
}) async {
  final container = ProviderContainer(
    overrides: [
      playerDatabaseProvider.overrideWith((ref) async => db),
      careerSessionProvider.overrideWith((ref) => session),
      if (rivalService != null)
        rivalTransferServiceProvider.overrideWith((ref) => rivalService),
    ],
  );
  addTearDown(container.dispose);
  // The database is a FutureProvider: read it before the desk advances, or
  // the market finds a null database and quietly does nothing.
  await container.read(playerDatabaseProvider.future);
  return container;
}

void main() {
  testWidgets('rival deals land in the world, the ledger and the news feed',
      (tester) async {
    final db = stubLeagueDatabase(4);
    // The user manages the first club; rivals are the other three.
    final user = db.teams.first;
    final seller = db.teams[1];
    final buyer = db.teams[2];
    final player = seller.squad[3];

    // A scripted service so the wiring is tested deterministically instead
    // of through seeded rolls (the real generator has its own unit tests).
    final script = FakeRivalService([
      RivalDeal(
        player: player,
        seller: seller,
        buyer: buyer,
        fee: 5000000,
        wage: 25000,
      ),
    ]);

    final session = _sessionFor(db, matchday: 1);
    final container = await _containerFor(db, session, rivalService: script);

    await _run(
      tester,
      container,
      (ref) => advanceTransferDesk(ref, session),
    );

    // The world moved.
    expect(seller.squad.any((p) => p.id == player.id), isFalse,
        reason: 'the seller loses his player to the buyer');
    expect(buyer.squad.any((p) => p.id == player.id), isTrue);
    expect(player.currentTeam, 'Club 2');
    expect(player.weeklyWage, 25000);

    // The manager's squad was never touched.
    expect(user.squad.any((p) => p.id == player.id), isFalse);

    // The ledger is the durable truth of the move.
    final moves = session.transferDesk.ledger
        .where((m) => m.playerId == player.id)
        .toList();
    expect(moves, hasLength(1));
    expect(moves.single.toClub, 'Club 2');
    expect(moves.single.fromClub, 'Club 1');
    expect(moves.single.kind, 'permanent');
    expect(moves.single.fee, 5000000);
    expect(moves.single.year, 2026);
    expect(moves.single.matchday, 1);

    // And the feed tells the story.
    expect(
      session.transferDesk.news.any((n) => n.type == 'rival'),
      isTrue,
      reason: 'rival business should be visible on the desk',
    );
  });

  testWidgets('an applied rival move replays onto a rebuilt database',
      (tester) async {
    final db = stubLeagueDatabase(4);
    final seller = db.teams[1];
    final buyer = db.teams[2];
    final player = seller.squad[5];

    final script = FakeRivalService([
      RivalDeal(
        player: player,
        seller: seller,
        buyer: buyer,
        fee: 8000000,
        wage: 30000,
      ),
    ]);
    final session = _sessionFor(db, matchday: 1);
    final container = await _containerFor(db, session, rivalService: script);
    await _run(
      tester,
      container,
      (ref) => advanceTransferDesk(ref, session),
    );

    // Restore rebuilds the world from CSV/ledger, which is exactly what the
    // replay does onto a fresh database.
    final freshDb = stubLeagueDatabase(4);
    TransferMarketService().applyTransferLedger(
      players: freshDb.players,
      teams: freshDb.teams,
      moves: [...session.transferDesk.ledger],
      userClub: 'Club 0',
    );

    final freshSeller = freshDb.teams[1];
    final freshBuyer = freshDb.teams[2];
    final moved = freshDb.players.firstWhere((p) => p.id == player.id);
    expect(freshSeller.squad.any((p) => p.id == player.id), isFalse,
        reason: 'a replayed move must not resurrect the old ownership');
    expect(freshBuyer.squad.any((p) => p.id == player.id), isTrue);
    expect(moved.currentTeam, 'Club 2');
    expect(moved.weeklyWage, 30000);
  });

  testWidgets('a rival move survives the desk JSON round trip',
      (tester) async {
    final db = stubLeagueDatabase(4);
    final seller = db.teams[1];
    final buyer = db.teams[3];
    final player = seller.squad[2];

    final script = FakeRivalService([
      RivalDeal(
        player: player,
        seller: seller,
        buyer: buyer,
        fee: 3000000,
        wage: 20000,
      ),
    ]);
    final session = _sessionFor(db, matchday: 1);
    final container = await _containerFor(db, session, rivalService: script);
    await _run(
      tester,
      container,
      (ref) => advanceTransferDesk(ref, session),
    );

    final restored = TransferDesk.fromJson(session.transferDesk.toJson());
    final move = restored.ledger.singleWhere((m) => m.playerId == player.id);
    expect(move.fromClub, 'Club 1');
    expect(move.toClub, 'Club 3');
    expect(move.fee, 3000000);
    expect(restored.news.any((n) => n.type == 'rival'), isTrue);
  });

  testWidgets('the rival clock never sells a player the manager owns',
      (tester) async {
    final db = stubLeagueDatabase(4);
    final user = db.teams.first;
    final buyer = db.teams[2];
    // A scripted deal pointed at the manager's own squad on purpose: the
    // session must refuse it rather than strip the authoritative squad.
    final own = user.squad[4];

    final script = FakeRivalService([
      RivalDeal(
        player: own,
        seller: user,
        buyer: buyer,
        fee: 9000000,
        wage: 30000,
      ),
    ]);
    final session = _sessionFor(db, matchday: 1);
    final container = await _containerFor(db, session, rivalService: script);
    await _run(
      tester,
      container,
      (ref) => advanceTransferDesk(ref, session),
    );

    expect(user.squad.any((p) => p.id == own.id), isTrue,
        reason: 'the manager keeps his player');
    expect(session.transferDesk.ledger.any((m) => m.playerId == own.id),
        isFalse,
        reason: 'a refused deal must not reach the ledger');
  });
}

/// Returns a fixed deal list regardless of what the world looks like.
class FakeRivalService extends RivalTransferService {
  FakeRivalService(this.moves);

  final List<RivalDeal> moves;

  @override
  List<RivalDeal> generateMoves({
    required List<Team> teams,
    required String userClub,
    required String seedKey,
    required int seasonYear,
    required int matchday,
    required Set<String> priorityBuyers,
    required Set<int> busyPlayers,
    double activityMultiplier = 1.0,
  }) =>
      moves;
}
