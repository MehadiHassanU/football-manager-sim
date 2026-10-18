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

  /// The stored manual pick for this slot, or null when the assistant picks.
  final int? playerId;

  /// Who will actually play here once availability is taken into account.
  final Player? player;

  const FormationSlot({required this.position, this.playerId, this.player});

  bool get isEmpty => player == null;

  /// Whether the manager stored a pick for this slot.
  bool get manual => playerId != null;

  /// True when a stored pick exists but somebody else will play here — he is
  /// injured or out of shape and a fit alternative took over.
  bool get replaced {
    final current = player;
    return playerId != null && (current == null || current.id != playerId);
  }
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

/// Builds the starting slots for [formation] from [squad], honouring the
/// manager's stored picks in [manualIds].
///
/// [manualIds] is sparse and slot-indexed: index 0 is the goalkeeper, and the
/// index order matches [kFormationLayouts]. A value of `0` means "the
/// assistant picks this slot". An empty list is the entirely automatic XI.
///
/// Slots without a stored pick are filled greedily in formation order with the
/// best available player who can fill them; any slot still empty is back-filled
/// with the strongest remaining squad member, because an incomplete XI would be
/// worse than a mis-placed one. [minFitness] mirrors the match screen: players
/// below the threshold are skipped when a fit alternative exists. Players in
/// the treatment room slide down the pecking order the same way — a stored pick
/// who is injured or out of shape only takes the field when nobody fit can
/// stand in for him, and the slot reports [FormationSlot.replaced] until then.
List<FormationSlot> resolveFormationSlots(
  List<Player> squad,
  Formation formation,
  List<int> manualIds, {
  double minFitness = 45,
}) {
  final layout = kFormationLayouts[formation] ?? const <PitchPosition>[];
  final fit = squad.where((p) => p.fitness > minFitness).toList();
  final fitEmpty = fit.isEmpty;
  final pool = fitEmpty ? [...squad] : fit;
  final byId = {for (final p in squad) p.id: p};

  final picked = List<Player?>.filled(layout.length, null);
  final stored = List<int?>.filled(layout.length, null);
  final lastResort = <int, Player>{};
  final used = <int>{};

  // First pass: seat the manager's picks.
  for (var i = 0; i < layout.length && i < manualIds.length; i++) {
    final id = manualIds[i];
    if (id <= 0) continue;
    final player = byId[id];
    if (player == null) continue; // he left the club: back to the assistant
    stored[i] = id;
    final available = !player.isInjured && (fitEmpty || player.fitness > minFitness);
    if (available && used.add(player.id)) {
      picked[i] = player;
    } else {
      lastResort[i] = player;
    }
  }

  // The assistant fills the rest. A pick who is out of action is kept out of
  // the general pool: he only ever plays his own slot, and only as a last
  // resort.
  final deferred = {for (final p in lastResort.values) p.id};
  final remaining = [
    for (final p in pool)
      if (!used.contains(p.id) && !deferred.contains(p.id)) p,
  ];

  void takeBest(int slotIndex, bool Function(Player) ok) {
    remaining.sort((a, b) {
      // Fit bodies first: the injured are only picked when the alternative
      // would be to leave the slot empty.
      if (a.isInjured != b.isInjured) return a.isInjured ? 1 : -1;
      return b.ovr.compareTo(a.ovr);
    });
    final index = remaining.indexWhere(ok);
    if (index < 0) return;
    final player = remaining.removeAt(index);
    used.add(player.id);
    picked[slotIndex] = player;
  }

  for (var i = 0; i < layout.length; i++) {
    if (picked[i] != null) continue;
    final position = layout[i].position;
    takeBest(i, (p) => canFillSlot(p, position));
  }
  // Back-fill anything the formation could not fill from real positions.
  for (var i = 0; i < layout.length; i++) {
    if (picked[i] != null) continue;
    takeBest(i, (_) => true);
  }
  // A stored pick who is out of action still plays when nobody fit could take
  // his slot — the same last word as the assistant's pecking order.
  for (final entry in lastResort.entries) {
    if (picked[entry.key] == null && used.add(entry.value.id)) {
      picked[entry.key] = entry.value;
    }
  }

  return [
    for (var i = 0; i < layout.length; i++)
      FormationSlot(
        position: layout[i].position,
        playerId: stored[i],
        player: picked[i],
      ),
  ];
}

