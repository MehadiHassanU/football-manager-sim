import 'dart:math';

import '../models/season.dart';
import '../models/team.dart';
import '../utils/scoring_weights.dart';

/// Credits a simulated scoreline to individual players.
///
/// Rival fixtures run through `simulateScore`, which produces goals but no
/// scorers. This gives those goals a plausible author from the club's squad —
/// strikers and wingers score most, creators assist most, defenders and
/// keepers almost never — so the league's top scorer list moves for every
/// club, not only the manager's. The RNG is the round's own seeded generator,
/// so a restored save replays the same names.
///
/// The weights live in [ScoringWeights] and are shared with the live match
/// engine, which used to pick scorers uniformly and could send a defender to
/// the top of the chart.
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
      final scorer = ScoringWeights.pick(
        club.squad,
        ScoringWeights.scoring,
        rng,
      );
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
        final assistant = ScoringWeights.pick(
          assistants,
          ScoringWeights.assist,
          rng,
        );
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
}
