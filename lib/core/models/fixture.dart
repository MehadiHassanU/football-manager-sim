import 'dart:math';

/// One scheduled league match.
///
/// [round] is the index into `SeasonState.rounds` and is 0-based, so the
/// matchday a fixture belongs to is `round + 1`. [leg] is 0 for the first
/// meeting of a pair and 1 for the return fixture, which reverses home and
/// away. The score is mutable because a fixture is filled in when it is played
/// and then becomes part of the persisted season rather than a static
/// schedule.
class Fixture {
  Fixture({
    required this.homeTeamId,
    required this.awayTeamId,
    required this.round,
    required this.leg,
    this.homeGoals = 0,
    this.awayGoals = 0,
    this.played = false,
    this.competition = 'league',
  });

  final String homeTeamId;
  final String awayTeamId;
  final int round;
  final int leg;
  int homeGoals;
  int awayGoals;
  bool played;

  /// Which competition the fixture belongs to: `'league'` counts towards the
  /// table, `'cup'` comes out of the knockout schedule and never records
  /// points. Older saves read back as `'league'`, which is exactly right.
  final String competition;

  bool involves(String teamId) => homeTeamId == teamId || awayTeamId == teamId;

  /// The other side of the fixture from [teamId], or null when [teamId] is not
  /// part of it. A league with an odd number of clubs produces rounds where
  /// the user's club simply does not appear, which is a bye rather than an
  /// error.
  String? opponentOf(String teamId) {
    if (homeTeamId == teamId) return awayTeamId;
    if (awayTeamId == teamId) return homeTeamId;
    return null;
  }

  bool isHomeFor(String teamId) => homeTeamId == teamId;

  /// Points [teamId] takes from this fixture (0, 1 or 3). An unplayed fixture
  /// is worth nothing to both sides.
  int pointsFor(String teamId) {
    if (!played) return 0;
    final home = isHomeFor(teamId);
    final mine = home ? homeGoals : awayGoals;
    final theirs = home ? awayGoals : homeGoals;
    if (mine > theirs) return 3;
    if (mine == theirs) return 1;
    return 0;
  }

  /// Fills in the final score and marks the fixture played.
  void record(int home, int away) {
    homeGoals = home;
    awayGoals = away;
    played = true;
  }

  Map<String, dynamic> toJson() => {
        'homeTeamId': homeTeamId,
        'awayTeamId': awayTeamId,
        'round': round,
        'leg': leg,
        'homeGoals': homeGoals,
        'awayGoals': awayGoals,
        'played': played,
        'competition': competition,
      };

  /// Reads a fixture back from Hive, which hands maps back as
  /// `Map<dynamic, dynamic>` rather than `Map<String, dynamic>`.
  factory Fixture.fromJson(Map<dynamic, dynamic> json) => Fixture(
        homeTeamId: json['homeTeamId'] as String,
        awayTeamId: json['awayTeamId'] as String,
        round: (json['round'] as num).toInt(),
        leg: (json['leg'] as num).toInt(),
        homeGoals: (json['homeGoals'] as num?)?.toInt() ?? 0,
        awayGoals: (json['awayGoals'] as num?)?.toInt() ?? 0,
        played: json['played'] as bool? ?? false,
        competition: json['competition'] as String? ?? 'league',
      );
}

/// Builds a double round-robin schedule: every club plays every other club once
/// at home and once away.
///
/// Returns one list of [Fixture]s per matchday, so a 20-club league yields
/// `2 * (20 - 1)` = 38 rounds and every club plays 38 matches. Using the
/// circle method guarantees that no club meets the same opponent twice in a
/// leg, that every club plays the same number of matches, and that home and
/// away are balanced.
///
/// An odd number of clubs gets a bye: a placeholder slot is rotated alongside
/// the real clubs and whichever pair contains it is skipped, so the odd club
/// out sits out exactly one round per leg.
List<List<Fixture>> buildRounds(List<String> teamIds, {Random? rng}) {
  if (teamIds.length < 2) return [];

  // Shuffling the input stops every new career from opening with the same
  // opponent; a deterministic seed keeps tests reproducible.
  final ids = [...teamIds];
  if (rng != null) ids.shuffle(rng);

  // The bye slot is null rather than a sentinel string so it can never
  // collide with a real club id.
  final hasBye = ids.length.isOdd;
  final slots = hasBye ? ids.length + 1 : ids.length;
  final ring = <String?>[...ids, if (hasBye) null];

  final firstLeg = <List<Fixture>>[];
  for (var r = 0; r < slots - 1; r++) {
    final fixtures = <Fixture>[];
    for (var i = 0; i < slots ~/ 2; i++) {
      final a = ring[i];
      final b = ring[slots - 1 - i];
      if (a == null || b == null) continue; // one side is the bye
      // Alternate which side of the pair is nominally at home so a club is not
      // handed every home fixture of the first leg.
      final flip = (i + r).isOdd;
      fixtures.add(Fixture(
        homeTeamId: flip ? b : a,
        awayTeamId: flip ? a : b,
        round: r,
        leg: 0,
      ));
    }
    firstLeg.add(fixtures);
    // Rotate everything except the fixed pivot at index 0.
    final held = ring.removeAt(1);
    ring.add(held);
  }

  // The return fixtures mirror the first leg with home and away reversed, so
  // playing round r of leg 0 and round r of leg 1 visits every opponent twice.
  final rounds = <List<Fixture>>[...firstLeg];
  for (var r = 0; r < firstLeg.length; r++) {
    rounds.add([
      for (final f in firstLeg[r])
        Fixture(
          homeTeamId: f.awayTeamId,
          awayTeamId: f.homeTeamId,
          round: firstLeg.length + r,
          leg: 1,
        ),
    ]);
  }
  return rounds;
}
