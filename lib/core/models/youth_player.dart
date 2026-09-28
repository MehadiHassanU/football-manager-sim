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
}