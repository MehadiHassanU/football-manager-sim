/// The three kit slots a club sells, in the order the finances sheet shows
/// them: front of shirt, the mid-back patch, and the sleeve.
enum SponsorSlot {
  front('Front of shirt'),
  back('Back of shirt'),
  sleeve('Sleeve');

  const SponsorSlot(this.label);

  /// Human label for the finances sheet.
  final String label;

  /// Save-file key: the enum name, so reordering the enum cannot silently
  /// swap a saved deal into another slot.
  String get key => name;
}

/// What a performance clause pays on.
///
/// Real kit contracts rarely pay a flat fee: the money is split between the
/// guaranteed annual value and bonuses the club can earn on the pitch. One
/// clause rides with each deal that carries one, settled when the season ends.
enum ClauseKind {
  /// A lump sum if the club finishes inside the top [SponsorshipClause.threshold].
  leagueTop,

  /// A lump sum if the club wins the domestic cup.
  cupWin,

  /// A per-goal payment on the club's league goals.
  goals,
}

/// The one performance clause attached to a deal.
class SponsorshipClause {
  const SponsorshipClause({
    required this.kind,
    required this.amount,
    this.threshold = 0,
  });

  final ClauseKind kind;

  /// The lump sum, or for [ClauseKind.goals] the payment per league goal.
  final double amount;

  /// The league position the clause pays on, for [ClauseKind.leagueTop].
  final int threshold;

  /// One-line name for lists: 'Top-4 finish', 'Cup winners', 'Per league goal'.
  String get label => switch (kind) {
        ClauseKind.leagueTop => 'Top-$threshold finish',
        ClauseKind.cupWin => 'Cup winners',
        ClauseKind.goals => 'Per league goal',
      };

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'amount': amount,
        if (threshold > 0) 'threshold': threshold,
      };

  /// Rebuilds a clause from the save blob, or null when the record is damaged
  /// — a deal without its bonus is still a deal.
  static SponsorshipClause? fromJson(Map<String, dynamic> json) {
    final amount = json['amount'];
    if (amount is! num || amount <= 0) return null;
    for (final kind in ClauseKind.values) {
      if (kind.name == json['kind']) {
        return SponsorshipClause(
          kind: kind,
          amount: amount.toDouble(),
          threshold: ((json['threshold'] as num?)?.toInt() ?? 0).clamp(0, 30),
        );
      }
    }
    return null;
  }
}

/// One commercial deal: who pays, how much a year, how long it runs and what
/// bonus it carries.
///
/// Deals are the club's steady income. A share of the annual value lands on
/// every matchday instead of arriving as a lump sum on day one, and a deal
/// whose term has run out is put back on the market as fresh offers. Real kit
/// contracts average around three years, so the terms here are short enough
/// that the board can still see a renewal.
class Sponsorship {
  Sponsorship({
    required this.slot,
    required this.brand,
    required this.annualValue,
    required this.startYear,
    required this.durationYears,
    this.prestige = 3,
    this.clause,
  });

  final SponsorSlot slot;

  /// The fake brand the deal is signed with.
  final String brand;

  /// Euros per year, paid in weekly instalments across the season.
  final double annualValue;

  /// First season the deal covers.
  final int startYear;

  /// Number of seasons covered, [startYear] included.
  final int durationYears;

  /// How big a name the brand is, 1–5. Saves written before offers existed
  /// carry no rating, so the default sits in the middle.
  final int prestige;

  /// The performance bonus, when the brand insisted on one.
  final SponsorshipClause? clause;

  /// Last season the deal covers.
  int get endYear => startYear + durationYears - 1;

  bool isActiveIn(int year) => year >= startYear && year <= endYear;

  /// Seasons still to run, counting the current one. Zero once expired.
  int yearsRemaining(int year) => (endYear - year + 1).clamp(0, durationYears);

  Map<String, dynamic> toJson() => {
        'slot': slot.key,
        'brand': brand,
        'annualValue': annualValue,
        'startYear': startYear,
        'durationYears': durationYears,
        'prestige': prestige,
        if (clause != null) 'clause': clause!.toJson(),
      };

