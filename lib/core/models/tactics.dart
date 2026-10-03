import 'package:meta/meta.dart';

import '../constants/tactic_definitions.dart';
import 'player.dart';

class Tactic {
  final Formation formation;
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

  const Tactic({
    this.formation = Formation.fourFourTwo,
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

  Tactic copyWith({
    Formation? formation,
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
    return Tactic(
      formation: formation ?? this.formation,
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

  String get displayName {
    final s = playingStyle.name.replaceAll(RegExp(r'([A-Z])'), r' $1').trim();
    final p = pressing.name.replaceAll(RegExp(r'([A-Z])'), r' $1').trim();
    return '$s | $p';
  }

  /// JSON round-trip used by the save blob for named saved tactics.
  Map<String, dynamic> toJson() => {
        'formation': formation.name,
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

  factory Tactic.fromJson(Map<String, dynamic> json) => Tactic(
        formation: _enumByName(
            Formation.values, json['formation'] as String?, Formation.fourFourTwo),
        playingStyle: _enumByName(
            PlayingStyle.values, json['playingStyle'] as String?, PlayingStyle.balanced),
        pressing: _enumByName(PressingIntensity.values,
            json['pressing'] as String?, PressingIntensity.mediumPress),
        tempo: _enumByName(Tempo.values, json['tempo'] as String?, Tempo.normal),
        width: _enumByName(Width.values, json['width'] as String?, Width.normal),
        defensiveLine: _enumByName(
            DefensiveLine.values, json['defensiveLine'] as String?, DefensiveLine.medium),
        offsideTrap: json['offsideTrap'] as bool? ?? false,
        counterPress: json['counterPress'] as bool? ?? false,
        possessionFocus: _enumByName(PossessionFocus.values,
            json['possessionFocus'] as String?, PossessionFocus.shortPassing),
        setPieceAggressive: json['setPieceAggressive'] as bool? ?? false,
        targetPlayer: json['targetPlayer'] as String? ?? '',
      );
}

@immutable
class FormationSlot {
  final String position;
  final int? playerId;
  final Player? player;

  const FormationSlot({required this.position, this.playerId, this.player});

  bool get isEmpty => player == null;
}

/// One place on the pitch: the position it is for and where it sits, as a
/// fraction of the pitch box (0,0 = top-left of the attacking half shown,
/// 1,1 = bottom-right). The tactics screen uses [x]/[y] to lay out the
/// preview; [selectStartingEleven] uses [position].
@immutable
class PitchPosition {
  const PitchPosition(this.position, this.x, this.y);

  final String position;
  final double x;
  final double y;
}

/// Pitch layouts per formation, back to front.
const Map<Formation, List<PitchPosition>> kFormationLayouts = {
  Formation.fourFourTwo: [
    PitchPosition('GK', 0.5, 0.93),
    PitchPosition('LB', 0.12, 0.76),
    PitchPosition('CB', 0.37, 0.78),
    PitchPosition('CB', 0.63, 0.78),
    PitchPosition('RB', 0.88, 0.76),
    PitchPosition('LM', 0.12, 0.53),
    PitchPosition('CM', 0.37, 0.55),
    PitchPosition('CM', 0.63, 0.55),
    PitchPosition('RM', 0.88, 0.53),
    PitchPosition('ST', 0.35, 0.24),
    PitchPosition('ST', 0.65, 0.24),
  ],
  Formation.fourThreeThree: [
    PitchPosition('GK', 0.5, 0.93),
    PitchPosition('LB', 0.12, 0.76),
    PitchPosition('CB', 0.37, 0.78),
    PitchPosition('CB', 0.63, 0.78),
    PitchPosition('RB', 0.88, 0.76),
    PitchPosition('CDM', 0.5, 0.58),
    PitchPosition('CM', 0.28, 0.47),
    PitchPosition('CM', 0.72, 0.47),
    PitchPosition('LW', 0.15, 0.2),
    PitchPosition('ST', 0.5, 0.16),
    PitchPosition('RW', 0.85, 0.2),
  ],
  Formation.threeFiveTwo: [
    PitchPosition('GK', 0.5, 0.93),
    PitchPosition('CB', 0.28, 0.78),
    PitchPosition('CB', 0.5, 0.8),
    PitchPosition('CB', 0.72, 0.78),
    PitchPosition('LM', 0.1, 0.5),
    PitchPosition('CM', 0.3, 0.55),
    PitchPosition('CM', 0.5, 0.5),
    PitchPosition('CM', 0.7, 0.55),
    PitchPosition('RM', 0.9, 0.5),
    PitchPosition('ST', 0.36, 0.22),
    PitchPosition('ST', 0.64, 0.22),
  ],
  Formation.fourTwoThreeOne: [
    PitchPosition('GK', 0.5, 0.93),
    PitchPosition('LB', 0.12, 0.76),
    PitchPosition('CB', 0.37, 0.78),
    PitchPosition('CB', 0.63, 0.78),
    PitchPosition('RB', 0.88, 0.76),
    PitchPosition('CDM', 0.35, 0.58),
    PitchPosition('CDM', 0.65, 0.58),
    PitchPosition('CAM', 0.5, 0.44),
    PitchPosition('LM', 0.15, 0.35),
    PitchPosition('RM', 0.85, 0.35),
    PitchPosition('ST', 0.5, 0.18),
  ],
};

/// Positions a player can fill, ordered by how well they suit each slot.
/// Used by [selectStartingEleven] so a wide midfielder is not dropped in
/// goal or a centre-back pushed up front.
const Map<String, List<String>> kPositionAffinity = {
  'GK': ['GK'],
  'CB': ['CB', 'CDM', 'RB', 'LB'],
  'LB': ['LB', 'LM', 'CB', 'RB'],
  'RB': ['RB', 'RM', 'CB', 'LB'],
  'CDM': ['CDM', 'CM', 'CB'],
  'CM': ['CM', 'CDM', 'CAM'],
  'CAM': ['CAM', 'CM', 'AM'],
  'LM': ['LM', 'LW', 'CM', 'LB'],
  'RM': ['RM', 'RW', 'CM', 'RB'],
  'LW': ['LW', 'LM', 'ST'],
  'RW': ['RW', 'RM', 'ST'],
  'ST': ['ST', 'CF', 'LW', 'RW'],
  'CF': ['CF', 'ST', 'CAM'],
  'AM': ['AM', 'CAM', 'CM'],
};

/// Whether [player] can fill [slot] at all.
bool canFillSlot(Player player, String slot) =>
    (kPositionAffinity[player.primaryPosition] ?? const <String>[])
        .contains(slot);

/// Picks the starting XI for [formation] from [squad].
///
/// Slots are filled greedily in formation order with the best available player
/// who can fill them; any slot still empty is back-filled with the strongest
/// remaining squad member, because an incomplete XI would be worse than a
/// mis-placed one. [minFitness] mirrors the match screen: players below the
/// threshold are skipped when a fit alternative exists.
List<Player> selectStartingEleven(
  List<Player> squad,
  Formation formation, {
  double minFitness = 45,
}) {
  final fit = squad.where((p) => p.fitness > minFitness).toList();
  final pool = fit.isNotEmpty ? fit : [...squad];
  final remaining = [...pool];
  final picked = <Player>[];

  void takeBest(bool Function(Player) ok) {
    remaining.sort((a, b) => b.ovr.compareTo(a.ovr));
    final index = remaining.indexWhere(ok);
    if (index < 0) return;
    picked.add(remaining.removeAt(index));
  }

  for (final slot in kFormationLayouts[formation] ?? const <PitchPosition>[]) {
    takeBest((p) => canFillSlot(p, slot.position));
  }
  // Back-fill anything the formation could not fill from real positions.
  while (picked.length < kFormationLayouts[formation]!.length &&
      remaining.isNotEmpty) {
    takeBest((_) => true);
  }
  return picked;
}

/// The eleven players [formation] would start, paired with their slot, for
/// the pitch preview. Slots with no player come back with a null player.
List<FormationSlot> formationPreview(List<Player> squad, Formation formation) {
  final xi = selectStartingEleven(squad, formation);
  final layout = kFormationLayouts[formation] ?? const <PitchPosition>[];
  return [
    for (var i = 0; i < layout.length; i++)
      FormationSlot(
        position: layout[i].position,
        player: i < xi.length ? xi[i] : null,
      ),
  ];
}

/// The out-field players of the starting XI (the goalkeeper is tracked
/// separately by the match engine).
List<Player> startingOutfield(List<Player> squad, Formation formation) =>
    selectStartingEleven(squad, formation)
        .where((p) => p.primaryPosition != 'GK')
        .toList();

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}