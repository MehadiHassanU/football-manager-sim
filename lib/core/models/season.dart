import 'cup.dart';
import 'fixture.dart';

/// One club's season record. Points are derived rather than stored twice, so
/// the table can never drift from the results behind it.
class LeagueRecord {
  LeagueRecord({
    this.played = 0,
    this.won = 0,
    this.drawn = 0,
    this.lost = 0,
    this.goalsFor = 0,
    this.goalsAgainst = 0,
  });

  int played;
  int won;
  int drawn;
  int lost;
  int goalsFor;
  int goalsAgainst;

  int get points => won * 3 + drawn;

  int get goalDifference => goalsFor - goalsAgainst;

  /// Folds one finished match into the record.
  void record(int scored, int conceded) {
    played += 1;
    goalsFor += scored;
    goalsAgainst += conceded;
    if (scored > conceded) {
      won += 1;
    } else if (scored == conceded) {
      drawn += 1;
    } else {
      lost += 1;
    }
  }

  Map<String, dynamic> toJson() => {
        'played': played,
        'won': won,
        'drawn': drawn,
        'lost': lost,
        'goalsFor': goalsFor,
        'goalsAgainst': goalsAgainst,
      };

  factory LeagueRecord.fromJson(Map<dynamic, dynamic> json) => LeagueRecord(
        played: (json['played'] as num?)?.toInt() ?? 0,
        won: (json['won'] as num?)?.toInt() ?? 0,
        drawn: (json['drawn'] as num?)?.toInt() ?? 0,
        lost: (json['lost'] as num?)?.toInt() ?? 0,
        goalsFor: (json['goalsFor'] as num?)?.toInt() ?? 0,
        goalsAgainst: (json['goalsAgainst'] as num?)?.toInt() ?? 0,
      );
}

/// One row of the league table.
class LeagueStanding {
  const LeagueStanding({
    required this.teamId,
    required this.record,
    required this.position,
  });

  final String teamId;
  final LeagueRecord record;
  final int position;
}

/// One player's goals and assists for the season, for the league's top
/// scorer list.
///
/// It lives on the season rather than on the players because rival squads are
/// rebuilt from the CSV on every load: their tallies have nowhere else to
/// live. Goals recorded here are league goals, matching the table beside it;
/// the full all-competitions total is folded onto the user's own players.
class ScorerRecord {
  ScorerRecord({
    required this.playerId,
    required this.playerName,
    required this.clubId,
    required this.clubName,
    this.goals = 0,
    this.assists = 0,
  });

  final int playerId;
  String playerName;
  String clubId;
  String clubName;
  int goals;
  int assists;

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'playerName': playerName,
        'clubId': clubId,
        'clubName': clubName,
        'goals': goals,
        'assists': assists,
      };

  factory ScorerRecord.fromJson(Map<dynamic, dynamic> json) => ScorerRecord(
        playerId: (json['playerId'] as num?)?.toInt() ?? 0,
        playerName: '${json['playerName'] ?? ''}',
        clubId: '${json['clubId'] ?? ''}',
        clubName: '${json['clubName'] ?? ''}',
        goals: (json['goals'] as num?)?.toInt() ?? 0,
        assists: (json['assists'] as num?)?.toInt() ?? 0,
      );
}

class SeasonState {
  SeasonState({
    required this.leagueId,
    this.currentMatchday = 0,
    int? totalMatchdays,
    this.currentYear = 2024,
    this.isPreSeason = true,
    this.isWinterBreak = false,
    Map<String, LeagueRecord>? records,
    List<List<Fixture>>? rounds,
    List<String>? legacyFixturePairs,
    Map<int, ScorerRecord>? scorers,
    this.cup,
  })  : _totalMatchdaysOverride = totalMatchdays,
        _legacyFixturePairs = legacyFixturePairs ?? const <String>[],
        rounds = rounds ?? const <List<Fixture>>[],
        records = records ?? <String, LeagueRecord>{},
        scorers = scorers ?? <int, ScorerRecord>{};

  final String leagueId;

  /// Index of the next round to be played. 0 means the season has not started.
  final int currentMatchday;
  final int currentYear;
  final bool isPreSeason;
  final bool isWinterBreak;

  /// The schedule: one list of fixtures per matchday. This is the single source
  /// of truth for who plays whom.
  ///
  /// Cup rounds live in the same list: a knockout round is spliced between
  /// league matchdays at an absolute position recorded in [cup], and its
  /// fixtures carry `competition: 'cup'`. Position-based reading keeps the
  /// merged counter coherent.
  final List<List<Fixture>> rounds;

  /// The knockout cup attached to this season, or null for seasons played
  /// before cups existed (older saves get one when the next season starts).
  /// The bracket itself is expressed through the schedule; this object holds
  /// only the round anchors and byes.
  final CupState? cup;

  /// Every club's record, keyed by team id.
  final Map<String, LeagueRecord> records;

  /// League goals and assists, keyed by player id. Rebuilt from empty at
  /// every rollover because it belongs to the season, not the career.
  final Map<int, ScorerRecord> scorers;

  /// Schema v1 stored a flat, shuffled list of "home|away" strings with no
  /// round structure, which made it impossible to tell who the user was
  /// actually playing. It is read once so a save can be migrated and is then
  /// replaced by [rounds]; nothing schedules from it.
  final List<String> _legacyFixturePairs;

