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

  /// Rough per-match gate receipts from capacity and reputation.
  double estimateGateReceipts(Team team) {
    final avgTicket = 35 + team.reputation * 0.35;
    final attendance =
        team.stadiumCapacity * (0.55 + (team.fanTrust / 100) * 0.4);
    return attendance * avgTicket;
  }

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