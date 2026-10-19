/// The kind of knockout competition a [CupState] describes.
enum CupKind {
  /// The country's primary cup (FA Cup, DFB-Pokal, Copa del Rey…).
  national,

  /// A second, usually smaller cup (EFL Cup, Taça da Liga…).
  leagueCup,

  /// The one-match curtain-raiser between last season's league and cup winners.
  superCup;

  static CupKind parse(Object? value) {
    final name = value?.toString();
    return CupKind.values.firstWhere(
      (kind) => kind.name == name,
      orElse: () => CupKind.national,
    );
  }
}

/// State of a knockout competition attached to a season.
///
/// A competition's matches ARE the season's schedule: every round is spliced
/// into `SeasonState.rounds` at a fixed position (its [anchor]) and tagged
/// with the competition's [competition] id, so the existing match engine,
/// dashboard and bye handling run it without caring which cup a round belongs
/// to. This class carries only what the schedule alone cannot express:
///
/// * [anchors] — the absolute index of each round inside the merged rounds
///   list. Round k is played at `rounds[anchors[k]]`.
/// * [byes] — when a bracket level has an odd number of survivors, the
///   trailing team (in bracket order) skips that round. Stored so progression
///   can reconstruct every round's contenders from the played fixtures alone,
///   which is what makes a restored save replay the same bracket.
/// * [entrants] — the clubs that join the bracket at each round. Large cups
///   stagger entry (the top flight joins the round of 64, not the preliminary
///   round), so progression must know who arrives when. Persisted because it
///   is part of the draw, not something to re-derive from a different RNG.
/// * [roundNames] — the real stage names ('Round of 64', 'Semi-finals'…) so an
///   undrawn round can still be labelled correctly.
///
/// [ties] holds the number of matches each round will hold, computed once at
/// the draw: the contender chain is deterministic (ceil-halving with staggered
/// entry), so stage names and progress reporting never have to peek at
/// undrawn rounds.
class CupState {
  CupState({
    required this.name,
    required this.anchors,
    this.id = 'national_cup',
    this.kind = CupKind.national,
    this.competition = 'cup',
    this.roundNames = const <String>[],
    this.entrants = const <int, List<String>>{},
    this.ties = const <int>[],
    Map<int, String>? byes,
  }) : byes = byes ?? <int, String>{};

  /// Stable competition id ('fa_cup', 'efl_cup'…). Also the fixture tag on
  /// the pitches, so a round can always name the competition it belongs to.
  final String id;

  final String name;
  final CupKind kind;

  /// The value written to `Fixture.competition` for this cup's ties.
  final String competition;

  /// One absolute rounds-list position per round, strictly increasing.
  final List<int> anchors;

  /// The real name of each round, index-aligned with [anchors]. Empty on
  /// saves written before multiple competitions, where the name is derived
  /// from the bracket shape instead.
  final List<String> roundNames;

  /// Cup round index -> the clubs that join the draw at that round.
  final Map<int, List<String>> entrants;

  /// How many matches each bracket round holds, index-aligned with
  /// [anchors]. Deterministic from the entrant counts, so it is known the
  /// moment the draw happens.
  final List<int> ties;

  /// Cup round index -> the team id that sits that round out.
  final Map<int, String> byes;

  /// Number of cup rounds the bracket contains, filled or not.
  int get roundCount => anchors.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'competition': competition,
        'anchors': anchors,
        'roundNames': roundNames,
        'entrants': {
          for (final entry in entrants.entries) '${entry.key}': entry.value,
        },
        'ties': ties,
        'byes': {for (final e in byes.entries) e.key.toString(): e.value},
      };

  factory CupState.fromJson(Map<dynamic, dynamic> json) {
    final rawAnchors = json['anchors'] is List ? json['anchors'] as List : const [];
    final rawTies = json['ties'] is List ? json['ties'] as List : const [];
    final rawNames =
        json['roundNames'] is List ? json['roundNames'] as List : const [];
    final rawEntrants = json['entrants'];
    final entrants = <int, List<String>>{};
    if (rawEntrants is Map) {
      for (final entry in rawEntrants.entries) {
        final round = int.tryParse(entry.key.toString());
        if (round == null || entry.value is! List) continue;
        entrants[round] = [
          for (final id in entry.value as List) id.toString(),
        ];
      }
    }
    return CupState(
      id: json['id'] as String? ?? 'national_cup',
      name: json['name'] as String? ?? 'National Cup',
      kind: CupKind.parse(json['kind']),
      competition: json['competition'] as String? ?? 'cup',
      anchors: [
        for (final a in rawAnchors) (a as num).toInt(),
      ],
      roundNames: [for (final name in rawNames) name.toString()],
      entrants: entrants,
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
