import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/player.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/sponsorship.dart';
import 'package:football_manager_sim/core/models/team.dart';
import 'package:football_manager_sim/core/services/financial_service.dart';
import 'package:football_manager_sim/core/services/sponsorship_service.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';

import '../helpers/test_hive.dart';

/// A club of [ovr] strength with a squad that costs what its level says it
/// should — the same way `backfillTransferData` prices a real save.
Team _calibrationTeam(int ovr) {
  final finance = FinancialService();
  final reputation = (40 + ovr * 0.55).round();
  final squad = <Player>[];
  for (var i = 0; i < 25; i++) {
    final player = stubPlayer(id: 1000 + i, name: 'Player $i', ovr: ovr);
    player.weeklyWage = finance.expectedWeeklyWage(player);
    squad.add(player);
  }
  final id = 'cal_$ovr';
  return Team(
    id: id,
    name: 'Cal $ovr',
    shortName: 'C$ovr',
    leagueId: 'test_league',
    country: 'EN',
    stadiumName: 'Ground',
    stadiumCapacity: finance.realisticCapacity(reputation, id),
    budget: 10000000,
    color: '#FFF',
    badgeUrl: '',
    reputation: reputation,
    squad: squad,
  );
}

Sponsorship _deal(
  SponsorSlot slot, {
  String brand = 'Volt Energy',
  double annualValue = 10400000,
  int startYear = 2026,
  int durationYears = 3,
}) =>
    Sponsorship(
      slot: slot,
      brand: brand,
      annualValue: annualValue,
      startYear: startYear,
      durationYears: durationYears,
    );

