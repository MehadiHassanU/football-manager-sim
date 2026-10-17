import 'dart:math';

import '../models/player.dart';
import '../models/team.dart';
import '../models/transfer.dart';
import 'financial_service.dart';

/// Result of a bid against a selling club.
class BidResult {
  const BidResult({
    required this.outcome,
    required this.counter,
    required this.patience,
    required this.round,
    required this.message,
  });

  final BidOutcome outcome;

  /// The seller's counter-offer, or 0 when there is none.
  final int counter;
  final int patience;
  final int round;
  final String message;
}

/// Result of offering personal terms to a player.
class TermsResult {
  const TermsResult({
    required this.accepted,
    required this.message,
    this.counterWage = 0,
  });

  final bool accepted;
  final String message;

  /// What his agent says he actually wants, when the offer is short.
  final int counterWage;
}

/// All the pure transfer-market rules.
///
/// Everything here is deterministic: rivals, counters and incoming bids are
/// seeded from the player id and the matchday, so a reloaded save makes the
/// same decisions rather than rerolling until the manager gets a good deal.
class TransferMarketService {
  const TransferMarketService();

  /// The seller's public asking price.
  ///
  /// Starts from the market value, then adjusts for contract length, whether
  /// the player is listed or wants out, how important he is to the seller and
  /// whether the buyer is a direct league rival.
  int askingPrice(
    Player player,
    Team? seller, {
    required int seasonYear,
    Team? buyer,
  }) {
    if (isFreeAgent(player, seasonYear)) return 0;
    final value = FinancialService()
        .calculateTransferValue(player, seasonYear: seasonYear)
        .toDouble();
    var multiplier = 1.12;
    final expiryYear = player.contractExpiry?.year;
    if (expiryYear != null && expiryYear - seasonYear <= 1) multiplier -= 0.12;
    if (player.hiddenAttributes['transferListed'] == true) multiplier -= 0.15;
    if (player.requestedTransfer) multiplier -= 0.10;
    if (seller != null && seller.squad.isNotEmpty) {
      final average = seller.squad
              .fold<int>(0, (sum, p) => sum + p.ovr) /
          seller.squad.length;
      if (player.ovr >= average + 8) multiplier += 0.12;
    }
    if (buyer != null &&
        seller != null &&
        buyer.id != seller.id &&
        buyer.leagueId == seller.leagueId) {
      // Selling to a direct rival costs more.
      multiplier += 0.12;
    }
    multiplier = multiplier.clamp(0.75, 1.55);
    return (value * multiplier / 100000).round() * 100000;
  }

  int reservationPrice(int askingPrice) =>
      askingPrice <= 0 ? 0 : (askingPrice * 0.82 / 100000).round() * 100000;

  /// A player whose contract has run out is available outside the window for
  /// nothing. Contracts are backfilled to end on June 30, so comparing years is
  /// enough and never depends on today's date.
  bool isFreeAgent(Player player, int seasonYear) =>
      player.contractExpiry != null &&
      player.contractExpiry!.year <= seasonYear;

  bool canSign(TransferWindow window, bool freeAgent) =>
      window.isOpen || freeAgent;

  int requiredReputation(Player player) =>
      (40 + player.ovr * 0.5).round().clamp(45, 95);

  /// What the player's agent wants per week from [buyer].
  ///
  /// A club below his level has to pay a premium; an older player is slightly
  /// more flexible.
  int wageDemand(Player player, Team buyer) {
    final base = FinancialService().expectedWeeklyWage(player);
    final gap = (requiredReputation(player) - buyer.reputation).clamp(0, 40);
    var multiplier = 1 + gap / 80;
    if (player.age >= 31) multiplier *= 0.9;
    return (base * multiplier / 100).round() * 100;
  }

  /// Evaluates a bid. The ask is public; the reservation is not.
  BidResult evaluateBid({
    required int asking,
    required int reservation,
    required int offer,
    required int round,
    required int patience,
    required int seed,
  }) {
    if (asking <= 0) {
      return BidResult(
        outcome: BidOutcome.accepted,
        counter: 0,
        patience: patience,
        round: round + 1,
        message: 'Free agent — no fee is needed.',
      );
    }
    if (offer >= asking) {
      return BidResult(
        outcome: BidOutcome.accepted,
        counter: 0,
        patience: patience,
        round: round + 1,
        message: 'They accept your ${money(offer)} offer.',
      );
    }

    final insulting = offer < reservation * 0.85;
    final nextPatience = patience - (insulting ? 2 : 1);
    final bidNumber = round + 1;

    if (bidNumber >= 3 || nextPatience <= 0) {
      return BidResult(
        outcome: BidOutcome.collapsed,
        counter: 0,
        patience: 0,
        round: bidNumber,
        message: insulting
            ? 'They are insulted by ${money(offer)} and end talks.'
            : 'Talks have ended after three bids.',
      );
    }

    final counter = offer >= reservation
        ? (((asking + offer) / 2) / 100000).round() * 100000
        : asking;
    final counterPatience = nextPatience;
    final rng = Random(seed);
    final opener = insulting
        ? 'They are unhappy with ${money(offer)}.'
        : rng.nextBool()
            ? 'They reject ${money(offer)}.'
            : '${money(offer)} is not enough.';
    return BidResult(
      outcome: BidOutcome.countered,
      counter: counter,
      patience: counterPatience,
      round: bidNumber,
      message: '$opener They want ${money(counter)}.',
    );
  }

