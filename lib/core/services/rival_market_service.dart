import 'dart:math';

import '../models/player.dart';
import '../models/team.dart';
import 'financial_service.dart';
import 'transfer_market_service.dart';

/// One transfer rival clubs agreed between themselves.
///
/// The service only *generates* the deal; the career session applies it to
/// the world (squads, the [TransferMove] ledger, the news feed), which keeps
/// the world mutation and persistence in one place.
class RivalDeal {
  const RivalDeal({
    required this.player,
    required this.seller,
    required this.buyer,
    required this.fee,
    required this.wage,
  });

  final Player player;
  final Team seller;
  final Team buyer;
  final int fee;
  final int wage;
}

/// Spontaneous transfer activity by AI clubs.
///
/// The career's league used to stand still: rival squads never changed,
/// nobody's transfers were visible and each season replayed the same table.
/// This service gives every other club a small, seeded, budget- and
/// ceiling-aware chance to improve its weakest area each matchday — with
/// clubs that just lost a player to the manager hunting a replacement
/// harder than anyone else.
///
/// Determinism contract: calling `generateMoves` twice with identical inputs
/// and an un-mutated world produces identical deals. The career session
/// reproduces the same behavior on a restored save, because every decision
/// is rolled from the same `seedKey:year:matchday` hash and the squad state
/// it reads has already been rebuilt by the ledger replay.
class RivalTransferService {
  /// Moves for one matchday while the window is open.
  ///
  /// [seedKey] must be stable across restores for the same career (the
  /// session passes the league id); together with the year and the matchday
  /// it forms the RNG seed, following the convention rival sim results use.
  ///
  /// [priorityBuyers] are clubs the user has bought from during the current
  /// window; they roll with a much higher chance to replace the player they
  /// lost, which is what makes the league read as reactive rather than
  /// ambient noise.
  ///
  /// [busyPlayers] are the player ids in the user's live negotiations; they
  /// are excluded so a random rival never quietly resolves a deal the user
  /// is actually in — that is the hijack system's job.
  List<RivalDeal> generateMoves({
    required List<Team> teams,
    required String userClub,
    required String seedKey,
    required int seasonYear,
    required int matchday,
    required Set<String> priorityBuyers,
    required Set<int> busyPlayers,
    double activityMultiplier = 1.0,
  }) {
    final rng = Random('$seedKey:$seasonYear:$matchday'.hashCode.abs());
    final service = TransferMarketService();
    final finance = FinancialService();

    // Purchasable pool: everyone outside the manager's squad.
    final sellers = {for (final team in teams) team.name: team};
    final targets = <Player>[
      for (final team in teams)
        if (team.name != userClub)
          for (final player in team.squad)
            if (!busyPlayers.contains(player.id)) player,
    ];

    // Iteration order is the database order, which is stable across a
    // restore, so the seed reproduces which clubs acted and when.
    final buyers = [
      for (final team in teams)
        if (team.name != userClub && team.squad.length >= kMinRivalSquad) team,
    ];

    final deals = <RivalDeal>[];
    for (final buyer in buyers) {
      if (deals.length >= kMaxDealsPerMatchday) break;

      final priority = priorityBuyers.contains(buyer.name);
      final chance =
          (kBaseActChance + (priority ? kPriorityActChance : 0)) *
              activityMultiplier;
      if (rng.nextDouble() > chance) continue;

      final deal = _pickDeal(
        rng: rng,
        buyer: buyer,
        sellers: sellers,
        targets: targets,
        seasonYear: seasonYear,
        priority: priority,
        service: service,
        finance: finance,
      );
      if (deal == null) continue;
      deals.add(deal);
    }
    return deals;
  }

