/// State of the national knockout cup attached to a season.
///
/// The cup's matches ARE the season's schedule: every cup round is spliced
/// into `SeasonState.rounds` at a fixed position (its [anchor]) and tagged
/// `competition: 'cup'`, so the existing match engine, dashboard and bye
/// handling run them without caring which competition a round belongs to.
/// This class carries only what the schedule alone cannot express:
///
/// * [anchors] — the absolute index of each cup round inside the merged
///   rounds list. Round k is played at `rounds[anchors[k]]`.
/// * [byes] — when a bracket level has an odd number of survivors, the
///   trailing team (in bracket order) skips that round. Stored so
///   progression can reconstruct every round's contenders from the played
///   fixtures alone, which is what makes a restored save replay the same
///   bracket.
///
/// [ties] holds the number of matches each round will hold, computed once
/// at the draw: the contender chain is deterministic (ceil-halving), so
/// stage names and progress reporting never have to peek at undrawn rounds.
///
/// Everything else — pairings, winners, the eventual cup holder — is derived
/// from the played cup fixtures by [CupService], so there is no duplicate
/// match state to drift.
class CupState {
  CupState({
    required this.name,
    required this.anchors,
    this.ties = const <int>[],
    Map<int, String>? byes,
  }) : byes = byes ?? <int, String>{};

  final String name;

  /// One absolute rounds-list position per cup round, strictly increasing.
  final List<int> anchors;

  /// How many matches each bracket round holds, index-aligned with
  /// [anchors]. Deterministic from the entrant count, so it is known the
  /// moment the draw happens.
  final List<int> ties;

  /// Cup round index -> the team id that sits that round out.
  final Map<int, String> byes;

  /// Number of cup rounds the bracket contains, filled or not.
  int get roundCount => anchors.length;

  Map<String, dynamic> toJson() => {
        'name': name,
        'anchors': anchors,
        'ties': ties,
        'byes': {for (final e in byes.entries) e.key.toString(): e.value},
      };

  factory CupState.fromJson(Map<dynamic, dynamic> json) {
    final rawAnchors = json['anchors'] is List ? json['anchors'] as List : const [];
    final rawTies = json['ties'] is List ? json['ties'] as List : const [];
    return CupState(
      name: json['name'] as String? ?? 'National Cup',
      anchors: [
        for (final a in rawAnchors) (a as num).toInt(),
      ],
      ties: [
        for (final t in rawTies) (t as num).toInt(),
      ],
      byes: {
        for (final entry in ((json['byes'] as Map?) ?? const {}).entries)
          int.parse(entry.key.toString()): entry.value.toString(),
      },
    );
  }
}