  /// Rebuilds a deal from the save blob, or null when the record is damaged.
  ///
  /// A malformed entry must not take the whole career down with it: the
  /// finance repair on load treats a null as "this slot is unsold" and signs
  /// a fresh deal.
  static Sponsorship? fromJson(Map<String, dynamic> json) {
    SponsorSlot? slot;
    for (final candidate in SponsorSlot.values) {
      if (candidate.key == json['slot']) slot = candidate;
    }
    final brand = json['brand'];
    final value = json['annualValue'];
    final start = json['startYear'];
    final years = json['durationYears'];
    if (slot == null ||
        brand is! String ||
        value is! num ||
        start is! num) {
      return null;
    }
    final clause = json['clause'];
    return Sponsorship(
      slot: slot,
      brand: brand,
      annualValue: value.toDouble(),
      startYear: start.toInt(),
      durationYears: ((years is num) ? years.toInt() : 1).clamp(1, 10),
      prestige: ((json['prestige'] as num?)?.toInt() ?? 3).clamp(1, 5),
      clause: clause is Map
          ? SponsorshipClause.fromJson(Map<String, dynamic>.from(clause))
          : null,
    );
  }
}

/// An offer on the table for a free slot, awaiting the manager's signature.
///
/// Offers are what the market actually looks like: two to four brands, each
/// with its own money, term, criteria and bonus clause, and never the same
/// shortlist twice. Nothing is signed automatically while the window is open —
/// the manager picks. The board only steps in when the season starts, signing
/// the best offer still on the table so the club is never left with an unsold
/// shirt.
class SponsorshipOffer {
  const SponsorshipOffer({
    required this.id,
    required this.slot,
    required this.brand,
    required this.prestige,
    required this.requirement,
    required this.annualValue,
    required this.durationYears,
    required this.year,
    this.clause,
  });

  /// Stable within the offer's life, so the UI can key cards.
  final String id;

  final SponsorSlot slot;
  final String brand;

  /// How big a name the brand is, 1–5.
  final int prestige;

  /// The criterion the brand attaches to the deal. Offers are only ever made
  /// to clubs that already satisfy it — it is shown so the manager can see
  /// what the brand is paying for.
  final String requirement;

  /// Euros per year on offer.
  final double annualValue;

  /// Number of seasons the brand wants to commit for.
  final int durationYears;

  /// The season the offer was made for.
  final int year;

  /// The bonus clause the brand is asking for, or null for a flat deal.
  final SponsorshipClause? clause;

  Map<String, dynamic> toJson() => {
        'id': id,
        'slot': slot.key,
        'brand': brand,
        'prestige': prestige,
        'requirement': requirement,
        'annualValue': annualValue,
        'durationYears': durationYears,
        'year': year,
        if (clause != null) 'clause': clause!.toJson(),
      };

  /// Rebuilds an offer from the save blob, or null when the record is damaged.
  static SponsorshipOffer? fromJson(Map<String, dynamic> json) {
    SponsorSlot? slot;
    for (final candidate in SponsorSlot.values) {
      if (candidate.key == json['slot']) slot = candidate;
    }
    final brand = json['brand'];
    final value = json['annualValue'];
    final year = json['year'];
    if (slot == null || brand is! String || value is! num || year is! num) {
      return null;
    }
    final clause = json['clause'];
    return SponsorshipOffer(
      id: json['id'] is String ? json['id'] as String : '$brand-${slot.key}',
      slot: slot,
      brand: brand,
      prestige: ((json['prestige'] as num?)?.toInt() ?? 3).clamp(1, 5),
      requirement: json['requirement'] is String
          ? json['requirement'] as String
          : 'Top-flight football',
      annualValue: value.toDouble(),
      durationYears: ((json['durationYears'] as num?)?.toInt() ?? 1).clamp(1, 10),
      year: year.toInt(),
      clause: clause is Map
          ? SponsorshipClause.fromJson(Map<String, dynamic>.from(clause))
          : null,
    );
  }
}
