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
    List<Player> homeBench = const [],
    List<Player> awayBench = const [],
    Tactic? homeTactic,
    Tactic? awayTactic,
  }) {
    final events = <MatchEvent>[];
    final homeMomentum = <double>[];
    final awayMomentum = <double>[];

    final homePower = _calcTeamPower(homeSquad, homeGoalkeeper, homeTactic);
    final awayPower = _calcTeamPower(awaySquad, awayGoalkeeper, awayTactic);
    // A small home advantage: enough to break an even tie on paper, never
    // enough to make an away fixture feel decided before kick-off.
    final homeEdge = (homePower + 1.5) - awayPower;

    // Who is on the pitch right now, who is still on the bench, and the
    // minutes everyone has played. Substitutions update these in place, so
    // the rest of the simulation works off the current eleven.
    final homeSide = _MatchSide(homeSquad, homeBench);
    final awaySide = _MatchSide(awaySquad, awayBench);

    var homeGoals = 0;
    var awayGoals = 0;
    // Goal and assist tallies are keyed by player id, never by name: two
    // players in one squad can share a name, and a shared name would merge
    // their days into one line of the ratings sheet.
    final homeScorers = <int, int>{};
    final awayScorers = <int, int>{};
    final homeAssists = <int, int>{};
    final awayAssists = <int, int>{};

    events.add(MatchEvent(
      type: 'kickoff',
      team: 'home',
      player: '',
      description: 'Kick-off. The match is under way.',
      minute: 0,
      homeScore: 0,
      awayScore: 0,
    ));

    var minute = 0;
    var halfTimeAdded = false;

    while (minute < matchMinutes) {
      minute += _getMinuteIncrement(homeTactic, awayTactic);
      if (minute > matchMinutes) minute = matchMinutes;

      if (!halfTimeAdded && minute > 45) {
        events.add(MatchEvent(
          type: 'halfTime',
          team: 'home',
          player: '',
          description: 'Half-time: $homeGoals - $awayGoals.',
          minute: 45,
          homeScore: homeGoals,
          awayScore: awayGoals,
        ));
        halfTimeAdded = true;
      }

      // Momentum follows the stronger side: the favourite spends more of the
      // match on the front foot, but the underdog still gets spells.
      final double momentum;
      if (homeEdge >= 0) {
        momentum = 0.5 + rng.nextDouble() * 0.5;
      } else {
        momentum = rng.nextDouble() * 0.5;
      }
      homeMomentum.add(momentum * 100);
      awayMomentum.add((1 - momentum) * 100);

      final homeAttacks = rng.nextDouble() < momentum;
      final attackSide = homeAttacks ? homeSide : awaySide;
      final defenceSide = homeAttacks ? awaySide : homeSide;
      final attackSquad = attackSide.onPitch;
      final defenceSquad = defenceSide.onPitch;
      final attackRating = homeAttacks ? homePower + 1.5 : awayPower;
      final defenceRating = homeAttacks ? awayPower : homePower;
      final team = homeAttacks ? 'home' : 'away';
      final attacker = _randomPlayer(attackSquad);
      final defender = _randomPlayer(defenceSquad);

      // Expected goals rise with the attacking side's edge. The normal tempo
      // gives roughly 22 chunks, so ~0.10 per chunk lands a full match near
      // the 2-3 goal range instead of the goalless run the first draft had.
      final goalChance =
          (0.10 + (attackRating - defenceRating) * 0.0025).clamp(0.03, 0.18);
      final roll = rng.nextDouble();

      if (roll < goalChance) {
        final assist =
            rng.nextDouble() < 0.7 ? _randomPlayer(attackSquad) : null;
        final assistName = (assist != null && assist.name != attacker.name)
            ? assist.name
            : null;
        final assistId = assistName == null ? null : assist!.id;
        if (homeAttacks) {
          homeGoals++;
        } else {
          awayGoals++;
        }
        (homeAttacks ? homeScorers : awayScorers)
            .update(attacker.id, (v) => v + 1, ifAbsent: () => 1);
        if (assistId != null) {
          (homeAttacks ? homeAssists : awayAssists)
              .update(assistId, (v) => v + 1, ifAbsent: () => 1);
        }
        events.add(MatchEvent(
          type: 'goal',
          team: team,
          player: attacker.name,
          description: _goalDescription(attacker.name, assistName),
          minute: minute,
          homeScore: homeGoals,
          awayScore: awayGoals,
          extraData: assistName == null ? null : {'assist': assistName},
        ));
        // One decisive moment per chunk keeps the feed readable at speed.
        continue;
      }

      if (roll < goalChance + 0.16) {
        final saved = rng.nextDouble() < 0.5;
        events.add(MatchEvent(
          type: saved ? 'save' : 'chance',
          team: team,
          player: attacker.name,
          description: saved
              ? '${attacker.name} forces a save from the goalkeeper.'
              : '${attacker.name} drags a shot wide of the post.',
          minute: minute,
        ));
      } else if (roll < goalChance + 0.30) {
        // Fouls are the bulk of the tackling in a match; a fraction of them
        // are late enough to be booked. The card is shown at the same minute
        // as the foul that earned it.
        final cardRoll = rng.nextDouble();
        if (cardRoll < 0.16) {
          events.add(MatchEvent(
            type: 'card',
            team: team == 'home' ? 'away' : 'home',
            player: defender.name,
            description: 'Yellow card: ${defender.name} is booked for '
                'bringing down ${attacker.name}.',
            minute: minute,
          ));
        } else {
          events.add(MatchEvent(
            type: 'foul',
            team: team == 'home' ? 'away' : 'home',
            player: defender.name,
            description: '${defender.name} fouls ${attacker.name}.',
            minute: minute,
          ));
        }
      } else if (roll < goalChance + 0.38) {
        events.add(MatchEvent(
          type: 'corner',
          team: team,
          player: attacker.name,
          description: '${attacker.name} wins a corner.',
          minute: minute,
        ));
      } else if (roll < goalChance + 0.46) {
        events.add(MatchEvent(
          type: 'offside',
          team: team,
          player: attacker.name,
          description: '${attacker.name} is caught offside.',
          minute: minute,
        ));
      } else if (roll < goalChance + 0.50) {
        events.add(MatchEvent(
          type: 'injury',
          team: team,
          player: attacker.name,
          description: '${attacker.name} is down and needs treatment.',
          minute: minute,
          // The physio resolves the victim by id: a name can belong to two
          // players, and the wrong twin must not be sent to the treatment room.
          extraData: {'playerId': attacker.id},
        ));
        // A knock that stops play usually ends the player's afternoon: the
        // freshest substitute comes on right away, unless the bench is spent.
        final replacement = _benchPick(attackSide);
        if (replacement != null &&
            _substitute(attackSide, attacker, replacement, minute)) {
          events.add(MatchEvent(
            type: 'sub',
            team: team,
            player: attacker.name,
            description: '${replacement.name} replaces ${attacker.name}, '
                'who cannot continue.',
            minute: minute,
          ));
        }
      } else {
        events.add(MatchEvent(
          type: 'commentary',
          team: team,
          player: '',
          description: _generateCommentary(minute, homeGoals, awayGoals),
          minute: minute,
        ));
      }

      // Fresh legs in the closing half-hour: the bench sends the freshest
      // substitute on for the most tired body on the pitch. The old feed
      // invented a substitute from the XI purely to fill the event.
      if (minute >= 55) {
        _freshnessPass(homeSide, 'home', minute, events);
        _freshnessPass(awaySide, 'away', minute, events);
      }
    }

    final homeRatings = _generateRatings(
      homeGoalkeeper,
      homeSide,
      goals: homeScorers,
      assists: homeAssists,
      goalDifference: homeGoals - awayGoals,
    );
    final awayRatings = _generateRatings(
      awayGoalkeeper,
      awaySide,
      goals: awayScorers,
      assists: awayAssists,
      goalDifference: awayGoals - homeGoals,
    );

    return MatchResult(
      homeTeam: 'Home',
      awayTeam: 'Away',
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      events: events,
      homeRatings: homeRatings,
      awayRatings: awayRatings,
      homeMomentum: homeMomentum,
      awayMomentum: awayMomentum,
      fullTimeCommentary: 'Full-time: $homeGoals - $awayGoals',
    );
  }

  /// Simulates a match between two clubs from overall squad strength alone.
  ///
  /// Used to resolve the fixtures in a round that the user is not involved in,
  /// which is what makes the league table move. Running the full event loop for
  /// every other club would produce commentary nobody reads, so this returns
  /// just the scoreline. Goals are drawn from a Poisson distribution whose mean
  /// rises with the attacker's strength and falls with the defender's, so a
  /// strong favourite wins more often than it loses.
  (int, int) simulateScore({
    required double homeStrength,
    required double awayStrength,
    required Random rng,
  }) {
    // Strength is a 20-100 rating; map it to an expected-goals rate.
    final edge = (homeStrength - awayStrength) / 100.0;
    final homeLambda = (1.35 + edge * 1.1).clamp(0.15, 4.5);
    final awayLambda = (1.15 - edge * 1.1).clamp(0.15, 4.5);
    return (
      _poisson(homeLambda, rng),
      _poisson(awayLambda, rng),
    );
  }

  /// Knuth's method: cheap, bounded and fine for the small lambdas used here.
  int _poisson(double lambda, Random rng) {
    final threshold = exp(-lambda);
    var k = 0;
    var product = rng.nextDouble();
    while (product > threshold && k < 12) {
      k += 1;
      product *= rng.nextDouble();
    }
    // The count is [k]: the first draw already stands for the first
    // multiplication, so a first draw under the threshold is zero goals. The
    // old `k - 1` returned minus one there, which shipped negative scorelines
    // into rival fixtures and biased every simulated match a goal low.
    return k;
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
        case PlayingStyle.attacking:
          total *= 1.05;
          break;
        case PlayingStyle.defensive:
          total *= 0.95;
          break;
        case PlayingStyle.possession:
          total *= 1.03;
          break;
        case PlayingStyle.counterAttack:
          total *= 1.02;
          break;
        default:
          break;
      }
    }
    return total.clamp(20.0, 100.0);
  }

  Player _randomPlayer(List<Player> squad) {
    return squad[rng.nextInt(squad.length)];
  }

  String _goalDescription(String scorer, String? assist) {
    const finishes = [
      'fires it into the bottom corner',
      'heads it home from close range',
      'slots it past the goalkeeper',
      'curls one in from the edge of the box',
      'taps in at the back post',
      'lashes it in off the underside of the bar',
    ];
    final finish = finishes[rng.nextInt(finishes.length)];
    final assistText = assist == null ? '' : ', assisted by $assist';
    return 'GOAL! $scorer $finish$assistText.';
  }

  /// The freshest available substitute — an injured bench player cannot come
  /// on, and keepers stay out of out-field substitutions because the engine
  /// never changes keepers mid-match.
  ///
  /// A freshness change also wants the stand-in to actually be fresher than
  /// the man coming off: [atLeastAsFreshAs] rejects a tired bench.
  Player? _benchPick(_MatchSide side, {Player? atLeastAsFreshAs}) {
    final available = [
      for (final p in side.bench)
        if (!p.isInjured && p.primaryPosition != 'GK') p,
    ];
    if (available.isEmpty) return null;
    available.sort((a, b) {
      if (a.fitness != b.fitness) return b.fitness.compareTo(a.fitness);
      return b.ovr.compareTo(a.ovr);
    });
    final pick = available.first;
    if (atLeastAsFreshAs != null &&
        pick.fitness < atLeastAsFreshAs.fitness) {
      return null;
    }
    return pick;
  }

  /// Swaps [on] in for [off] when the side still has changes left; records
  /// the minutes both will be credited with.
  bool _substitute(_MatchSide side, Player off, Player on, int minute) {
    if (side.subs >= maxSubstitutions) return false;
    side.onPitch.removeWhere((p) => p.id == off.id);
    side.onPitch.add(on);
    side.bench.removeWhere((p) => p.id == on.id);
    side.offAt[off.id] = minute;
    side.onAt[on.id] = minute;
    side.subbedOn.add(on);
    side.subs += 1;
    return true;
  }

  /// The closing-half-hour change: with a small chance, the most tired body
  /// on the pitch makes way for the freshest substitute. No bench (or a
  /// bench that is no fresher) means no change and no event.
  void _freshnessPass(
    _MatchSide side,
    String team,
    int minute,
    List<MatchEvent> events,
  ) {
    if (side.subs >= maxSubstitutions || side.bench.isEmpty) return;
    if (rng.nextDouble() >= 0.14) return;
    final onPitch = [...side.onPitch]
      ..sort((a, b) {
        if (a.fitness != b.fitness) return a.fitness.compareTo(b.fitness);
        return a.ovr.compareTo(b.ovr);
      });
    for (final tired in onPitch) {
      final fresh = _benchPick(side, atLeastAsFreshAs: tired);
      if (fresh == null) continue;
      if (!_substitute(side, tired, fresh, minute)) return;
      events.add(MatchEvent(
        type: 'sub',
        team: team,
        player: tired.name,
        description: '${fresh.name} comes on for ${tired.name}.',
        minute: minute,
      ));
      return;
    }
  }

  List<PlayerRating> _generateRatings(
    Player goalkeeper,
    _MatchSide side, {
    required Map<int, int> goals,
    required Map<int, int> assists,
    required int goalDifference,
  }) {
    PlayerRating rate(Player p, int minutes, {required bool started}) {
      final scored = goals[p.id] ?? 0;
      final assisted = assists[p.id] ?? 0;
      // Start from a par performance for the player's quality, then let the
      // result and their direct contributions move it.
      var rating = 6.0 + (p.ovr - 70) / 14.0;
      rating += rng.nextDouble() * 1.4 - 0.7;
      if (goalDifference > 0) rating += 0.8;
      if (goalDifference < 0) rating -= 0.5;
      rating += scored * 1.2 + assisted * 0.5;
      // Keep the tenth: a 7.4 and a 7.9 are different performances, and the
      // old `.round()` threw that away before it ever reached the squad.
      final stepped = (rating.clamp(1.0, 10.0) * 10).round() / 10;
      return PlayerRating(
        playerName: p.name,
        playerId: p.id,
        position: p.primaryPosition,
        rating: stepped,
        goals: scored,
        assists: assisted,
        minutes: minutes,
        started: started,
      );
    }

    return [
      // The keeper plays the whole match and is rated like everyone else —
      // he used to be left out entirely, which quietly cost him every
      // appearance, minute and rating in his career record.
      rate(goalkeeper, matchMinutes, started: true),
      for (final p in side.squad)
        rate(p, side.offAt[p.id] ?? matchMinutes, started: true),
      for (final p in side.subbedOn)
        rate(p, matchMinutes - (side.onAt[p.id] ?? matchMinutes),
            started: false),
    ];
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

/// One side's players during a match: the eleven that started, who is on the
/// pitch right now, who is left on the bench, and — once the whistle goes —
/// who played how long.
class _MatchSide {
  _MatchSide(List<Player> starters, List<Player> bench)
      : squad = [...starters],
        onPitch = [...starters],
        bench = [
          // A bench that repeats an out-field starter is ignored: the same
          // body cannot sit on the bench and play.
          for (final substitute in bench)
            if (!starters.any((s) => s.id == substitute.id)) substitute,
        ];

  /// The eleven that started, in order; ratings are reported in this order
  /// followed by the substitutes.
  final List<Player> squad;

  /// The mutable current eleven the simulation picks attackers, defenders and
  /// injuries from.
  final List<Player> onPitch;

  /// The substitutes still available.
  final List<Player> bench;

  /// Substitutes who have come on, in appearance order.
  final List<Player> subbedOn = [];

  /// The minute a starter left the pitch, keyed by player id.
  final Map<int, int> offAt = {};

  /// The minute a substitute came on, keyed by player id.
  final Map<int, int> onAt = {};

  /// Changes made so far, against [maxSubstitutions].
  int subs = 0;
}