  /// Consulted only when [rounds] is empty, which is the case for a
  /// default-constructed or freshly migrated season.
  final int? _totalMatchdaysOverride;

  /// Matchdays in the season, derived from the schedule whenever one exists so
  /// the counter can never disagree with the fixtures.
  int get totalMatchdays =>
      rounds.isNotEmpty ? rounds.length : (_totalMatchdaysOverride ?? 38);

  /// Points per club, derived from the records. There is deliberately no
  /// constructor parameter for a bare points map: seeding one would produce
  /// clubs whose points silently read back as zero.
  Map<String, int> get standings => <String, int>{
        for (final e in records.entries) e.key: e.value.points,
      };

  /// The legacy flat fixture list, exposed only so the migration can detect a
  /// schema v1 save.
  List<String> get legacyFixturePairs => _legacyFixturePairs;

  bool get isPostSeason => currentMatchday >= totalMatchdays;

  /// A season is live once matchdays have begun and before they finish.
  ///
  /// The calendar is the source of truth: [isPreSeason] is a persisted phase
  /// flag that callers mutate, so it can contradict [currentMatchday]. Deriving
  /// activity from the matchday counter keeps the three states consistent.
  bool get isActive => currentMatchday > 0 && !isPostSeason && !isWinterBreak;

  int get matchdayNumber => currentMatchday + 1;

  /// The round at which the league pauses for winter. Rounds keep counting
  /// across the break, so this is the midpoint of the schedule.
  int get winterBreakRound => totalMatchdays ~/ 2;

  /// Whether the season is sitting at the winter break, which is a pause
  /// rather than a completed matchday: no fixture is played until the manager
  /// resumes.
  bool get isWinterBreakRound =>
      rounds.isNotEmpty && currentMatchday == winterBreakRound;

  /// The fixtures of [round], or an empty list past the end of the season.
  List<Fixture> fixturesForRound(int round) {
    if (round < 0 || round >= rounds.length) return const <Fixture>[];
    return rounds[round];
  }

  /// The single fixture in [round] that involves [teamId].
  ///
  /// Null when the club is not in that round, which happens on a bye when the
  /// league has an odd number of clubs. This is the only supported way to
  /// resolve an opponent: the dashboard and the match engine both call it, so
  /// they cannot disagree about who is being played.
  Fixture? userFixtureForRound(int round, String teamId) {
    for (final fixture in fixturesForRound(round)) {
      if (fixture.involves(teamId)) return fixture;
    }
    return null;
  }

  /// The club's fixture for the round currently being played, if any.
  Fixture? currentFixtureFor(String teamId) =>
      userFixtureForRound(currentMatchday, teamId);

  /// Whether the club sits out the round currently being played.
  bool isByeRound(String teamId) =>
      rounds.isNotEmpty && currentFixtureFor(teamId) == null;

  /// The league table, best first: points, then goal difference, then goals
  /// scored, then club id so the order is stable across rebuilds.
  ///
  /// Ranking the club rather than a points value is what stops tied clubs from
  /// aliasing to the same position.
  List<LeagueStanding> table() {
    final sorted = records.keys
        .map((id) =>
            LeagueStanding(teamId: id, record: records[id]!, position: 0))
        .toList()
      ..sort((a, b) {
        final byPoints = b.record.points.compareTo(a.record.points);
        if (byPoints != 0) return byPoints;
        final byGd = b.record.goalDifference.compareTo(a.record.goalDifference);
        if (byGd != 0) return byGd;
        final byGoals = b.record.goalsFor.compareTo(a.record.goalsFor);
        if (byGoals != 0) return byGoals;
        return a.teamId.compareTo(b.teamId);
      });
    return [
      for (var i = 0; i < sorted.length; i++)
        LeagueStanding(
          teamId: sorted[i].teamId,
          record: sorted[i].record,
          position: i + 1,
        ),
    ];
  }

  /// The league position of [teamId] (1 = top), or 0 when it is unknown.
  int positionOf(String teamId) {
    for (final row in table()) {
      if (row.teamId == teamId) return row.position;
    }
    return 0;
  }

  /// Credits a player's league tallies for this season.
  void recordContribution({
    required int playerId,
    required String playerName,
    required String clubId,
    required String clubName,
    int goals = 0,
    int assists = 0,
  }) {
    if (goals == 0 && assists == 0) return;
    final entry = scorers.putIfAbsent(
      playerId,
      () => ScorerRecord(
        playerId: playerId,
        playerName: playerName,
        clubId: clubId,
        clubName: clubName,
      ),
    );
    entry
      ..playerName = playerName
      ..clubId = clubId
      ..clubName = clubName
      ..goals += goals
      ..assists += assists;
  }

  /// The league's leading scorers: goals, then assists, then name so tied
  /// players keep a stable order.
  List<ScorerRecord> topScorers({int limit = 20}) {
    final sorted = scorers.values.toList()
      ..sort((a, b) {
        final byGoals = b.goals.compareTo(a.goals);
        if (byGoals != 0) return byGoals;
        final byAssists = b.assists.compareTo(a.assists);
        if (byAssists != 0) return byAssists;
        return a.playerName.compareTo(b.playerName);
      });
    return sorted.take(limit).toList();
  }
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