  /// Whether the player accepts the contract on offer.
  ///
  /// The wage is annualised with the signing bonus so a big bonus can bridge a
  /// small weekly gap, and a club below his level has to overpay.
  TermsResult evaluateTerms({
    required Player player,
    required Team buyer,
    required int wage,
    required int bonus,
    required int years,
    required String role,
  }) {
    final demand = wageDemand(player, buyer);
    final roleMultiplier = role == 'Key Player'
        ? 0.92
        : role == 'Rotation'
            ? 1.05
            : 1.0;
    final target = demand * roleMultiplier;
    final effective = wage + bonus / (52.0 * max(1, years));
    final required = requiredReputation(player);
    final gap = required - buyer.reputation;

    // A club well below his level cannot buy prestige with a normal wage; it
    // has to blow him away. This is what stops a mid-table club signing the
    // entire elite just because it has cash.
    if (gap > 8) {
      if (effective >= target * 1.5) {
        return const TermsResult(
          accepted: true,
          message: 'The money convinced him. He signs.',
        );
      }
      return TermsResult(
        accepted: false,
        counterWage: (target * 1.5).round(),
        message: 'He wants to play at a bigger club. '
            'Only a huge wage (${money((target * 1.5).round())}/wk) would '
            'change his mind.',
      );
    }
    // A first-team player will not accept a bench role at a smaller club.
    if (role == 'Rotation' && player.ovr >= 82 && effective < target * 1.2) {
      return TermsResult(
        accepted: false,
        counterWage: (target * 1.2).round(),
        message: 'He is not convinced by the squad role on offer. '
            'He wants a bigger wage to accept rotation.',
      );
    }
    if (effective >= target * 0.95) {
      return const TermsResult(
        accepted: true,
        message: 'He is happy with the contract and the project.',
      );
    }
    return TermsResult(
      accepted: false,
      counterWage: target.round(),
      message: "His agent wants ${money(target.round())} a week.",
    );
  }

  /// A deterministic rival for a target, or null when nobody is competing.
  String? rivalClubFor(
    Player player,
    List<Team> eliteClubs, {
    required int seasonYear,
  }) {
    if (player.ovr < 78) return null;
    final rng = Random(player.id * 7919 + seasonYear * 131);
    if (rng.nextDouble() > 0.25) return null;
    final required = requiredReputation(player);
    final candidates = [
      for (final club in eliteClubs)
        if (club.name != player.currentTeam && club.reputation >= required - 5)
          club,
    ];
    if (candidates.isEmpty) return null;
    return candidates[rng.nextInt(candidates.length)].name;
  }

  /// A club that might bid for one of the manager's players.
  String? incomingClubFor(
    Player player,
    List<Team> teams,
    Team seller, {
    required int seasonYear,
    required int matchday,
  }) {
    final rng = Random(player.id * 104729 + matchday * 31 + seasonYear);
    final nearby = [
      for (final team in teams)
        if (team.id != seller.id &&
            (team.reputation - seller.reputation).abs() <= 15)
          team,
    ];
    final pool = nearby.isNotEmpty ? nearby : teams;
    if (pool.isEmpty) return null;
    return pool[rng.nextInt(pool.length)].name;
  }

  int incomingFee(Player player, {required int seasonYear, required int matchday}) {
    final value =
        FinancialService().calculateTransferValue(player, seasonYear: seasonYear);
    final rng = Random(player.id * 15485863 + matchday);
    final factor = 0.80 + rng.nextDouble() * 0.35;
    return (value * factor / 100000).round() * 100000;
  }

  /// Precomputes the whole market once so the screen never values 16,000
  /// players inside a list builder.
  List<MarketListing> buildListings({
    required List<Player> players,
    required List<Team> teams,
    required int seasonYear,
    Team? buyer,
  }) {
    final finance = FinancialService();
    final byName = {for (final team in teams) team.name: team};
    final elite = [
      for (final team in teams)
        if (team.reputation >= 78) team,
    ];
    final listings = <MarketListing>[];
    for (final player in players) {
      final seller = byName[player.currentTeam];
      final free = isFreeAgent(player, seasonYear);
      listings.add(
        MarketListing(
          player: player,
          seller: seller,
          value: finance.calculateTransferValue(player, seasonYear: seasonYear),
          askingPrice: free
              ? 0
              : askingPrice(
                  player,
                  seller,
                  seasonYear: seasonYear,
                  buyer: buyer,
                ),
          weeklyWage: finance.expectedWeeklyWage(player),
          freeAgent: free,
          rivalClub: free
              ? null
              : rivalClubFor(
                  player,
                  [
                    for (final club in elite)
                      if (club.id != buyer?.id) club,
                  ],
                  seasonYear: seasonYear,
                ),
        ),
      );
    }
    return listings;
  }

