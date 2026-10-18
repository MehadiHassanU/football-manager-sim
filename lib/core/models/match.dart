class MatchEvent {
  final String type;
  final String team;
  final String player;
  final String description;
  final int minute;
  final int? homeScore;
  final int? awayScore;
  final Map<String, dynamic>? extraData;

  MatchEvent({
    required this.type,
    required this.team,
    required this.player,
    required this.description,
    required this.minute,
    this.homeScore,
    this.awayScore,
    this.extraData,
  });

  bool get isGoal => type == 'goal';
  bool get isCard => type == 'card';
  bool get isInjury => type == 'injury';
  bool get isSubstitution => type == 'sub';
  bool get isChance => type == 'chance';
  bool get isCommentary => type == 'commentary';
  bool get isFoul => type == 'foul';
  bool get isCorner => type == 'corner';
  bool get isOffside => type == 'offside';
  bool get isSave => type == 'save';
  bool get isKickOff => type == 'kickoff';
  bool get isHalfTime => type == 'halfTime';
}

class PlayerRating {
  final String playerName;

  /// The player's database id. Player identity is an id, never a name: two
  /// squad-mates can share a name, and every stat folded back into the squad
  /// keys on this. Null only on hand-built ratings in tests.
  final int? playerId;
  final String position;

  /// One decimal in the 1.0-10.0 band real match ratings use (7.4, not 7):
  /// integer ratings flattened every performance into ten buckets.
  final double rating;
  final int goals;
  final int assists;
  final int minutes;
  final bool started;

  PlayerRating({
    required this.playerName,
    this.playerId,
    required this.position,
    required this.rating,
    required this.goals,
    required this.assists,
    required this.minutes,
    required this.started,
  });
}

class MatchResult {
  final String homeTeam;
  final String awayTeam;
  final int homeGoals;
  final int awayGoals;
  final List<MatchEvent> events;

  /// Who played for each side and how they did. Kept apart so the career can
  /// slice the manager's own side out of the report without guessing where
  /// one list ends and the next begins (substitutes make the sides uneven).
  final List<PlayerRating> homeRatings;
  final List<PlayerRating> awayRatings;

  final List<double> homeMomentum;
  final List<double> awayMomentum;
  final String fullTimeCommentary;

  MatchResult({
    required this.homeTeam,
    required this.awayTeam,
    required this.homeGoals,
    required this.awayGoals,
    required this.events,
    this.homeRatings = const [],
    this.awayRatings = const [],
    required this.homeMomentum,
    required this.awayMomentum,
    required this.fullTimeCommentary,
  });

  /// Every rating, home side first, for screens that show one list.
  List<PlayerRating> get playerRatings => [...homeRatings, ...awayRatings];

  bool get homeWon => homeGoals > awayGoals;
  bool get awayWon => awayGoals > homeGoals;
  bool get isDraw => homeGoals == awayGoals;

  String get resultText => '$homeGoals - $awayGoals';
}

class Contract {
  final double weeklyWage;
  final int contractYears;
  final int? releaseClause;
  final DateTime startDate;
  final DateTime expiryDate;
  final double signOnBonus;

  Contract({
    required this.weeklyWage,
    required this.contractYears,
    this.releaseClause,
    required this.startDate,
    required this.expiryDate,
    this.signOnBonus = 0,
  });

  bool get isExpiring {
    final diff = expiryDate.difference(DateTime.now()).inDays;
    return diff < 180; // 6 months
  }
}
