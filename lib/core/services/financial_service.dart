import 'dart:math';

import '../models/player.dart';
import '../models/team.dart';
import '../constants/game_constants.dart';

class FinancialService {
  final Random rng;

  FinancialService({Random? rng}) : rng = rng ?? Random();

  double calculateWageBill(Team team) {
    double total = 0.0;
    for (final p in team.squad) {
      total += p.weeklyWage;
    }
    return total;
  }

  double calculateFFPRatio(Team team) {
    final wageBill = calculateWageBill(team);
    final revenue = team.revenue != 0 ? team.revenue : 1000000.0;
    return wageBill / revenue;
  }

  bool isFFPCompliant(Team team) {
    return calculateFFPRatio(team) <= ffpWageRatioLimit;
  }

  /// Market value of [player] in euros.
  ///
  /// The old formula (ovr × €100k × age × position) priced a 91 OVR striker at
  /// about €12M, so any mid-table budget could buy the entire elite. This is a
  /// curve instead: ≈€5M at 70 OVR, €27M at 80, €61M at 85, €138M at 90 and
  /// €247M at 94 before the age, contract and position multipliers.
  int calculateTransferValue(Player player, {int? seasonYear}) {
    final refYear = seasonYear ?? DateTime.now().year;
    final millions = pow(1.18, player.ovr - 60).toDouble();
    var value = millions * 1000000;
    value *= _ageFactor(player.age);
    value *= _positionFactor(player.primaryPosition);
    value *= _contractFactor(player.contractExpiry, refYear);
    // Form swings a valuation by at most ±10%, morale by ±5%.
    final form = ((player.form - 5) / 50).clamp(-0.10, 0.10);
    final morale = ((player.morale - 75) / 500).clamp(-0.05, 0.05);
    value *= 1 + form + morale;
    // Round to the nearest €10k so fees read like real bids.
    return (value / 10000).round() * 10000;
  }

  double _ageFactor(int age) {
    if (age <= 20) return 1.35;
    if (age <= 24) return 1.20;
    if (age <= 28) return 1.05;
    if (age <= 31) return 0.65;
    if (age <= 34) return 0.35;
    return 0.15;
  }

  double _positionFactor(String position) {
    const factors = {
      'ST': 1.25,
      'CF': 1.20,
      'LW': 1.15,
      'RW': 1.15,
      'CAM': 1.15,
      'AM': 1.10,
      'CM': 1.00,
      'CDM': 1.00,
      'LM': 1.00,
      'RM': 1.00,
      'CB': 0.95,
      'LB': 0.90,
      'RB': 0.90,
      'GK': 0.80,
    };
    return factors[position] ?? 1.0;
  }

  /// A player in the final year of his deal is a bargain; one who is already
  /// out of contract is nearly free.
  double _contractFactor(DateTime? expiry, int refYear) {
    if (expiry == null) return 1.0;
    final years = expiry.year - refYear;
    if (years <= 0) return 0.35;
    if (years == 1) return 0.65;
    return 1.0;
  }

  /// The weekly wage a player of this quality expects, in euros.
  ///
  /// ≈€8k at 60 OVR, €22k at 70, €58k at 80, €157k at 90, €240k at 94.
  double expectedWeeklyWage(Player player) {
    final weekly = pow(2, (player.ovr - 60) / 7) * 8000;
    return (weekly / 100).round() * 100.0;
  }

  /// Broadcast money per league match, paid wherever the match is played.
  ///
  /// Half a week's wage bill, so an away match is not a loss-making
  /// formality: the clubs with the biggest wage bills also collect the
  /// biggest cheques, at roughly the ratio the real distribution deals use.
  double broadcastPerMatch(int reputation) {
    final weekly = _commercialBase(reputation) / kWeeksPerYear;
    return (weekly * 0.5 / 50000).round() * 50000.0;
  }

  /// Annual value of the front-of-shirt deal.
  ///
  /// The biggest of the three kit slots; the back patch takes 40% of it and
  /// the sleeve 30%. Sized off the same wage anchor as everything else, so it
  /// scales from a few million at the bottom to eight figures at the top
  /// instead of paying a fourth-tier club big-six money.
  double frontOfShirtValue(int reputation) {
    final base = _commercialBase(reputation) * 0.206;
    return (base / 100000).round() * 100000.0;
  }

