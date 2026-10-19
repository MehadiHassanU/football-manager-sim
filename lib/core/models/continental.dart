import 'fixture.dart';

/// A continental competition a season can carry: a league phase followed by
/// two-legged knockout rounds and a single-leg final.
///
/// The structure is deliberately split in two. [ContinentalState] is the small
/// persisted part — the field, the calendar anchors and which rounds have
/// already paid out — while every table and bracket is derived from the
/// fixtures in `SeasonState.rounds`, exactly like the domestic cups. That way
/// a save can never disagree with the schedule it was built from.
class ContinentalState {
  ContinentalState({
    required this.id,
    required this.name,
    required this.region,
    required this.clubIds,
    required this.leagueRounds,
    required this.leagueAnchors,
    required this.knockoutAnchors,
    List<int>? rewardedRounds,
  }) : rewardedRounds = rewardedRounds ?? <int>[];

  /// Stable id ('ucl', 'libertadores'…), also written to `Fixture.competition`.
  final String id;

  /// The real competition name ('UEFA Champions League'…).
  final String name;

  /// 'europe', 'south_america', 'north_america' or 'asia'.
  final String region;

  /// The field in seed order (reputation first). The seeded draw and the
  /// knockout home/away order both read it.
  final List<String> clubIds;

  /// League-phase games per club (8 for the Champions League, 6 for the
  /// Conference League and the South American competitions).
  final int leagueRounds;

  /// Absolute rounds-list positions of the league phase, one per matchday.
  final List<int> leagueAnchors;

  /// Nine knockout slots: two legs for each of the play-off, round of 16,
  /// quarter-final and semi-final, then the final. Empty until drawn.
  final List<int> knockoutAnchors;

  /// Rounds that have already paid the club's prize money, so replaying a
  /// matchday after a crash cannot pay twice.
  final List<int> rewardedRounds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'region': region,
        'clubIds': clubIds,
        'leagueRounds': leagueRounds,
        'leagueAnchors': leagueAnchors,
        'knockoutAnchors': knockoutAnchors,
        'rewardedRounds': rewardedRounds,
      };

  factory ContinentalState.fromJson(Map<dynamic, dynamic> json) =>
      ContinentalState(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        region: '${json['region'] ?? ''}',
        clubIds: [
          for (final id in (json['clubIds'] as List? ?? const [])) '$id',
        ],
        leagueRounds: (json['leagueRounds'] as num?)?.toInt() ?? 8,
        leagueAnchors: [
          for (final a in (json['leagueAnchors'] as List? ?? const []))
            (a as num).toInt(),
        ],
        knockoutAnchors: [
          for (final a in (json['knockoutAnchors'] as List? ?? const []))
            (a as num).toInt(),
        ],
        rewardedRounds: [
          for (final a in (json['rewardedRounds'] as List? ?? const []))
            (a as num).toInt(),
        ],
      );
}

/// A competition the season builder asks the calendar to schedule.
///
/// The service hands one of these to [CupService.attachCompetitions]; the
/// scheduler fills in the anchor lists in the same pass that splices the
/// domestic cups, so no anchor is ever invalidated by a later insertion. The
/// league-phase fixtures travel with the request because they are fully known
/// at the draw: unlike a knockout bracket there are no results to wait for.
class ContinentalRequest {
  ContinentalRequest({
    required this.id,
    required this.name,
    required this.region,
    required this.clubIds,
    required this.leagueRounds,
    required this.leagueSchedule,
  });

  final String id;
  final String name;
  final String region;
  final List<String> clubIds;
  final int leagueRounds;

  /// One list of league-phase fixtures per matchday.
  final List<List<Fixture>> leagueSchedule;

  /// Filled by the scheduler.
  final List<int> leagueAnchors = <int>[];
  final List<int> knockoutAnchors = <int>[];

  /// The persisted competition once the anchors are known.
  ContinentalState? toState() =>
      leagueAnchors.length == leagueRounds && knockoutAnchors.length == 9
          ? ContinentalState(
              id: id,
              name: name,
              region: region,
              clubIds: clubIds,
              leagueRounds: leagueRounds,
              leagueAnchors: [...leagueAnchors],
              knockoutAnchors: [...knockoutAnchors],
            )
          : null;
}
