import 'dart:math';

import '../models/player.dart';
import '../models/season.dart';
import '../models/team.dart';

/// Credits a simulated scoreline to individual players.
///
/// Rival fixtures run through `simulateScore`, which produces goals but no
/// scorers. This gives those goals a plausible author from the club's squad —
/// strikers and wingers score most, creators assist most, defenders and
/// keepers almost never — so the league's top scorer list moves for every
/// club, not only the manager's. The RNG is the round's own seeded generator,
/// so a restored save replays the same names.
class ScorerAttributionService {
  const ScorerAttributionService();

  /// The share of goals that are assisted, close to real scorekeeping.
  static const double _assistChance = 0.72;

  void attribute({
    required SeasonState season,
    required Team home,
    required Team away,
    required int homeGoals,
    required int awayGoals,
    required Random rng,
  }) {
    _attributeSide(season, home, homeGoals, rng);
    _attributeSide(season, away, awayGoals, rng);
  }

  void _attributeSide(SeasonState season, Team club, int goals, Random rng) {
    if (goals <= 0 || club.squad.isEmpty) return;
    for (var i = 0; i < goals; i++) {
      final scorer = _weightedPick(club.squad, _scoringWeight, rng);
      if (scorer == null) return;
      season.recordContribution(
        playerId: scorer.id,
        playerName: scorer.name,
        clubId: club.id,
        clubName: club.name,
        goals: 1,
      );

      if (rng.nextDouble() < _assistChance) {
        final assistants = [
          for (final p in club.squad)
            if (p.id != scorer.id) p,
        ];
        final assistant = _weightedPick(assistants, _assistWeight, rng);
        if (assistant != null) {
          season.recordContribution(
            playerId: assistant.id,
            playerName: assistant.name,
            clubId: club.id,
            clubName: club.name,
            assists: 1,
          );
        }
      }
    }
  }

  /// Scoring likelihood by position and quality. A keeper's weight is zero:
  /// an outfield scorer is always the sensible author.
  double _scoringWeight(Player p) {
    final base = switch (p.primaryPosition) {
      'ST' => 6.0,
      'CF' => 5.5,
      'LW' || 'RW' => 3.5,
      'CAM' || 'AM' => 3.0,
      'LM' || 'RM' => 2.0,
      'CM' => 1.6,
      'CDM' => 0.9,
      'LB' || 'RB' => 0.5,
      'CB' => 0.4,
      _ => 0.0,
    };
    return base * (0.4 + p.ovr / 100);
  }

  /// Assist likelihood by position: the creators, not the finishers.
  double _assistWeight(Player p) {
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
    return base * (0.4 + p.ovr / 130);
  }

  Player? _weightedPick(
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