void main() {
  group('Sponsorship', () {
    test('round-trips through JSON', () {
      final deal = _deal(SponsorSlot.back,
          brand: 'Kestrel Bank', annualValue: 4200000);
      final restored = Sponsorship.fromJson(deal.toJson())!;
      expect(restored.slot, SponsorSlot.back);
      expect(restored.brand, 'Kestrel Bank');
      expect(restored.annualValue, 4200000);
      expect(restored.startYear, 2026);
      expect(restored.durationYears, 3);
      expect(restored.endYear, 2028);
      expect(restored.yearsRemaining(2027), 2);
      expect(restored.yearsRemaining(2030), 0, reason: 'clamped at zero');
    });

    test('a damaged record is refused instead of crashing the load', () {
      expect(Sponsorship.fromJson(<String, dynamic>{'slot': 'elbow'}), isNull);
      expect(Sponsorship.fromJson(<String, dynamic>{'slot': 'front'}), isNull);
      expect(
        Sponsorship.fromJson(<String, dynamic>{
          'slot': 'front',
          'brand': 'X',
          'annualValue': 'lots',
          'startYear': 2026,
          'durationYears': 3,
        }),
        isNull,
      );
    });
  });

  group('SponsorshipService', () {
    test('mints one deal per slot sized to the club level', () {
      final team = _calibrationTeam(84);
      final deals = SponsorshipService(rng: Random(3))
          .ensureDeals(existing: const [], team: team, year: 2026);

      expect(deals, hasLength(SponsorSlot.values.length));
      expect({for (final deal in deals) deal.slot}, SponsorSlot.values.toSet());
      expect({for (final deal in deals) deal.brand}.length, 3,
          reason: 'one brand should not cover two slots of the same kit');

      final bySlot = {for (final deal in deals) deal.slot: deal};
      final front = bySlot[SponsorSlot.front]!;
      final back = bySlot[SponsorSlot.back]!;
      final sleeve = bySlot[SponsorSlot.sleeve]!;
      expect(back.annualValue, closeTo(front.annualValue * 0.4, 100000));
      expect(sleeve.annualValue, closeTo(front.annualValue * 0.3, 100000));

      for (final deal in deals) {
        expect(deal.annualValue, greaterThan(0));
        expect(deal.durationYears, inInclusiveRange(1, 5));
        expect(deal.startYear, 2026);
        expect(deal.isActiveIn(2026), isTrue);
      }
    });

    test('is deterministic for a seeded market', () {
      final team = _calibrationTeam(84);
      final first = SponsorshipService(rng: Random(11))
          .ensureDeals(existing: const [], team: team, year: 2026);
      final second = SponsorshipService(rng: Random(11))
          .ensureDeals(existing: const [], team: team, year: 2026);
      for (var i = 0; i < first.length; i++) {
        expect(first[i].slot, second[i].slot);
        expect(first[i].brand, second[i].brand);
        expect(first[i].annualValue, second[i].annualValue);
        expect(first[i].durationYears, second[i].durationYears);
      }
    });

    test('keeps running deals and renews only the expired slot', () {
      final team = _calibrationTeam(84);
      final running = _deal(SponsorSlot.front, durationYears: 2);
      final expiring = _deal(SponsorSlot.back,
          brand: 'Kestrel Bank', annualValue: 4000000, durationYears: 1);

      final renewed = SponsorshipService(rng: Random(2)).ensureDeals(
        existing: [running, expiring],
        team: team,
        year: 2027,
        revalue: true,
      );

      expect(renewed, hasLength(3));
      final kept = renewed.firstWhere((d) => d.slot == SponsorSlot.front);
      expect(identical(kept, running), isTrue,
          reason: 'a contract still running must not be rewritten');
      final back = renewed.where((d) => d.slot == SponsorSlot.back).single;
      expect(back.startYear, 2027, reason: 'the expired slot renews now');
      expect(back.isActiveIn(2027), isTrue);
      final sleeve = renewed.where((d) => d.slot == SponsorSlot.sleeve).single;
      expect(sleeve.startYear, 2027, reason: 'the empty slot is sold too');
    });

    test('renewals drift around the tier value instead of repeating it', () {
      final team = _calibrationTeam(84);
      final expectedFront =
          FinancialService().frontOfShirtValue(team.reputation);
      final fronts = <double>[];
      for (var seed = 0; seed < 12; seed++) {
        final deals = SponsorshipService(rng: Random(seed)).ensureDeals(
          existing: const [],
          team: team,
          year: 2030,
          revalue: true,
        );
        fronts.add(
            deals.where((d) => d.slot == SponsorSlot.front).single.annualValue);
      }
      // ±15% band, rounded to 100k: never far from the tier value, never the
      // exact same number every summer.
      for (final value in fronts) {
        expect(value, greaterThanOrEqualTo(expectedFront * 0.85 - 100000));
        expect(value, lessThanOrEqualTo(expectedFront * 1.15 + 100000));
      }
      expect({...fronts}.length, greaterThan(1));
    });

    test('weekly income divides the annual book across the year', () {
      final service = SponsorshipService();
      final deals = [
        _deal(SponsorSlot.front),
        _deal(SponsorSlot.back, brand: 'Kestrel Bank', annualValue: 5200000),
      ];
      expect(service.weeklyIncome(deals, 2026), closeTo(15600000 / 52, 0.01));
      expect(service.weeklyIncome(deals, 2029), 0,
          reason: 'expired deals pay nothing');
    });
  });

  group('Financial tier helpers', () {
    test('capacity bands track reputation and are deterministic', () {
      final finance = FinancialService();
      final elite = finance.realisticCapacity(88, 'club');
      final top = finance.realisticCapacity(83, 'club');
      final upper = finance.realisticCapacity(79, 'club');
      final mid = finance.realisticCapacity(77, 'club');
      final lower = finance.realisticCapacity(71, 'club');
      final small = finance.realisticCapacity(60, 'club');

      expect(elite, greaterThanOrEqualTo(59000),
          reason: 'a big club plays in a big ground');
      expect(elite, lessThanOrEqualTo(77000));
      expect(top, lessThanOrEqualTo(elite));
      expect(upper, lessThanOrEqualTo(top));
      expect(mid, lessThanOrEqualTo(upper));
      expect(lower, lessThanOrEqualTo(mid));
      expect(small, lessThanOrEqualTo(lower));
      expect(small, lessThanOrEqualTo(11000),
          reason: 'a small club is not given a stadium it cannot fill');

      expect(finance.realisticCapacity(88, 'club'),
          finance.realisticCapacity(88, 'club'),
          reason: 'the same club always keeps the same ground');

      final spread = [
        for (final id in ['a', 'b', 'c', 'd', 'e', 'f'])
          finance.realisticCapacity(88, id),
      ];
      for (final capacity in spread) {
        expect(capacity, greaterThanOrEqualTo(59000));
        expect(capacity, lessThanOrEqualTo(77000));
      }
      expect({...spread}.length, greaterThan(1),
          reason: 'the per-club spread must vary or every ground is a twin');
    });

    test('broadcast and kit money climb with reputation', () {
      final finance = FinancialService();
      var lastBroadcast = 0.0;
      var lastFront = 0.0;
      for (var reputation = 55; reputation <= 90; reputation += 5) {
        final broadcast = finance.broadcastPerMatch(reputation);
        final front = finance.frontOfShirtValue(reputation);
        expect(broadcast, greaterThan(0));
        expect(front, greaterThan(0));
        expect(broadcast, greaterThanOrEqualTo(lastBroadcast));
        expect(front, greaterThanOrEqualTo(lastFront));
        lastBroadcast = broadcast;
        lastFront = front;
      }
      // Real-life floor and ceiling: eight figures for a giant, pocket money
      // for a fourth-tier club.
      expect(finance.frontOfShirtValue(88), greaterThan(20000000));
      expect(finance.frontOfShirtValue(60), lessThan(2000000));
      expect(finance.broadcastPerMatch(88), greaterThan(1000000));
    });

    test('merit prize rewards the higher finish', () {
      final finance = FinancialService();
      final champion = finance.meritPrize(84, 1, 20);
      final middle = finance.meritPrize(84, 10, 20);
      final last = finance.meritPrize(84, 20, 20);
      expect(champion, greaterThan(middle));
      expect(middle, greaterThan(last));
      expect(last, greaterThan(0));
      expect(finance.meritPrize(84, 0, 20), champion,
          reason: 'positions are clamped into the table');
      expect(finance.meritPrize(84, 21, 20), last);
      expect(finance.meritPrize(84, 1, 0), 0);
      expect(finance.meritPrize(88, 1, 20),
          greaterThan(finance.meritPrize(70, 1, 20)),
          reason: 'the big leagues pay bigger merit money');
    });
  });

  group('Season balance', () {
    test('every level of club funds itself across a season', () {
      final finance = FinancialService();
      // A 20-club league: 38 matchdays, 19 of them at home. Wages settle once
      // per matchday, kit instalments once per week, broadcast once per match.
      for (final ovr in [60, 66, 72, 78, 84, 90]) {
        final team = _calibrationTeam(ovr);
        final deals = SponsorshipService(rng: Random(ovr))
            .ensureDeals(existing: const [], team: team, year: 2026);
        final income = finance.estimateGateReceipts(team) * 19 +
            finance.broadcastPerMatch(team.reputation) * 38 +
            SponsorshipService().weeklyIncome(deals, 2026) * 38 +
            finance.meritPrize(team.reputation, 10, 20);
        final cost = finance.calculateWageBill(team) * 38;
        final ratio = income / cost;
        expect(ratio, inInclusiveRange(1.25, 1.95),
            reason: 'an OVR $ovr club must be sustainable without being a '
                'money printer (ratio ${ratio.toStringAsFixed(2)})');
      }
    });
  });

  group('repairClubFinances', () {
    CareerSession sessionFor(Team team) => CareerSession(
          manager: Manager(name: 'Boss', age: 40, nationality: 'Spain'),
          team: team,
          season: SeasonState(
            leagueId: 'test_league',
            currentYear: 2026,
            records: {team.id: LeagueRecord()},
          ),
        );

    test('gives a pre-finance save a real ground and a sold shirt', () {
      // The flat formula every pre-finance save carries, plus the empty kit.
      final team = _calibrationTeam(84)..stadiumCapacity = 61960;
      final session = sessionFor(team);
      expect(session.sponsorships, isEmpty);

      repairClubFinances(session);

      expect(team.stadiumCapacity,
          FinancialService().realisticCapacity(team.reputation, team.id));
      expect(session.sponsorships, hasLength(3));
      for (final deal in session.sponsorships) {
        expect(deal.isActiveIn(session.season.currentYear), isTrue);
      }
    });

    test('leaves a club that already has its ground and deals alone', () {
      final team = _calibrationTeam(84);
      final session = sessionFor(team);
      repairClubFinances(session);
      final capacity = team.stadiumCapacity;
      final deals = [...session.sponsorships];

      repairClubFinances(session);

      expect(team.stadiumCapacity, capacity);
      expect(session.sponsorships, hasLength(3));
      for (var i = 0; i < deals.length; i++) {
        expect(identical(session.sponsorships[i], deals[i]), isTrue,
            reason: 'repair must not reroll deals that are still running');
      }
    });
  });
}
