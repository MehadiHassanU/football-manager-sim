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

  int calculateTransferValue(Player player) {
    final base = player.ovr * 100000;
    final ageFactor = player.age < 24
        ? 1.5
        : player.age < 30
            ? 1.0
            : 0.6;
    final positionFactor = {
      'ST': 1.3, 'GK': 0.8, 'CB': 0.9, 'CDM': 0.85,
    }[player.primaryPosition] ?? 1.0;
    return (base * ageFactor * positionFactor).round();
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