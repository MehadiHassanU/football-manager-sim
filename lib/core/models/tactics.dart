import 'package:flutter/material.dart';
import 'package:meta/meta.dart';
import '../constants/tactic_definitions.dart';
import 'player.dart';

class Tactic {
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
}

@immutable
class FormationSlot {
  final String position;
  final int? playerId;
  final Player? player;

  const FormationSlot({required this.position, this.playerId, this.player});

  bool get isEmpty => player == null;
}