/// The eleven players [formation] would start, in slot order, honouring the
/// manager's stored picks in [manualIds] (empty = assistant's pick).
List<Player> resolveStartingEleven(
  List<Player> squad,
  Formation formation,
  List<int> manualIds, {
  double minFitness = 45,
}) {
  final slots =
      resolveFormationSlots(squad, formation, manualIds, minFitness: minFitness);
  return [
    for (final slot in slots)
      if (slot.player != null) slot.player!,
  ];
}

/// Picks the starting XI for [formation] from [squad]. See
/// [resolveFormationSlots] for the full rules; this is the all-automatic
/// entry point.
List<Player> selectStartingEleven(
  List<Player> squad,
  Formation formation, {
  double minFitness = 45,
}) =>
    resolveStartingEleven(squad, formation, const [], minFitness: minFitness);

/// The eleven players [formation] would start, paired with their slot, for
/// the pitch preview. Slots with no player come back with a null player.
List<FormationSlot> formationPreview(List<Player> squad, Formation formation) =>
    resolveFormationSlots(squad, formation, const []);

/// The out-field players of the starting XI (the goalkeeper is tracked
/// separately by the match engine).
List<Player> startingOutfield(List<Player> squad, Formation formation) =>
    selectStartingEleven(squad, formation)
        .where((p) => p.primaryPosition != 'GK')
        .toList();

/// Splits the resolved starting XI into the parts the match engine wants:
/// the keeper (when the formation could place one) and the out-field ten,
/// honouring the manager's stored picks in [manualIds].
///
/// When the squad has no keeper at all, the player standing in the goal slot
/// is no keeper by trade: the match screen brings a synthetic keeper on
/// instead, so he is handed back with the out-field players.
({Player? goalkeeper, List<Player> outfield}) resolveMatchLineup(
  List<Player> squad,
  Formation formation,
  List<int> manualIds, {
  double minFitness = 45,
}) {
  final slots =
      resolveFormationSlots(squad, formation, manualIds, minFitness: minFitness);
  final keeperSlot = slots.isEmpty ? null : slots.first.player;
  final goalkeeper =
      keeperSlot != null && keeperSlot.primaryPosition == 'GK' ? keeperSlot : null;
  final outfield = [
    for (var i = 1; i < slots.length; i++)
      if (slots[i].player != null) slots[i].player!,
    if (goalkeeper == null && keeperSlot != null) keeperSlot,
  ];
  return (
    goalkeeper: goalkeeper,
    outfield: [
      for (final p in outfield)
        if (p.primaryPosition != 'GK') p,
    ],
  );
}

/// Re-seats the stored picks after a formation change from [from] to [to].
///
/// A pick keeps his slot when the new shape asks for a position he can fill;
/// otherwise he is moved to the first empty slot he suits, and a pick with no
/// home anywhere in the new shape goes back to the assistant. Picks that have
/// left the club are dropped. Returns the new sparse, slot-indexed list.
List<int> reconcileXiPicks(
  List<int> manualIds,
  Formation from,
  Formation to,
  List<Player> squad,
) {
  final oldLayout = kFormationLayouts[from] ?? const <PitchPosition>[];
  final newLayout = kFormationLayouts[to] ?? const <PitchPosition>[];
  if (manualIds.isEmpty || newLayout.isEmpty) return const [];

  final byId = {for (final p in squad) p.id: p};
  final picks = <(int, Player)>[];
  for (var i = 0; i < oldLayout.length && i < manualIds.length; i++) {
    final id = manualIds[i];
    if (id <= 0) continue;
    final player = byId[id];
    if (player == null) continue; // already gone: no pick to carry over
    picks.add((i, player));
  }

  final result = List<int>.generate(newLayout.length, (_) => 0, growable: true);
  final placed = <int>{};

  // Same index, compatible position: keep him where he is.
  for (final (oldIndex, player) in picks) {
    if (oldIndex >= newLayout.length) continue;
    if (!canFillSlot(player, newLayout[oldIndex].position)) continue;
    if (!placed.add(player.id)) continue;
    result[oldIndex] = player.id;
  }
  // Relocate the rest to any empty slot they suit.
  for (final (_, player) in picks) {
    if (placed.contains(player.id)) continue;
    for (var j = 0; j < newLayout.length; j++) {
      if (result[j] != 0) continue;
      if (!canFillSlot(player, newLayout[j].position)) continue;
      result[j] = player.id;
      placed.add(player.id);
      break;
    }
  }

  while (result.isNotEmpty && result.last == 0) {
    result.removeLast();
  }
  return result;
}

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}