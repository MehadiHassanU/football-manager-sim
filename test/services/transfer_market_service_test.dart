import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/player.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/team.dart';
import 'package:football_manager_sim/core/models/transfer.dart';
import 'package:football_manager_sim/core/services/financial_service.dart';
import 'package:football_manager_sim/core/services/transfer_market_service.dart';

import '../helpers/test_hive.dart';

void main() {
  const service = TransferMarketService();

  Team club(
    String id, {
    String? name,
    int reputation = 70,
    List<Player> squad = const [],
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
        squad: squad,
      );

  Player target({
    int id = 1,
    int ovr = 85,
    String position = 'ST',
    int age = 25,
    int contractYear = 2030,
  }) =>
      stubPlayer(id: id, name: 'Target $id', ovr: ovr, position: position)
        ..age = age
        ..contractExpiry = DateTime(contractYear, 6, 30);

  group('valuation', () {
    test('elite players cost real money, not pocket change', () {
      final value = FinancialService()
          .calculateTransferValue(target(ovr: 91, age: 27), seasonYear: 2026);
      // The old formula priced this at about €12M.
      expect(value, greaterThan(100000000));
      expect(value, lessThan(400000000));
    });

    test('a squad player is affordable but not free', () {
      final value = FinancialService()
          .calculateTransferValue(target(ovr: 70), seasonYear: 2026);
      expect(value, greaterThan(1000000));
      expect(value, lessThan(30000000));
    });

    test('value falls steeply after 31', () {
      final young = FinancialService()
          .calculateTransferValue(target(age: 26), seasonYear: 2026);
      final old = FinancialService()
          .calculateTransferValue(target(age: 34), seasonYear: 2026);
      expect(old, lessThan(young * 0.4));
    });
  });

  group('asking price', () {
    test('the seller asks more than the market value', () {
      final player = target(ovr: 84);
      final seller = club('seller', squad: [player]);
      final value = FinancialService()
          .calculateTransferValue(player, seasonYear: 2026);
      final ask = service.askingPrice(player, seller, seasonYear: 2026);
      expect(ask, greaterThan(value));
    });

    test('a final-year contract is cheaper', () {
      final longDeal = target(id: 1, contractYear: 2030);
      final expiring = target(id: 2, contractYear: 2027);
      final askLong =
          service.askingPrice(longDeal, club('s'), seasonYear: 2026);
      final askShort =
          service.askingPrice(expiring, club('s'), seasonYear: 2026);
      expect(askShort, lessThan(askLong));
    });

    test('a direct league rival is charged a premium', () {
      final player = target(ovr: 84);
      final seller = club('seller');
      final outsider = club('outsider')..leagueId = 'other_league';
      final rival = club('rival');
      final normal =
          service.askingPrice(player, seller, seasonYear: 2026);
      final derby = service.askingPrice(
        player,
        seller,
        seasonYear: 2026,
        buyer: rival,
      );
      expect(derby, greaterThan(normal));
      expect(
        service.askingPrice(
          player,
          seller,
          seasonYear: 2026,
          buyer: outsider,
        ),
        normal,
      );
    });

    test('out-of-contract players are free agents', () {
      final player = target(contractYear: 2026);
      expect(service.isFreeAgent(player, 2026), isTrue);
      expect(service.askingPrice(player, club('s'), seasonYear: 2026), 0);
      expect(service.canSign(TransferWindow.of(season(10)), true), isTrue);
      expect(service.canSign(TransferWindow.of(season(10)), false), isFalse);
    });
  });

  group('bid evaluation', () {
    test('a bid at the asking price is accepted', () {
      final result = service.evaluateBid(
        asking: 10000000,
        reservation: 8000000,
        offer: 10000000,
        round: 0,
        patience: 3,
        seed: 1,
      );
      expect(result.outcome, BidOutcome.accepted);
    });

    test('a low bid is countered at the asking price', () {
      final result = service.evaluateBid(
        asking: 10000000,
        reservation: 8000000,
        offer: 5000000,
        round: 0,
        patience: 3,
        seed: 1,
      );
      expect(result.outcome, BidOutcome.countered);
      expect(result.counter, 10000000);
      expect(result.patience, lessThan(3));
    });

    test('a bid near the reservation gets a split counter', () {
      final result = service.evaluateBid(
        asking: 10000000,
        reservation: 8000000,
        offer: 9000000,
        round: 1,
        patience: 2,
        seed: 1,
      );
      expect(result.outcome, BidOutcome.countered);
      expect(result.counter, inInclusiveRange(9000000, 10000000));
    });

    test('three bids are the limit', () {
      final result = service.evaluateBid(
        asking: 10000000,
        reservation: 8000000,
        offer: 9000000,
        round: 2,
        patience: 1,
        seed: 1,
      );
      expect(result.outcome, BidOutcome.collapsed);
      expect(result.patience, 0);
    });

    test('an insulting bid is called out', () {
      final result = service.evaluateBid(
        asking: 10000000,
        reservation: 8000000,
        offer: 1000000,
        round: 0,
        patience: 3,
        seed: 1,
      );
      expect(result.message.toLowerCase(), contains('unhappy'));
      expect(result.patience, 1);
    });

    test('a free agent needs no fee', () {
      final result = service.evaluateBid(
        asking: 0,
        reservation: 0,
        offer: 0,
        round: 0,
        patience: 3,
        seed: 1,
      );
      expect(result.outcome, BidOutcome.accepted);
    });
  });

  group('personal terms', () {
    test('the asking wage is enough for a club of the right size', () {
      final player = target(ovr: 82);
      final buyer = club('buyer', reputation: 90);
      final wage = service.wageDemand(player, buyer);
      final terms = service.evaluateTerms(
        player: player,
        buyer: buyer,
        wage: wage,
        bonus: 0,
        years: 4,
        role: 'First Team',
      );
      expect(terms.accepted, isTrue);
    });

    test('a low wage is rejected with the agent demand', () {
      final player = target(ovr: 82);
      final buyer = club('buyer', reputation: 90);
      final terms = service.evaluateTerms(
        player: player,
        buyer: buyer,
        wage: 1000,
        bonus: 0,
        years: 4,
        role: 'First Team',
      );
      expect(terms.accepted, isFalse);
      expect(terms.counterWage, greaterThan(1000));
      expect(terms.message, contains('agent'));
    });

    test('a small club must overpay', () {
      final player = target(ovr: 86);
      final bigClub = club('big', reputation: 92);
      final smallClub = club('small', reputation: 55);
      expect(
        service.wageDemand(player, smallClub),
        greaterThan(service.wageDemand(player, bigClub)),
      );
      final terms = service.evaluateTerms(
        player: player,
        buyer: smallClub,
        wage: service.wageDemand(player, bigClub),
        bonus: 0,
        years: 4,
        role: 'First Team',
      );
      expect(terms.accepted, isFalse,
          reason: 'prestige cannot be bought with a market-rate wage');
    });

    test('a big signing bonus can bridge a wage gap', () {
      final player = target(ovr: 82);
      final buyer = club('buyer', reputation: 90);
      final demand = service.wageDemand(player, buyer);
      final terms = service.evaluateTerms(
        player: player,
        buyer: buyer,
        wage: (demand * 0.8).round(),
        bonus: (demand * 52 * 4).round(),
        years: 4,
        role: 'First Team',
      );
      expect(terms.accepted, isTrue);
    });
  });

  group('rivals', () {
    test('are deterministic for the same player and season', () {
      final player = target(ovr: 88);
      final elite = [
        club('a', reputation: 88),
        club('b', reputation: 90, name: 'B'),
        club('c', reputation: 84, name: 'C'),
      ];
      final first =
          service.rivalClubFor(player, elite, seasonYear: 2026);
      final second =
          service.rivalClubFor(player, elite, seasonYear: 2026);
      expect(first, second);
    });

    test('never circle a player below the elite threshold', () {
      final player = target(ovr: 70);
      final elite = [club('a', reputation: 90)];
      expect(service.rivalClubFor(player, elite, seasonYear: 2026), isNull);
    });

    test('a rival is never the selling club', () {
      final player = target(ovr: 90);
      final seller = club('seller', name: player.currentTeam, reputation: 92);
      final other = club('other', reputation: 90);
      final rival = service.rivalClubFor(
        player,
        [seller, other],
        seasonYear: 2026,
      );
      if (rival != null) expect(rival, isNot(seller.name));
    });
  });

  group('windows', () {
    test('the summer window covers the opening matchdays', () {
      final open = TransferWindow.of(season(0));
      expect(open.isOpen, isTrue);
      expect(open.isDeadlineDay, isFalse);
      expect(TransferWindow.of(season(3)).isDeadlineDay, isTrue);
      expect(TransferWindow.of(season(4)).isOpen, isFalse);
    });

    test('the winter window wraps the mid-season break', () {
      final winter = TransferWindow.of(season(19));
      expect(winter.isOpen, isTrue);
      expect(winter.label, 'Winter window');
      expect(TransferWindow.of(season(22)).isDeadlineDay, isTrue);
      expect(TransferWindow.of(season(15)).isOpen, isFalse);
    });

    test('nothing opens after the last matchday', () {
      expect(TransferWindow.of(season(38)).isOpen, isFalse);
    });

    test('the banner counts down to the deadline', () {
      expect(TransferWindow.of(season(1)).banner(season(1)),
          contains('2 matchdays left'));
      expect(TransferWindow.of(season(3)).banner(season(3)),
          contains('DEADLINE DAY'));
    });
  });

  group('market listings', () {
    test('price every player once, with free agents at zero', () {
      final free = target(id: 5, contractYear: 2026)
        ..currentTeam = 'Seller FC';
      final owned = target(id: 6, ovr: 70, contractYear: 2030)
        ..currentTeam = 'Seller FC';
      final seller = club('seller', name: 'Seller FC', squad: [owned, free]);
      final listings = service.buildListings(
        players: [owned, free],
        teams: [seller],
        seasonYear: 2026,
      );
      expect(listings, hasLength(2));
      final freeListing = listings.firstWhere((l) => l.player.id == 5);
      expect(freeListing.freeAgent, isTrue);
      expect(freeListing.askingPrice, 0);
      final ownedListing = listings.firstWhere((l) => l.player.id == 6);
      expect(ownedListing.askingPrice, greaterThan(0));
      expect(ownedListing.seller?.name, 'Seller FC');
    });
  });

  group('backfill', () {
    test('fills contracts, wages and reputation from squad strength', () {
      final squad = [
        for (var i = 0; i < 16; i++)
          stubPlayer(id: 100 + i, name: 'P$i', ovr: 85),
      ];
      final team = club('big', squad: squad);
      expect(team.reputation, 70);
      service.backfillTransferData([team], 2026);
      expect(team.reputation, greaterThan(80));
      for (final player in squad) {
        expect(player.contractExpiry, isNotNull);
        expect(player.weeklyWage, greaterThan(0));
        expect(player.transferValue, greaterThan(0));
      }
    });

    test('never leaves a player already out of contract', () {
      // Ids divisible by four used to expire on the first day of a career,
      // which handed the manager a quarter of the database for free.
      final squad = [
        for (var i = 0; i < 12; i++)
          stubPlayer(id: 4000 + i, name: 'P$i', ovr: 72),
      ];
      final team = club('t', squad: squad);
      service.backfillTransferData([team], 2026);
      for (final player in squad) {
        expect(service.isFreeAgent(player, 2026), isFalse,
            reason: 'player ${player.id} must still be under contract');
        expect(player.contractExpiry!.year, greaterThan(2026));
      }
    });

    test('never overwrites an existing contract or reputation', () {
      final player = stubPlayer(id: 1, name: 'P', ovr: 80)
        ..contractExpiry = DateTime(2031, 6, 30)
        ..weeklyWage = 12345;
      final team = club('t', reputation: 88, squad: [player]);
      service.backfillTransferData([team], 2026);
      expect(team.reputation, 88);
      expect(player.contractExpiry, DateTime(2031, 6, 30));
      expect(player.weeklyWage, 12345);
    });
  });
}

SeasonState season(int matchday) => SeasonState(
      leagueId: 'test_league',
      currentMatchday: matchday,
      totalMatchdays: 38,
      currentYear: 2026,
      isPreSeason: false,
    );