  /// Repairs the data the market needs on old saves and on CSV players.
  ///
  /// CSV players arrive with no contract (wage 0, no expiry, no value), and
  /// saves created before the market existed persisted those zeroes. Only
  /// missing values are filled, so an established career keeps the deals it
  /// already agreed. Reputation is only recomputed for clubs still sitting on
  /// the old default of 70, which is how pre-reputation saves are detected.
  void backfillTransferData(Iterable<Team> teams, int seasonYear) {
    final finance = FinancialService();
    for (final team in teams) {
      if (team.squad.isEmpty) continue;
      // The weekly wage ceiling comes from the bill the club already carries:
      // a board sanctions what it has been paying plus a slice of headroom,
      // not a number picked out of the air. Only set when it is missing, so a
      // persisted budget survives a reload.
      if (team.wageBudget <= 0) {
        final bill = finance.calculateWageBill(team) + team.loanedOutWages;
        team.wageBudget = bill > 0 ? (bill * 1.15).roundToDouble() : 0;
      }
      if (team.reputation == 70) {
        final average = team.squad.fold<int>(0, (sum, p) => sum + p.ovr) /
            team.squad.length;
        team.reputation = (40 + average * 0.55).round().clamp(40, 95);
      }
      for (final player in team.squad) {
        if (player.weeklyWage <= 0) {
          player.weeklyWage = finance.expectedWeeklyWage(player);
        }
        if (player.transferValue <= 0) {
          player.transferValue =
              finance.calculateTransferValue(player, seasonYear: seasonYear);
        }
        // 1-4 years left, never "already expired": adding 0 here made a
        // quarter of the database a free agent on the first day of a career.
        player.contractExpiry ??=
            DateTime(seasonYear + 1 + (player.id.abs() % 4), 6, 30);
      }
    }
  }

  /// Replays the world's completed moves onto a freshly parsed database.
  ///
  /// Only the user's club is saved; every other squad comes back from the CSV,
  /// so without this a sold player would reappear at his old club, a hijack
  /// would never have happened, and last season's loans would still be running.
  ///
  /// Idempotent: a move already applied changes nothing.
  void applyTransferLedger({
    required List<Player> players,
    required List<Team> teams,
    required List<TransferMove> moves,
    required String userClub,
  }) {
    if (moves.isEmpty) return;
    final byId = {for (final player in players) player.id: player};
    final clubsByName = {for (final team in teams) team.name: team};

    for (final move in moves) {
      final player = byId[move.playerId];
      if (player == null) continue;

      // Step one: nobody still holds him. The user's own mirror squad is left
      // alone because the saved squad is the authority for that club.
      for (final team in teams) {
        if (team.name == userClub) continue;
        team.squad.removeWhere((p) => p.id == move.playerId);
      }

      player.currentTeam = move.toClub;
      if (move.wage > 0) player.weeklyWage = move.wage.toDouble();

      if (move.toClub == userClub) continue;
      final buyer = clubsByName[move.toClub];
      if (buyer == null) continue;
      if (!buyer.squad.any((p) => p.id == move.playerId)) {
        buyer.squad.add(player);
      }
    }
  }

  /// The weekly wage a wage-share share of [player] costs a borrowing club.
  int loanCost(Player player, int wageSharePercent) =>
      (player.weeklyWage * wageSharePercent / 100).round();

  /// Whether a club would let a player leave on loan, and whether he is good
  /// enough to be wanted. A squad player at a strong club is the classic loan
  /// target; a first-teamer is not going anywhere.
  bool loanAvailable(Player player, Team? owner) {
    if (owner == null || owner.squad.length <= 16) return false;
    if (player.hiddenAttributes['transferListed'] == true) return true;
    if (player.requestedTransfer) return true;
    final average =
        owner.squad.fold<int>(0, (sum, p) => sum + p.ovr) / owner.squad.length;
    return player.ovr <= average + 2 && player.age <= 23;
  }

  /// What a club expects as its share of the wage for loaning a player out.
  /// Stronger clubs push more of the bill onto the borrower.
  int loanWageShare(Player player, Team? owner) {
    if (owner == null) return 50;
    if (player.age <= 23 && player.ovr < 72) return 30;
    if (player.requestedTransfer ||
        player.hiddenAttributes['transferListed'] == true) {
      return 40;
    }
    return 60;
  }

  static String money(num amount) {
    if (amount >= 1000000000) {
      return '€${(amount / 1000000000).toStringAsFixed(1)}B';
    }
    if (amount >= 1000000) {
      return '€${(amount / 1000000).toStringAsFixed(1)}M';
    }
    if (amount >= 1000) return '€${(amount / 1000).toStringAsFixed(0)}K';
    return '€${amount.toStringAsFixed(0)}';
  }
}
