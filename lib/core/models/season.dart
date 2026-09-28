class SeasonState {
  final String leagueId;
  final int currentMatchday;
  final int totalMatchdays;
  final int currentYear;
  final bool isPreSeason;
  final bool isWinterBreak;
  final Map<String, int> standings; // teamId -> points
  final List<String> matchdayFixtures; // team pairs

  SeasonState({
    required this.leagueId,
    this.currentMatchday = 0,
    this.totalMatchdays = 38,
    this.currentYear = 2024,
    this.isPreSeason = true,
    this.isWinterBreak = false,
    Map<String, int>? standings,
    List<String>? matchdayFixtures,
  })  : standings = standings ?? {},
        matchdayFixtures = matchdayFixtures ?? [];

  bool get isPostSeason => currentMatchday >= totalMatchdays;

  /// A season is live once matchdays have begun and before they finish.
  ///
  /// The calendar is the source of truth: [isPreSeason] is a persisted phase
  /// flag that callers mutate, so it can contradict [currentMatchday]. Deriving
  /// activity from the matchday counter keeps the three states consistent.
  bool get isActive => currentMatchday > 0 && !isPostSeason && !isWinterBreak;

  int get matchdayNumber => currentMatchday + 1;
}

class TransferOffer {
  final String id;
  final String playerId;
  final String playerName;
  final String buyingTeamId;
  final String sellingTeamId;
  int proposedFee;
  int sellerCounterFee;
  double proposedWage;
  double sellerWageDemand;
  int proposedContractYears;
  int? releaseClause;
  double signOnBonus;
  String status; // 'pending', 'accepted', 'rejected', 'negotiating'
  int negotiationRound;

  TransferOffer({
    required this.id,
    required this.playerId,
    required this.playerName,
    required this.buyingTeamId,
    required this.sellingTeamId,
    required this.proposedFee,
    this.sellerCounterFee = 0,
    required this.proposedWage,
    this.sellerWageDemand = 0,
    required this.proposedContractYears,
    this.releaseClause,
    this.signOnBonus = 0,
    this.status = 'pending',
    this.negotiationRound = 0,
  });
}

class ScoutingResult {
  final String playerId;
  final String playerName;
  final int age;
  final String position;
  final int? ovr;
  final Map<String, int>? fullStats;
  final int? potential;
  final String? personality;
  final List<String>? traits;
  final ScoutLevel level;

  ScoutingResult({
    required this.playerId,
    required this.playerName,
    required this.age,
    required this.position,
    this.ovr,
    this.fullStats,
    this.potential,
    this.personality,
    this.traits,
    required this.level,
  });
}

enum ScoutLevel { detailed, topLevel }