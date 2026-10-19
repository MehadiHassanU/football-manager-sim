import 'dart:math';

import '../constants/game_constants.dart';
import '../models/sponsorship.dart';
import '../models/team.dart';
import 'financial_service.dart';

/// One clause that paid on a finished season, ready for the board's books.
class SponsorshipSettlement {
  const SponsorshipSettlement({
    required this.deal,
    required this.amount,
    required this.reason,
  });

  final Sponsorship deal;

  /// Euros the clause paid.
  final double amount;

  /// What earned it, in one line: 'Top-4 finish', '63 league goals'.
  final String reason;
}

/// Markets the club's kit: who bids for each slot, what a deal is worth, how
/// long it runs, what the brand asks for and what bonus it pays.
///
/// Only the manager's club carries deals, because only its books are
/// simulated from week to week; the values come from [FinancialService] so the
/// offer board and the matchday settlement can never disagree on what a
/// front-of-shirt contract is worth.
///
/// Nothing here signs a contract. The market puts 2–4 offers on each free
/// slot, the manager signs the one the board should shake hands on, and only
/// the season's first matchday rescues a slot that is still open.
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

  /// The share of the front-of-shirt value a slot is worth.
  double _slotShare(SponsorSlot slot) => switch (slot) {
        SponsorSlot.front => 1.0,
        SponsorSlot.back => 0.4,
        SponsorSlot.sleeve => 0.3,
      };

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

  /// Brands bid at their own level: a five-star name does not put itself on a
  /// fourth-division shirt, and a local business cannot outbid an airline.
  int _prestige(int reputation) {
    final ceiling = reputation >= 84
        ? 5
        : reputation >= 73
            ? 4
            : reputation >= 60
                ? 3
                : 2;
    return 1 + rng.nextInt(ceiling);
  }

  /// The criterion a brand attaches — always one the club already meets, so
  /// the line reads as what the money is paying for rather than a demand the
  /// club cannot satisfy.
  String _requirement(Team team, int? lastPosition, int prestige) {
    final eligible = <String>[
      'National exposure',
      if (team.reputation >= 66) 'Top-flight football',
      if (prestige >= 3 && (lastPosition == null || lastPosition <= 12))
        'Top-half football',
      if (prestige >= 4 && team.reputation >= 76) 'European qualification',
    ];
    return eligible[rng.nextInt(eligible.length)];
  }

  /// Roughly three in five deals carry a performance clause; the rest are flat.
  SponsorshipClause? _clause(double annualValue, int prestige) {
    if (rng.nextDouble() < 0.4) return null;
    final kind = switch (rng.nextInt(3)) {
      0 => ClauseKind.leagueTop,
      1 => ClauseKind.goals,
      _ => ClauseKind.cupWin,
    };
    return switch (kind) {
      ClauseKind.leagueTop => SponsorshipClause(
          kind: kind,
          threshold: switch (prestige) {
            5 => 4,
            4 => 6,
            3 => 10,
            _ => 12,
          },
          amount: _roundTo(annualValue * (0.12 + rng.nextDouble() * 0.25), 50000),
        ),
      ClauseKind.cupWin => SponsorshipClause(
          kind: kind,
          amount: _roundTo(annualValue * (0.15 + rng.nextDouble() * 0.3), 50000),
        ),
      ClauseKind.goals => SponsorshipClause(
          kind: kind,
          amount: max(
            5000,
            _roundTo(annualValue / (110 + rng.nextInt(70)), 5000),
          ),
        ),
    };
  }

  /// Rounds a figure to a real-world headline number. [step] of 50k keeps the
  /// small slots from quoting figures a brand would never say out loud.
  double _roundTo(double value, int step) =>
      max(step.toDouble(), (value / step).round() * step.toDouble());

  SponsorshipOffer _offer({
    required Team team,
    required SponsorSlot slot,
    required int year,
    required Set<String> usedBrands,
    required int? lastPosition,
    required int index,
  }) {
    final prestige = _prestige(team.reputation);
    final front = finance.frontOfShirtValue(team.reputation);
    // Prestige is money: a five-star brand's bid is worth several times a
    // local name's, and no two brands ever quote the same figure.
    final multiplier = 0.55 + prestige * 0.16 + rng.nextDouble() * 0.35;
    final annual = _roundTo(front * _slotShare(slot) * multiplier, 50000);
    return SponsorshipOffer(
      id: '${slot.key}-$year-$index-${rng.nextInt(1 << 22)}',
      slot: slot,
      brand: _pickBrand(usedBrands),
      prestige: prestige,
      requirement: _requirement(team, lastPosition, prestige),
      annualValue: annual,
      durationYears: _duration(team.reputation),
      year: year,
      clause: _clause(annual, prestige),
    );
  }

  /// A shortlist of offers for one free slot: 2–4 brands, never a repeat of
  /// [excludeBrands] (the club's running deals and the other slots' offers).
  ///
  /// [lastPosition] is where the club finished the previous season when that
  /// is known — it lets a brand ask for a top-half side even mid-table ones
  /// are told they already are one.
  List<SponsorshipOffer> generateOffers({
    required Team team,
    required SponsorSlot slot,
    required int year,
    Set<String> excludeBrands = const {},
    int? lastPosition,
    int? count,
  }) {
    final used = {...excludeBrands};
    final target = count ?? (2 + rng.nextInt(3));
    final offers = <SponsorshipOffer>[];
    for (var i = 0; i < target; i++) {
      final offer = _offer(
        team: team,
        slot: slot,
        year: year,
        usedBrands: used,
        lastPosition: lastPosition,
        index: i,
      );
      used.add(offer.brand);
      offers.add(offer);
    }
    return offers;
  }

  /// Turns a signed offer into the deal that rides the books.
  Sponsorship sign(SponsorshipOffer offer) => Sponsorship(
        slot: offer.slot,
        brand: offer.brand,
        annualValue: offer.annualValue,
        startYear: offer.year,
        durationYears: offer.durationYears,
        prestige: offer.prestige,
        clause: offer.clause,
      );

  /// The offers still on the table for [slot], best money first.
  List<SponsorshipOffer> offersForSlot(
    List<SponsorshipOffer> offers,
    SponsorSlot slot,
  ) {
    final mine = [for (final o in offers) if (o.slot == slot) o]
      ..sort((a, b) => b.annualValue.compareTo(a.annualValue));
    return mine;
  }

  /// The offer the board would sign if the manager never makes up his mind:
  /// the best annual value on the table.
  SponsorshipOffer? bestOffer(List<SponsorshipOffer> offers) {
    if (offers.isEmpty) return null;
    return (offers.toList()
          ..sort((a, b) => b.annualValue.compareTo(a.annualValue)))
        .first;
  }

  /// Settles every performance clause that rode a deal active in [year].
  ///
  /// Returns one entry per clause that paid; a clause that missed its target
  /// simply pays nothing and is not listed.
  List<SponsorshipSettlement> settleClauses({
    required List<Sponsorship> deals,
    required int year,
    required int leaguePosition,
    required int leagueGoals,
    required bool cupWon,
  }) {
    final settlements = <SponsorshipSettlement>[];
    for (final deal in deals) {
      final clause = deal.clause;
      if (clause == null || !deal.isActiveIn(year)) continue;
      switch (clause.kind) {
        case ClauseKind.leagueTop:
          if (leaguePosition > 0 && leaguePosition <= clause.threshold) {
            settlements.add(SponsorshipSettlement(
              deal: deal,
              amount: clause.amount,
              reason: 'Top-${clause.threshold} finish',
            ));
          }
        case ClauseKind.cupWin:
          if (cupWon) {
            settlements.add(SponsorshipSettlement(
              deal: deal,
              amount: clause.amount,
              reason: 'Cup winners',
            ));
          }
        case ClauseKind.goals:
          if (leagueGoals > 0) {
            settlements.add(SponsorshipSettlement(
              deal: deal,
              amount: clause.amount * leagueGoals,
              reason: '$leagueGoals league goals',
            ));
          }
      }
    }
    return settlements;
  }

  /// Every slot's deal for [year], keeping deals that are still running.
  ///
  /// Kept for saves written before offers existed and for the finance repair
  /// on load: a club that reaches a season with an unsold shirt and no offers
  /// to choose from must never silently earn nothing from it. The values are
  /// freshly drawn from the market, so a fallback sale still looks like a
  /// negotiation rather than a formula.
  List<Sponsorship> ensureDeals({
    required List<Sponsorship> existing,
    required Team team,
    required int year,
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
      final offer = _offer(
        team: team,
        slot: slot,
        year: year,
        usedBrands: used,
        lastPosition: null,
        index: fresh.length,
      );
      final deal = sign(offer);
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
