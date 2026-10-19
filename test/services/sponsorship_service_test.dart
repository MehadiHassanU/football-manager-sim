import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/sponsorship.dart';
import 'package:football_manager_sim/core/models/team.dart';
import 'package:football_manager_sim/core/services/sponsorship_service.dart';

import '../helpers/test_hive.dart';

Team _club({int reputation = 76}) =>
    stubLeagueDatabase(4, random: Random(2)).teams.first
      ..reputation = reputation;

void main() {
  group('offer generation', () {
    test('every free slot gets 2-4 bids with distinct brands', () {
      final team = _club();
      final service = SponsorshipService(rng: Random(3));
      final used = <String>{};
      var total = 0;
      for (final slot in SponsorSlot.values) {
        final offers = service.generateOffers(
          team: team,
          slot: slot,
          year: 2026,
          excludeBrands: used,
        );
        expect(offers.length, inInclusiveRange(2, 4));
        expect(offers.map((o) => o.slot), everyElement(slot));
        expect(offers.map((o) => o.year), everyElement(2026));
        expect(offers.every((o) => o.annualValue > 0), isTrue);
        expect(offers.every((o) => o.requirement.isNotEmpty), isTrue);
        expect(offers.every((o) => o.durationYears >= 1), isTrue);
        expect(offers.every((o) => o.prestige >= 1 && o.prestige <= 5), isTrue);
        expect(offers.map((o) => o.brand).toSet().length, offers.length,
            reason: 'two offers from the same brand in one slot');
        used.addAll(offers.map((o) => o.brand));
        total += offers.length;
      }
      expect(used.length, total,
          reason: 'a brand must never bid for two slots at once');
    });

    test('prestige is capped by the club the brand is bidding for', () {
      final small = _club(reputation: 55);
      final elite = _club(reputation: 92);
      final service = SponsorshipService(rng: Random(5));
      final smallOffers = service.generateOffers(
        team: small,
        slot: SponsorSlot.front,
        year: 2026,
      );
      final eliteOffers = service.generateOffers(
        team: elite,
        slot: SponsorSlot.front,
        year: 2026,
      );
      expect(smallOffers.every((o) => o.prestige <= 2), isTrue,
          reason: 'no five-star airline bids for a fourth-division shirt');
      expect(eliteOffers.every((o) => o.prestige >= 1), isTrue);
      expect(
        eliteOffers.map((o) => o.annualValue).reduce(max),
        greaterThan(smallOffers.map((o) => o.annualValue).reduce(max)),
        reason: 'bigger club, bigger money',
      );
    });

    test('offers and their clauses survive a save round-trip', () {
      final offer = SponsorshipOffer(
        id: 'front-2026-0-123',
        slot: SponsorSlot.front,
        brand: 'Volt Energy',
        prestige: 4,
        requirement: 'Top-half football',
        annualValue: 8000000,
        durationYears: 3,
        year: 2026,
        clause: const SponsorshipClause(
          kind: ClauseKind.leagueTop,
          amount: 1500000,
          threshold: 6,
        ),
      );
      final rebuilt = SponsorshipOffer.fromJson(offer.toJson())!;
      expect(rebuilt.id, 'front-2026-0-123');
      expect(rebuilt.slot, SponsorSlot.front);
      expect(rebuilt.brand, 'Volt Energy');
      expect(rebuilt.prestige, 4);
      expect(rebuilt.requirement, 'Top-half football');
      expect(rebuilt.annualValue, 8000000);
      expect(rebuilt.clause!.kind, ClauseKind.leagueTop);
      expect(rebuilt.clause!.threshold, 6);
      expect(rebuilt.clause!.amount, 1500000);

      final deal = Sponsorship(
        slot: SponsorSlot.sleeve,
        brand: 'Cobalt Water',
        annualValue: 2000000,
        startYear: 2026,
        durationYears: 2,
        prestige: 2,
      );
      final rebuiltDeal = Sponsorship.fromJson(deal.toJson())!;
      expect(rebuiltDeal.clause, isNull);
      expect(rebuiltDeal.prestige, 2);
      expect(rebuiltDeal.isActiveIn(2027), isTrue);
      expect(rebuiltDeal.isActiveIn(2028), isFalse);
    });
  });

  group('signing', () {
    test('a signature carries every term of the offer onto the deal', () {
      final offer = SponsorshipOffer(
        id: 'x',
        slot: SponsorSlot.back,
        brand: 'Kestrel Bank',
        prestige: 3,
        requirement: 'National exposure',
        annualValue: 3500000,
        durationYears: 2,
        year: 2026,
        clause: const SponsorshipClause(
          kind: ClauseKind.cupWin,
          amount: 900000,
        ),
      );
      final deal = SponsorshipService().sign(offer);
      expect(deal.slot, SponsorSlot.back);
      expect(deal.brand, 'Kestrel Bank');
      expect(deal.annualValue, 3500000);
      expect(deal.startYear, 2026);
      expect(deal.durationYears, 2);
      expect(deal.prestige, 3);
      expect(deal.clause!.kind, ClauseKind.cupWin);
      expect(deal.endYear, 2027);
    });

    test('the board signs the biggest cheque on the table', () {
      SponsorshipOffer offer(String brand, double value) => SponsorshipOffer(
            id: brand,
            slot: SponsorSlot.front,
            brand: brand,
            prestige: 3,
            requirement: 'National exposure',
            annualValue: value,
            durationYears: 1,
            year: 2026,
          );
      final service = SponsorshipService();
      final best = service.bestOffer([
        offer('Small', 2000000),
        offer('Big', 9000000),
        offer('Mid', 5000000),
      ]);
      expect(best!.brand, 'Big');
      expect(service.bestOffer(const []), isNull);
      expect(
        service
            .offersForSlot([offer('A', 1), offer('B', 2)], SponsorSlot.back),
        isEmpty,
      );
    });
  });

  group('clause settlement', () {
    Sponsorship deal(
      SponsorshipClause clause, {
      int startYear = 2026,
      int durationYears = 3,
    }) =>
        Sponsorship(
          slot: SponsorSlot.front,
          brand: 'Aurora Telecom',
          annualValue: 8000000,
          startYear: startYear,
          durationYears: durationYears,
          clause: clause,
        );

    test('a top-N clause pays exactly inside the top N', () {
      final service = SponsorshipService();
      final target = deal(const SponsorshipClause(
        kind: ClauseKind.leagueTop,
        amount: 2000000,
        threshold: 4,
      ));
      final paid = service.settleClauses(
        deals: [target],
        year: 2026,
        leaguePosition: 3,
        leagueGoals: 60,
        cupWon: false,
      );
      expect(paid.length, 1);
      expect(paid.first.amount, 2000000);
      expect(paid.first.reason, 'Top-4 finish');

      final missed = service.settleClauses(
        deals: [target],
        year: 2026,
        leaguePosition: 5,
        leagueGoals: 60,
        cupWon: false,
      );
      expect(missed, isEmpty);
    });

    test('a per-goal clause pays on the season total', () {
      final paid = SponsorshipService().settleClauses(
        deals: [
          deal(const SponsorshipClause(
            kind: ClauseKind.goals,
            amount: 50000,
          )),
        ],
        year: 2026,
        leaguePosition: 9,
        leagueGoals: 61,
        cupWon: false,
      );
      expect(paid.length, 1);
      expect(paid.first.amount, 3050000);
      expect(paid.first.reason, '61 league goals');
    });

    test('a cup clause waits for silverware', () {
      final target = deal(const SponsorshipClause(
        kind: ClauseKind.cupWin,
        amount: 1200000,
      ));
      final service = SponsorshipService();
      expect(
        service.settleClauses(
          deals: [target],
          year: 2026,
          leaguePosition: 1,
          leagueGoals: 70,
          cupWon: false,
        ),
        isEmpty,
      );
      final paid = service.settleClauses(
        deals: [target],
        year: 2026,
        leaguePosition: 1,
        leagueGoals: 70,
        cupWon: true,
      );
      expect(paid.single.amount, 1200000);
      expect(paid.single.reason, 'Cup winners');
    });

    test('expired deals and flat deals never appear', () {
      final expired = deal(
        const SponsorshipClause(kind: ClauseKind.cupWin, amount: 999999),
        startYear: 2024,
        durationYears: 1,
      );
      final flat = Sponsorship(
        slot: SponsorSlot.back,
        brand: 'Terra Motors',
        annualValue: 4000000,
        startYear: 2026,
        durationYears: 2,
      );
      final paid = SponsorshipService().settleClauses(
        deals: [expired, flat],
        year: 2026,
        leaguePosition: 1,
        leagueGoals: 80,
        cupWon: true,
      );
      expect(paid, isEmpty,
          reason: 'a clause runs for the season it was signed for');
    });
  });

  group('the fallback board', () {
    test('ensureDeals sells only the empty slots', () {
      final team = _club();
      final running = Sponsorship(
        slot: SponsorSlot.front,
        brand: 'Existing Brand',
        annualValue: 5200000,
        startYear: 2026,
        durationYears: 2,
      );
      final deals = SponsorshipService(rng: Random(4)).ensureDeals(
        existing: [running],
        team: team,
        year: 2026,
      );
      expect(deals.length, SponsorSlot.values.length);
      expect(deals.where((d) => d.slot == SponsorSlot.front).length, 1);
      expect(
        deals.firstWhere((d) => d.slot == SponsorSlot.front).brand,
        'Existing Brand',
      );
    });

    test('weekly income spreads the annual value across the year', () {
      final deal = Sponsorship(
        slot: SponsorSlot.front,
        brand: 'Solstice Energy',
        annualValue: 5200000,
        startYear: 2026,
        durationYears: 1,
      );
      expect(SponsorshipService().weeklyIncome([deal], 2026), 100000);
      expect(SponsorshipService().weeklyIncome([deal], 2027), 0);
    });
  });
}
