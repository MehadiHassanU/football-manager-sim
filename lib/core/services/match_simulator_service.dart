import 'dart:math';

import '../models/match.dart';
import '../models/player.dart';
import '../models/tactics.dart';
import '../constants/game_constants.dart';
import '../constants/tactic_definitions.dart';

class MatchSimulatorService {
  final Random rng;

  MatchSimulatorService({Random? rng}) : rng = rng ?? Random();

  MatchResult simulateMatch({
    required Player homeGoalkeeper,
    required List<Player> homeSquad,
    required Player awayGoalkeeper,
    required List<Player> awaySquad,
    Tactic? homeTactic,
    Tactic? awayTactic,
  }) {
    final events = <MatchEvent>[];
    final homeMomentum = <double>[];
    final awayMomentum = <double>[];

    int homeGoals = 0;
    int awayGoals = 0;
    double homePower = 0;
    double awayPower = 0;

    int minute = 0;
    while (minute < matchMinutes) {
      minute += _getMinuteIncrement(homeTactic, awayTactic);
      if (minute > matchMinutes) minute = matchMinutes;

      homePower = _calcTeamPower(homeSquad, homeGoalkeeper, homeTactic);
      awayPower = _calcTeamPower(awaySquad, awayGoalkeeper, awayTactic);

      final double momentum;
      if (homePower > awayPower) {
        momentum = 0.5 + rng.nextDouble() * 0.5;
      } else {
        momentum = rng.nextDouble() * 0.5;
      }
      homeMomentum.add(momentum * 100);
      awayMomentum.add((1 - momentum) * 100);

      if (homePower > awayPower) {
        if (rng.nextDouble() < 0.08) {
          homeGoals++;
          final scorer = _randomPlayer(homeSquad);
          events.add(MatchEvent(
            type: 'goal', team: 'home', player: scorer.name,
            description: 'GOAL! $scorer.name scores! $homeSquad first vs $awaySquad',
            minute: minute, homeScore: homeGoals, awayScore: awayGoals,
          ));
        } else if (rng.nextDouble() < 0.15) {
          final player = _randomPlayer(homeSquad);
          events.add(MatchEvent(
            type: 'chance', team: 'home', player: player.name,
            description: '$player.name has a chance!',
            minute: minute,
          ));
        }
      } else {
        if (rng.nextDouble() < 0.08) {
          awayGoals++;
          final scorer = _randomPlayer(awaySquad);
          events.add(MatchEvent(
            type: 'goal', team: 'away', player: scorer.name,
            description: 'GOAL! $scorer.name equalizes!',
            minute: minute, homeScore: homeGoals, awayScore: awayGoals,
          ));
        } else if (rng.nextDouble() < 0.15) {
          final player = _randomPlayer(awaySquad);
          events.add(MatchEvent(
            type: 'chance', team: 'away', player: player.name,
            description: '$player.name has a chance!',
            minute: minute,
          ));
        }
      }

      if (minute < matchMinutes) {
        final commentary = _generateCommentary(minute, homeGoals, awayGoals);
        events.add(MatchEvent(
          type: 'commentary', team: 'home', player: '',
          description: commentary, minute: minute,
        ));
      }
    }

    final homePlayerRatings = _generateRatings(homeSquad, homeGoals, homePower > awayPower ? 1 : 0);
    final awayPlayerRatings = _generateRatings(awaySquad, 0, awayPower > homePower ? 1 : 0);

    return MatchResult(
      homeTeam: 'Home',
      awayTeam: 'Away',
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      events: events,
      playerRatings: [...homePlayerRatings, ...awayPlayerRatings],
      homeMomentum: homeMomentum,
      awayMomentum: awayMomentum,
      fullTimeCommentary: 'Full-time: $homeGoals - $awayGoals',
    );
  }

  int _getMinuteIncrement(Tactic? home, Tactic? away) {
    if ((home?.tempo ?? Tempo.normal) == Tempo.fast ||
        (away?.tempo ?? Tempo.normal) == Tempo.fast) {
      return rng.nextInt(3) + 1;
    }
    return rng.nextInt(5) + 2;
  }

  double _calcTeamPower(List<Player> squad, Player gk, Tactic? tactic) {
    if (squad.isEmpty) return 50.0;
    double total = 0.0;
    for (final p in squad) {
      total += p.ovr.toDouble();
    }
    total += gk.ovr.toDouble();
    total /= (squad.length + 1);

    if (tactic != null) {
      switch (tactic.playingStyle) {
        case PlayingStyle.attacking: total *= 1.05; break;
        case PlayingStyle.defensive: total *= 0.95; break;
        case PlayingStyle.possession: total *= 1.03; break;
        case PlayingStyle.counterAttack: total *= 1.02; break;
        default: break;
      }
    }
    return total.clamp(20.0, 100.0);
  }

  Player _randomPlayer(List<Player> squad) {
    return squad[rng.nextInt(squad.length)];
  }

  List<PlayerRating> _generateRatings(List<Player> squad, int playerGoals, int teamWon) {
    return squad.take(11).map((p) {
      int rating = p.ovr ~/ 10;
      rating += rng.nextInt(5) - 2;
      if (teamWon == 1) rating += 2;
      if (playerGoals > 0) rating += 3;
      rating = rating.clamp(1, 10);
      return PlayerRating(
        playerName: p.name,
        position: p.primaryPosition,
        rating: rating,
        goals: playerGoals > 0 && rng.nextDouble() < 0.3 ? 1 : 0,
        assists: rng.nextDouble() < 0.2 ? 1 : 0,
        minutes: matchMinutes,
        started: true,
      );
    }).toList();
  }

  String _generateCommentary(int minute, int homeGoals, int awayGoals) {
    final events = [
      'Minute $minute - $homeGoals-$awayGoals. The match continues.',
      'At $minute minutes, still $homeGoals-$awayGoals.',
      'Minute $minute sees the teams still locked at $homeGoals-$awayGoals.',
      '$minute minutes played. Score: $homeGoals-$awayGoals.',
      'The clock ticks past $minute as the score remains $homeGoals-$awayGoals.',
    ];
    return events[rng.nextInt(events.length)];
  }
}