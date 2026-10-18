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

/// One commercial deal: who pays, how much a year, and how long it runs.
///
/// Deals are the club's steady income. A share of the annual value lands on
/// every matchday instead of arriving as a lump sum on day one, and a deal
/// that has run its course is replaced on the summer rollover with a
/// renegotiated one. Real kit contracts average around three years, so the
/// terms here are short enough that the board can still see a renewal.
class Sponsorship {
  Sponsorship({
    required this.slot,
    required this.brand,
    required this.annualValue,
    required this.startYear,
    required this.durationYears,
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
    return Sponsorship(
      slot: slot,
      brand: brand,
      annualValue: value.toDouble(),
      startYear: start.toInt(),
      durationYears: ((years is num) ? years.toInt() : 1).clamp(1, 10),
    );
  }
}
