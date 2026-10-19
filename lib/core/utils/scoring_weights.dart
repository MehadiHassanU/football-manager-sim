import 'dart:math';

import '../models/player.dart';

/// Who gets the credit when a goal (or an assist) has to be given an author.
///
/// Two places need the same answer: rival fixtures, which are simulated from a
/// scoreline alone and credited by `ScorerAttributionService`, and the live
/// match engine, which picks a name for every chance and goal. They used to
/// disagree — the engine drew its "attacker" uniformly from the ten outfield
/// players, so a centre-back had exactly the same scoring odds as a striker,
/// while the league-wide list used sensible position weights. Sharing the
/// table here means the top-scorer list and the manager's own match feed can
/// never tell different stories about the same squad.
///
/// The base number is the position's share of the goals. It is then scaled by
/// the attribute that actually decides the moment — finishing for a scorer,
/// vision for a creator — and by overall quality, so two strikers in the same
/// eleven split the chances by how good they are rather than by a coin flip.
class ScoringWeights {
  ScoringWeights._();

  /// Scoring likelihood by position and quality. Keepers weigh zero: an
  /// outfield scorer is always the sensible author.
  static double scoring(Player p) {
    final base = switch (p.primaryPosition) {
      'ST' => 6.0,
      'CF' => 5.5,
      'LW' || 'RW' => 3.5,
      'CAM' || 'AM' => 3.0,
      'LM' || 'RM' => 2.0,
      'CM' => 1.6,
      'CDM' => 0.9,
      'LB' || 'RB' => 0.5,
      // Centre-backs still score from set pieces now and then — just rarely
      // enough that a season's top scorer is never one of them.
      'CB' => 0.4,
      _ => 0.0,
    };
    final finish = 0.6 + (p.finishing.clamp(1, 99) / 99) * 0.7;
    return base * finish * (0.5 + p.ovr.clamp(20, 99) / 100);
  }

  /// Assist likelihood by position: the creators, not the finishers.
  static double assist(Player p) {
    final base = switch (p.primaryPosition) {
      'CAM' || 'AM' => 4.0,
      'LW' || 'RW' => 3.2,
      'CM' => 3.0,
      'LM' || 'RM' => 2.6,
      'CF' => 2.2,
      'ST' => 2.0,
      'CDM' => 1.4,
      'LB' || 'RB' => 1.4,
      'CB' => 0.6,
      _ => 0.0,
    };
    final vision = 0.6 + (p.vision.clamp(1, 99) / 99) * 0.7;
    return base * vision * (0.4 + p.ovr.clamp(20, 99) / 130);
  }

  /// Roulette-wheel pick weighted by [weight].
  ///
  /// Returns null when the list is empty or every candidate weighs zero, so a
  /// caller can fall back instead of throwing or crediting a keeper.
  static Player? pick(
    List<Player> candidates,
    double Function(Player) weight,
    Random rng,
  ) {
    var total = 0.0;
    for (final p in candidates) {
      total += weight(p);
    }
    if (total <= 0) return null;
    var roll = rng.nextDouble() * total;
    for (final p in candidates) {
      roll -= weight(p);
      if (roll <= 0) return p;
    }
    return candidates.last;
  }
}
