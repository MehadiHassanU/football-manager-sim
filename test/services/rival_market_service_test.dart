import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/player.dart';
import 'package:football_manager_sim/core/models/team.dart';
import 'package:football_manager_sim/core/services/rival_market_service.dart';

import '../helpers/test_hive.dart';

void main() {
  final service = RivalTransferService();

  Team club(
    String id, {
    String? name,
    int reputation = 70,
    List<Player> squad = const [],
    double transferBudget = 50000000,
    double wageBudget = 1600000,
  }) =>
      Team(
        id: id,
        name: name ?? 'Club $id',
        shortName: id.toUpperCase(),
        leagueId: 'test_league',
        country: 'Spain',
        stadiumName: 'Ground',
        stadiumCapacity: 40000,
        budget: 50000000,
        color: '#00C853',
        badgeUrl: '',
        reputation: reputation,
        transferBudget: transferBudget,
        wageBudget: wageBudget,
        squad: squad,
      );

  Player pro(
    int id,
    String name, {
    int ovr = 75,
    String position = 'CM',
    required String team,
    int age = 24,
  }) {
    final player = stubPlayer(
      id: id,
      name: name,
      ovr: ovr,
      position: position,
      team: team,
    );
    player.age = age;
    player.contractExpiry = DateTime(2030, 6, 30);
    return player;
  }

  /// A league of four rival clubs plus the user's, every squad past the
  /// 16-player minimum so every club is allowed to act.
  List<Team> teamsForLeague() {
    List<Player> squad(String teamName, int idBase, int ovrBase) {
      const positions = [
        'GK', 'CB', 'CB', 'LB', 'RB', 'CDM', 'CM', 'CAM',
        'LW', 'RW', 'ST', 'CF', 'LB', 'RB', 'CM', 'ST',
      ];
      final result = <Player>[];
      for (var i = 0; i < 16; i++) {
        final player = pro(
          idBase + i,
          '$teamName player $i',
          ovr: ovrBase + (i % 5),
          position: positions[i],
          team: teamName,
        );
        player.currentTeam = teamName;
        result.add(player);
      }
      return result;
    }

    return [
      club('user_fc', name: 'User FC', squad: squad('User FC', 0, 72)),
      club('alpha', name: 'Alpha', squad: squad('Alpha', 100, 78)),
      club('beta', name: 'Beta', squad: squad('Beta', 200, 74)),
      club('gamma', name: 'Gamma', squad: squad('Gamma', 300, 70)),
      club('delta', name: 'Delta', squad: squad('Delta', 400, 66)),
    ];
  }

  List<RivalDeal> movesFor({
    required List<Team> teams,
    required int matchday,
    Set<String> priorityBuyers = const {},
    double activityMultiplier = 1.0,
  }) =>
      service.generateMoves(
        teams: teams,
        userClub: 'User FC',
        seedKey: 'test_league',
        seasonYear: 2026,
        matchday: matchday,
        priorityBuyers: priorityBuyers,
        busyPlayers: const {},
        activityMultiplier: activityMultiplier,
      );

  group('determinism', () {
    test('identical inputs produce identical deals', () {
      final a = movesFor(teams: teamsForLeague(), matchday: 3,
          priorityBuyers: const {'Alpha'});
      final b = movesFor(teams: teamsForLeague(), matchday: 3,
          priorityBuyers: const {'Alpha'});
      expect(
        [for (final d in a) (d.player.id, d.buyer.name)],
        [for (final d in b) (d.player.id, d.buyer.name)],
      );
    });

    test('the seed is matchday-specific: activity varies over the window', () {
      final teams = teamsForLeague();
      final sizes = <int>{
        for (var m = 1; m <= 30; m++)
          movesFor(teams: teams, matchday: m).length,
      };
      expect(sizes.toSet().length, greaterThan(1),
          reason: 'not every matchday should look like every other');
    });
  });

  group('constraints', () {
    test('never touches the user club', () {
      for (var m = 1; m <= 12; m++) {
        for (final deal in movesFor(
            teams: teamsForLeague(), matchday: m,
            priorityBuyers: const {'Alpha'})) {
          expect(deal.buyer.name, isNot('User FC'));
          expect(deal.seller.name, isNot('User FC'));
          expect(deal.player.currentTeam, isNot('User FC'));
        }
      }
    });

    test('the fee never exceeds the club budget', () {
      final teams = teamsForLeague();
      for (var m = 1; m <= 12; m++) {
        for (final deal in movesFor(teams: teams, matchday: m)) {
          expect(deal.fee, lessThanOrEqualTo(deal.buyer.transferBudget.round()),
              reason: '${deal.buyer.name} spent beyond its budget on $m');
        }
      }
    });

    test('the wage fits the club weekly ceiling', () {
      final teams = teamsForLeague();
      for (var m = 1; m <= 12; m++) {
        for (final deal in movesFor(teams: teams, matchday: m)) {
          if (deal.buyer.wageBudget <= 0) continue;
          expect(deal.wage, lessThanOrEqualTo(deal.buyer.wageBudget.round()),
              reason: '${deal.buyer.name} pays beyond its ceiling on $m');
        }
      }
    });

    test('never resolves a busy player from the user live negotiations', () {
      final busy = {1000, 1001, 1002};
      final teams = teamsForLeague();
      for (var m = 1; m <= 12; m++) {
        final moves = service.generateMoves(
          teams: teams,
          userClub: 'User FC',
          seedKey: 'test_league',
          seasonYear: 2026,
          matchday: m,
          priorityBuyers: const {'Alpha'},
          busyPlayers: busy,
        );
        for (final deal in moves) {
          expect(busy.contains(deal.player.id), isFalse,
              reason: 'player ${deal.player.name} was in live talks');
        }
      }
    });

    test('caps how many deals one matchday produces', () {
      final teams = teamsForLeague();
      for (var m = 1; m <= 12; m++) {
        final moves = movesFor(
            teams: teams, matchday: m,
            priorityBuyers: const {'Alpha', 'Beta', 'Gamma', 'Delta'});
        expect(moves.length, lessThanOrEqualTo(3));
      }
    });

    test('a replacement hunt raises priority-club activity', () {
      final teams = teamsForLeague();
      var withPriority = 0;
      for (var m = 1; m <= 24; m++) {
        withPriority += movesFor(
            teams: teams, matchday: m, priorityBuyers: const {'Alpha'}).length;
      }
      var withoutPriority = 0;
      for (var m = 1; m <= 24; m++) {
        withoutPriority += movesFor(teams: teams, matchday: m).length;
      }
      expect(withPriority, greaterThan(withoutPriority),
          reason: 'the club you bought from should hunt a replacement');
    });

    test('activity goes fully silent at multiplier zero', () {
      final moves = movesFor(
          teams: teamsForLeague(), matchday: 1,
          priorityBuyers: const {'Alpha', 'Beta'}, activityMultiplier: 0.0);
      expect(moves, isEmpty);
    });
  });
}
