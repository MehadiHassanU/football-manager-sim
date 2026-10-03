import 'dart:math';

class YouthPlayer {
  String name;
  int age;
  int potential;
  int currentStats;
  String position;
  String nationality;
  bool isPromoted;
  Map<String, dynamic> hiddenAttributes;

  YouthPlayer({
    required this.name,
    required this.age,
    required this.potential,
    required this.currentStats,
    required this.position,
    required this.nationality,
    this.isPromoted = false,
    Map<String, dynamic>? hiddenAttributes,
    Random? random,
  }) : hiddenAttributes = hiddenAttributes ??
            _rollHiddenAttributes(random ?? Random());

  /// See `Player._rollHiddenAttributes` -- seeded injection keeps youth intake
  /// reproducible so academy generation can be asserted in tests.
  static Map<String, dynamic> _rollHiddenAttributes(Random random) => {
        'personality':
            const ['Stable', 'Driven', 'Charismatic', 'Temperamental'][random.nextInt(4)],
        'leadership': random.nextInt(100),
      };

  /// Three key attributes shown on the prospect card.
  List<String> get keyAttributeNames {
    switch (position) {
      case 'GK':
        return const ['Reflexes', 'Positioning', 'Handling'];
      case 'ST':
        return const ['Finishing', 'Pace', 'Positioning'];
      case 'CB':
        return const ['Tackling', 'Heading', 'Positioning'];
      default:
        return const ['Passing', 'Dribbling', 'Vision'];
    }
  }

  /// Values for [keyAttributeNames]. Rolled once at intake and stored in
  /// hiddenAttributes so they stay stable; falls back to current ability for
  /// prospects created before attributes were persisted.
  List<int> keyAttributeValues() {
    final names = keyAttributeNames;
    final stored = hiddenAttributes['keyAttributes'];
    if (stored is Map) {
      final map = Map<String, dynamic>.from(stored);
      return [for (final n in names) (map[n] as num?)?.toInt() ?? currentStats];
    }
    return [for (final _ in names) currentStats];
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'age': age,
        'potential': potential,
        'currentStats': currentStats,
        'position': position,
        'nationality': nationality,
        'isPromoted': isPromoted,
        'hiddenAttributes': hiddenAttributes,
      };

  factory YouthPlayer.fromJson(Map<String, dynamic> json) => YouthPlayer(
        name: json['name'] as String,
        age: json['age'] as int,
        potential: json['potential'] as int,
        currentStats: json['currentStats'] as int,
        position: json['position'] as String,
        nationality: json['nationality'] as String,
        isPromoted: json['isPromoted'] as bool? ?? false,
        hiddenAttributes: json['hiddenAttributes'] == null
            ? null
            : Map<String, dynamic>.from(json['hiddenAttributes'] as Map),
      );

  /// Deterministic scout report derived from the prospect's own numbers
  /// (stable across sessions; no randomness).
  String scoutReport() {
    final gap = potential - currentStats;
    final pos = position;
    final strength = keyAttributeNames.first;
    final strengthValue = keyAttributeValues().first;

    final opener = currentStats >= 65
        ? 'A polished $pos already capable of first-team football.'
        : gap >= 15
            ? 'A raw but exciting $pos with room to develop.'
            : 'A steady $pos with dependable basics.';
    final body = '$strength is the standout trait ($strengthValue).';
    final closer = switch (gap) {
      >= 20 => 'Elite ceiling - handle with patience and regular minutes.',
      >= 12 => 'Projects as a future first-team squad member.',
      >= 6 => 'Should develop into a reliable squad rotation option.',
      _ => 'Limited upside; a squad-depth signing at best.',
    };
    return '$opener $body $closer';
  }
}