  /// Chooses one purchase for [buyer], or null when nothing fits.
  ///
  /// The constraints mirror the manager's own rules: the asking price must
  /// fit the club's budget slice for this deal, the wage must fit the club's
  /// weekly ceiling (same bill + loaned-out maths the desk uses for the
  /// user), the reputation must plausibly allow the player, and the club
  /// buys towards its weakest position group.
  RivalDeal? _pickDeal({
    required Random rng,
    required Team buyer,
    required Map<String, Team> sellers,
    required List<Player> targets,
    required int seasonYear,
    required bool priority,
    required TransferMarketService service,
    required FinancialService finance,
  }) {
    if (buyer.squad.isEmpty) return null;
    if (buyer.transferBudget <= 0) return null;
    // Rosters grow only so far per window; a club that already overfilled
    // sits out until it moves somebody out.
    if (buyer.squad.length >= kMaxRivalSquad) return null;

    // Fee headroom for this deal: a slice of the budget, wider when the club
    // is owned a replacement for somebody the manager just took away. Not
    // banked across matchdays, so this mostly bounds per-matchday spree
    // size; the low act chance bounds the total for the window.
    final spendCap = buyer.transferBudget *
        (rng.nextDouble() * 0.18 + (priority ? 0.34 : 0.12));
    if (spendCap <= 0) return null;

    // Wage headroom: rivals respect a weekly ceiling like the user does.
    var bill = 0.0;
    for (final p in buyer.squad) {
      bill += p.weeklyWage;
    }
    bill += buyer.loanedOutWages;
    final wageHeadroom = buyer.wageBudget <= 0
        ? double.infinity
        : (buyer.wageBudget - bill) * kWageHeadroomFactor;
    if (wageHeadroom <= 0) return null;

    // The weakest position group drives the need.
    final buckets = _positionBuckets(buyer.squad);
    var weakest = buckets.keys.first;
    var weakestAvg = buckets[weakest]!;
    for (final entry in buckets.entries) {
      if (entry.value < weakestAvg) {
        weakest = entry.key;
        weakestAvg = entry.value;
      }
    }

    // Squad-average floor: a club does not sign somebody blatantly below
    // its own level just because he slots into a weak area.
    var squadOvrSum = 0;
    for (final p in buyer.squad) {
      squadOvrSum += p.ovr;
    }
    final squadAvg = squadOvrSum / buyer.squad.length;

    // Cheapest-fit evaluation asks the same `askingPrice` formula the user
    // has to beat, so prices are comparable across the market.
    final prices = <Player, int>{};
    for (final player in targets) {
      final seller = sellers[player.currentTeam];
      if (seller == null || seller.name == buyer.name) continue;
      // The need: at least comparable quality in the weakest area. Demanding
      // a strict upgrade starves the strongest clubs — in a league where the
      // best available is 78, a 79-average club would never act at all, and
      // realistic churn means giants still raid the leaders of mid-tier
      // squads.
      if (player.ovr < weakestAvg - kChurnSlack) continue;
      if (player.ovr < squadAvg - kSquadAvgFloor) continue;
      // Prestige plausibility: a priority replacement may stretch a little.
      if (service.requiredReputation(player) >
          buyer.reputation + (priority ? 10 : 5)) {
        continue;
      }
      final fee =
          service.askingPrice(player, seller, seasonYear: seasonYear, buyer: buyer);
      if (fee > spendCap) continue;
      final wage = finance.expectedWeeklyWage(player);
      if (wage > wageHeadroom) continue;
      prices[player] = fee;
    }
    if (prices.isEmpty) return null;

    // Among the fits, prefer quality but leave the exact pick to the seeded
    // roll so the market does not funnel every club to the same stars.
    final ranked = prices.keys.toList()
      ..sort((a, b) {
        final c = b.ovr.compareTo(a.ovr);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    final pick = ranked[rng.nextInt(min(kPickWindow, ranked.length))];
    final seller = sellers[pick.currentTeam]!;

    return RivalDeal(
      player: pick,
      seller: seller,
      buyer: buyer,
      fee: prices[pick]!,
      wage: finance.expectedWeeklyWage(pick).round(),
    );
  }

  /// Average OVR per broad position group; the buyer strengthens the lowest.
  Map<String, double> _positionBuckets(List<Player> squad) {
    final totals = <String, double>{};
    final counts = <String, int>{};
    for (final p in squad) {
      final bucket = _bucketFor(p.primaryPosition);
      totals[bucket] = (totals[bucket] ?? 0) + p.ovr;
      counts[bucket] = (counts[bucket] ?? 0) + 1;
    }
    return {
      for (final bucket in totals.keys) bucket: totals[bucket]! / counts[bucket]!,
    };
  }

  String _bucketFor(String position) {
    switch (position) {
      case 'GK':
        return 'GK';
      case 'CB':
      case 'LB':
      case 'RB':
      case 'LWB':
      case 'RWB':
        return 'DEF';
      case 'CDM':
      case 'CM':
      case 'CAM':
        return 'MID';
      default:
        return 'FWD';
    }
  }

  /// Minimum squad size a rival club needs before it acts.
  static const int kMinRivalSquad = 16;
  /// Roster growth cap: rivals sign into free slots only.
  static const int kMaxRivalSquad = 26;
  /// Most rival deals resolved in one matchday.
  static const int kMaxDealsPerMatchday = 3;
  /// Chance a wealthy, healthy rival club does business on a given matchday.
  static const double kBaseActChance = 0.10;
  /// Extra chance when the club replaces a player the manager took.
  static const double kPriorityActChance = 0.45;
  /// Fraction of the weekly wage ceiling a rival deal may use.
  static const double kWageHeadroomFactor = 0.9;
  /// A target may trail the weakest area's average by this little — churn at
  /// every level instead of strict ascension only.
  static const double kChurnSlack = 1.0;
  /// …but never this far below the club's overall level.
  static const double kSquadAvgFloor = 6.0;
  /// Candidates the seeded roll may pick from (best-of-N).
  static const int kPickWindow = 3;
}
