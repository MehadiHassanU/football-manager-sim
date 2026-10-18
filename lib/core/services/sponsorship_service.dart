import 'dart:math';

import '../constants/game_constants.dart';
import '../models/sponsorship.dart';
import '../models/team.dart';
import 'financial_service.dart';

/// Markets the club's kit: what a deal is worth, how long it runs and what
/// shows on the shirt.
///
/// Only the manager's club carries deals, because only its books are
/// simulated from week to week; the values come from [FinancialService] so the
/// deal board and the matchday settlement can never disagree on what a
/// front-of-shirt contract is worth.
class SponsorshipService {
  SponsorshipService({Random? rng, FinancialService? finance})
      : rng = rng ?? Random(),
        finance = finance ?? FinancialService();

  final Random rng;
  final FinancialService finance;

  /// Fake brands only. Real marks are licensed properties and the store build
  /// ships without them (see the Play Console checklist), so the kit is sold
  /// to companies that do not exist.
  static const List<String> _brands = [
    'Northwind Airlines',
    'Volt Energy',
    'Kestrel Bank',
    'Aurora Telecom',
    'Terra Motors',
    'Summit Insurance',
    'Orion Systems',
    'Meridian Travel',
    'Falcon Sportswear',
    'Cobalt Water',
    'Pinnacle Watches',
    'Lumen Electronics',
    'Atlas Shipping',
    'Stellar Coffee',
    'Vanguard Tyres',
    'Everline Rail',
    'Solstice Energy',
    'Harborview Hotels',
  ];

  /// How long a deal for a club of [reputation] runs.
  ///
  /// The biggest clubs sign the longest terms and the smallest clubs take the
  /// short deals, which keeps an average around the three years real kit
  /// contracts run for.
  int _duration(int reputation) {
    final base = reputation >= 84 ? 3 : (reputation < 72 ? 1 : 2);
    return (base + rng.nextInt(2)).clamp(1, 5);
  }

  String _pickBrand(Set<String> used) {
    for (var attempt = 0; attempt < 8; attempt++) {
      final brand = _brands[rng.nextInt(_brands.length)];
      if (!used.contains(brand)) return brand;
    }
    return _brands[rng.nextInt(_brands.length)];
  }

  /// A fresh deal for [slot] at the club's level.
  ///
  /// [revalue] is what the summer rollover uses: an expired deal is renewed
  /// within ±15% of the tier value instead of a rerun of the old contract.
  Sponsorship _deal({
    required Team team,
    required SponsorSlot slot,
    required int year,
    required Set<String> usedBrands,
    required bool revalue,
  }) {
    var front = finance.frontOfShirtValue(team.reputation);
    if (revalue) {
      front *= 0.85 + rng.nextDouble() * 0.3;
    }
    final share = switch (slot) {
      SponsorSlot.front => 1.0,
      SponsorSlot.back => 0.4,
      SponsorSlot.sleeve => 0.3,
    };
    return Sponsorship(
      slot: slot,
      brand: _pickBrand(usedBrands),
      annualValue: (front * share / 100000).round() * 100000.0,
      startYear: year,
      durationYears: _duration(team.reputation),
    );
  }

  /// Every slot's deal for [year], keeping deals that are still running.
  ///
  /// Called when a career starts, when a save predates the finance model, and
  /// on the summer rollover. Without it a club could reach a season with an
  /// unsold shirt and silently earn nothing from it.
  List<Sponsorship> ensureDeals({
    required List<Sponsorship> existing,
    required Team team,
    required int year,
    bool revalue = false,
  }) {
    final kept = [
      for (final deal in existing)
        if (deal.isActiveIn(year)) deal,
    ];
    final covered = {for (final deal in kept) deal.slot};
    final used = {for (final deal in kept) deal.brand};
    final fresh = <Sponsorship>[];
    for (final slot in SponsorSlot.values) {
      if (covered.contains(slot)) continue;
      final deal = _deal(
        team: team,
        slot: slot,
        year: year,
        usedBrands: used,
        revalue: revalue,
      );
      used.add(deal.brand);
      fresh.add(deal);
    }
    return [...kept, ...fresh];
  }

  /// The week's instalment from every active deal.
  ///
  /// The season settles one week per matchday, so a full calendar banks about
  /// 38 of the 52 instalments — the same fraction for every club, which keeps
  /// the deal values comparable across tiers.
  double weeklyIncome(List<Sponsorship> deals, int year) {
    var total = 0.0;
    for (final deal in deals) {
      if (deal.isActiveIn(year)) total += deal.annualValue;
    }
    return total / kWeeksPerYear;
  }
}
