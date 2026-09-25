
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
}

class PlayerRating {
  final String playerName;
  final String position;
  final int rating;
  final int goals;
  final int assists;
  final int minutes;
  final bool started;

  PlayerRating({
    required this.playerName,
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
  final List<PlayerRating> playerRatings;
  final List<double> homeMomentum;
  final List<double> awayMomentum;
  final String fullTimeCommentary;

  MatchResult({
    required this.homeTeam,
    required this.awayTeam,
    required this.homeGoals,
    required this.awayGoals,
    required this.events,
    required this.playerRatings,
    required this.homeMomentum,
    required this.awayMomentum,
    required this.fullTimeCommentary,
  });

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