  /// Merit prize for finishing [position] of [clubCount].
  ///
  /// Real leagues pay by the place: the champion banks the full cheque and
  /// last place a token share, so finishing one spot higher is worth real
  /// money to the board.
  double meritPrize(int reputation, int position, int clubCount) {
    if (clubCount <= 0) return 0;
    final champion = _commercialBase(reputation) * 0.12;
    final place = position.clamp(1, clubCount);
    final share = (clubCount - place + 1) / clubCount;
    return (champion * share / 50000).round() * 50000.0;
  }

  /// A realistic stadium capacity for a club of [reputation].
  ///
  /// The old flat `30000 + ovr × 400` gave every club an almost identical
  /// ground, so attendance meant nothing. These bands run from seven-figure
  /// crowds at the bottom to a 60-80k arena at the top, with a deterministic
  /// per-club spread so no two grounds are twins and the same club always
  /// keeps the same ground.
  int realisticCapacity(int reputation, String teamId) {
    final base = switch (reputation) {
      >= 86 => 68000,
      >= 82 => 48000,
      >= 79 => 34000,
      >= 76 => 26000,
      >= 73 => 19000,
      >= 70 => 13000,
      _ => 9000,
    };
    var hash = 0;
    for (final code in teamId.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    final factor = 0.87 + (hash % 27) / 100.0; // 0.87 .. 1.13
    return ((base * factor) / 500).round() * 500;
  }

  /// What a squad at [reputation] costs over a year.
  ///
  /// Reputation tracks average squad rating (see `_reputationFor`), so this is
  /// the 25-man annual bill implied by the club's level. Every commercial
  /// number is a fraction of it, which keeps the whole economy on one scale:
  /// a small club's deal is small, but it is the same kind of deal.
  double _commercialBase(int reputation) {
    final ovr = ((reputation - 40) / 0.55).clamp(55.0, 90.0).toDouble();
    final weekly = pow(2, (ovr - 60) / 7) * 8000;
    return (weekly * 25 * kWeeksPerYear).toDouble();
  }

  /// Rough per-match gate receipts from capacity and reputation.
  ///
  /// Ticket prices follow the club's level like the rest of the model does —
  /// an elite ground charges elite prices, a fourth-tier ground pocket money —
  /// so a full house is a fortune at one club and small change at another
  /// instead of a flat €60 everywhere.
  double estimateGateReceipts(Team team) {
    final attendance =
        team.stadiumCapacity * (0.55 + (team.fanTrust / 100) * 0.4);
    return attendance * _ticketPrice(team.reputation);
  }

  double _ticketPrice(int reputation) => switch (reputation) {
        >= 86 => 55,
        >= 82 => 38,
        >= 79 => 28,
        >= 76 => 22,
        >= 73 => 16,
        >= 70 => 12,
        _ => 9,
      };

  Map<String, dynamic> generateFinancialReport(Team team) {
    final wageBill = calculateWageBill(team);
    final ffpRatio = calculateFFPRatio(team);
    return {
      'wageBill': wageBill,
      'transferBudget': team.transferBudget,
      'totalBudget': team.budget,
      'ffpRatio': ffpRatio,
      'ffpCompliant': ffpRatio <= ffpWageRatioLimit,
      'revenue': team.revenue,
    };
  }

  double estimatePlayerValueForSale(Player player, {bool isSelling = true}) {
    final baseValue = calculateTransferValue(player);
    if (isSelling) {
      return (baseValue * (0.8 + rng.nextDouble() * 0.4)).roundToDouble();
    }
    return (baseValue * (1.0 + rng.nextDouble() * 0.3)).roundToDouble();
  }

  Map<String, dynamic> calculateTransferOffer(Player player, int fee, double wage, int years) {
    final playerValue = calculateTransferValue(player);
    final feeRatio = fee / playerValue;
    return {
      'fairPrice': playerValue,
      'offeredFee': fee,
      'feeRatio': feeRatio,
      'isOverpay': feeRatio > 1.2,
      'isUnderpay': feeRatio < 0.7,
      'weeklyWage': wage,
      'contractYears': years,
      'totalCost': fee + (wage * 52 * years),
      'recommendation': feeRatio > 1.5
          ? 'overpay'
          : feeRatio > 1.2
              ? 'fair'
              : feeRatio < 0.5
                  ? 'low_ball'
                  : 'good_value',
    };
  }
}