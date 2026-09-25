// Tactic definitions

enum PlayingStyle { attacking, balanced, defensive, possession, counterAttack }
enum PressingIntensity { highPress, mediumPress, lowBlock, false9Press }
enum Tempo { fast, normal, slow }
enum Width { narrow, normal, wide }
enum DefensiveLine { high, medium, low }
enum PossessionFocus { shortPassing, longBalls }

class TacticSettings {
  final PlayingStyle playingStyle;
  final PressingIntensity pressing;
  final Tempo tempo;
  final Width width;
  final DefensiveLine defensiveLine;
  final bool offsideTrap;
  final bool counterPress;
  final PossessionFocus possessionFocus;
  final bool setPieceAggressive;
  final String targetPlayer;

  const TacticSettings({
    this.playingStyle = PlayingStyle.balanced,
    this.pressing = PressingIntensity.mediumPress,
    this.tempo = Tempo.normal,
    this.width = Width.normal,
    this.defensiveLine = DefensiveLine.medium,
    this.offsideTrap = false,
    this.counterPress = false,
    this.possessionFocus = PossessionFocus.shortPassing,
    this.setPieceAggressive = false,
    this.targetPlayer = '',
  });

  TacticSettings copyWith({
    PlayingStyle? playingStyle,
    PressingIntensity? pressing,
    Tempo? tempo,
    Width? width,
    DefensiveLine? defensiveLine,
    bool? offsideTrap,
    bool? counterPress,
    PossessionFocus? possessionFocus,
    bool? setPieceAggressive,
    String? targetPlayer,
  }) {
    return TacticSettings(
      playingStyle: playingStyle ?? this.playingStyle,
      pressing: pressing ?? this.pressing,
      tempo: tempo ?? this.tempo,
      width: width ?? this.width,
      defensiveLine: defensiveLine ?? this.defensiveLine,
      offsideTrap: offsideTrap ?? this.offsideTrap,
      counterPress: counterPress ?? this.counterPress,
      possessionFocus: possessionFocus ?? this.possessionFocus,
      setPieceAggressive: setPieceAggressive ?? this.setPieceAggressive,
      targetPlayer: targetPlayer ?? this.targetPlayer,
    );
  }

  Map<String, dynamic> toJson() => {
    'playingStyle': playingStyle.name,
    'pressing': pressing.name,
    'tempo': tempo.name,
    'width': width.name,
    'defensiveLine': defensiveLine.name,
    'offsideTrap': offsideTrap,
    'counterPress': counterPress,
    'possessionFocus': possessionFocus.name,
    'setPieceAggressive': setPieceAggressive,
    'targetPlayer': targetPlayer,
  };

  factory TacticSettings.fromJson(Map<String, dynamic> json) => TacticSettings(
    playingStyle: PlayingStyle.values.firstWhere((e) => e.name == json['playingStyle']),
    pressing: PressingIntensity.values.firstWhere((e) => e.name == json['pressing']),
    tempo: Tempo.values.firstWhere((e) => e.name == json['tempo']),
    width: Width.values.firstWhere((e) => e.name == json['width']),
    defensiveLine: DefensiveLine.values.firstWhere((e) => e.name == json['defensiveLine']),
    offsideTrap: json['offsideTrap'] ?? false,
    counterPress: json['counterPress'] ?? false,
    possessionFocus: PossessionFocus.values.firstWhere((e) => e.name == json['possessionFocus']),
    setPieceAggressive: json['setPieceAggressive'] ?? false,
    targetPlayer: json['targetPlayer'] ?? '',
  );

  String get displayScore {
    final style = playingStyle.name.replaceAll(RegExp(r'([A-Z])'), r' $1').trim();
    final press = pressing.name.replaceAll(RegExp(r'([A-Z])'), r' $1').trim();
    return '$style | $press';
  }
}