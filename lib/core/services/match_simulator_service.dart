import 'dart:math';

import '../models/match.dart';
import '../models/player.dart';
import '../models/tactics.dart';
import '../constants/game_constants.dart';
import '../constants/tactic_definitions.dart';

/// Simulates football matches.
///
/// [simulateMatch] plays a whole match in one call, which is what every
/// fixture the manager is not watching needs. [MatchSimulation] is the same
/// engine behind a pause button: the live screen drives it a minute at a time
/// so a substitution or a sending-off can change the rest of the match.
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
    final simulation = MatchSimulation(
      homeGoalkeeper: homeGoalkeeper,
      homeSquad: homeSquad,
      awayGoalkeeper: awayGoalkeeper,
      awaySquad: awaySquad,
      homeBench: homeBench,
      awayBench: awayBench,
      homeTactic: homeTactic,
      awayTactic: awayTactic,
      rng: rng,
    );
    simulation.advanceTo(matchMinutes);
    return simulation.finish();
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
}

/// One match that can be played a chunk at a time.
///
/// The engine used to pre-compute the whole ninety minutes at kick-off and the
/// screen merely replayed the events. That made mid-match changes impossible:
/// the manager could watch his side lose its shape, but any substitute he
/// picked would only ever play in the next match. Here the clock is owned by
/// the caller: [advanceTo] plays every chunk that finishes by the requested
/// minute, and between calls the manager can [substitute] players. The rest of
/// the match is then simulated with the eleven actually on the pitch, and a
/// red card leaves a side a man down for the remainder.
///
/// Chunks are kept whole so pausing never changes the dice: a chunk that
/// would run past the requested minute is left pending, with its minute
/// increment already drawn, and taken on the next [advanceTo]. Playing the
/// whole match in one call therefore uses exactly the same random numbers in
/// exactly the same order as a match played in a hundred pieces.
class MatchSimulation {
  MatchSimulation({
    required this.homeGoalkeeper,
    required List<Player> homeSquad,
    required this.awayGoalkeeper,
    required List<Player> awaySquad,
    List<Player> homeBench = const [],
    List<Player> awayBench = const [],
    Tactic? homeTactic,
    Tactic? awayTactic,
    Random? rng,
    this.manualHome = false,
    this.manualAway = false,
  })  : _rng = rng ?? Random(),
        _homeTactic = homeTactic,
        _awayTactic = awayTactic,
        _home = _MatchSide(homeSquad, homeBench, manualSubs: manualHome),
        _away = _MatchSide(awaySquad, awayBench, manualSubs: manualAway) {
    _refreshPowers();
    events.add(MatchEvent(
      type: 'kickoff',
      team: 'home',
      player: '',
      description: 'Kick-off. The match is under way.',
      minute: 0,
      homeScore: 0,
      awayScore: 0,
    ));
  }

  final Player homeGoalkeeper;
  final Player awayGoalkeeper;

  /// A side managed by the user takes no automatic substitutions: the match
  /// pauses instead and the manager decides. The opponent is always managed by
  /// the assistant, and [MatchSimulatorService.simulateMatch] leaves both sides
  /// to the assistant.
  final bool manualHome;
  final bool manualAway;

  final Tactic? _homeTactic;
  final Tactic? _awayTactic;
  final Random _rng;
  final _MatchSide _home;
  final _MatchSide _away;

  final List<MatchEvent> events = [];
  final List<double> homeMomentum = [];
  final List<double> awayMomentum = [];

  int _minute = 0;
  int? _pendingStep;
  bool _halfTimeAdded = false;

  double _homePower = 50;
  double _awayPower = 50;
  double _homeEdge = 0;

  int _homeGoals = 0;
  int _awayGoals = 0;
  // Goal and assist tallies are keyed by player id, never by name: two
  // players in one squad can share a name, and a shared name would merge
  // their days into one line of the ratings sheet.
  final Map<int, int> _homeScorers = {};
  final Map<int, int> _awayScorers = {};
  final Map<int, int> _homeAssists = {};
  final Map<int, int> _awayAssists = {};

  MatchResult? _result;

  int get minute => _minute;
  int get homeGoals => _homeGoals;
  int get awayGoals => _awayGoals;

  /// True once the clock has reached full time — not merely once [finish] has
  /// been called, so the screen can stop the ticker first.
  bool get isFinished => _minute >= matchMinutes;

  int substitutionsUsed({required bool home}) => _sideOf(home).subs;

  int substitutionsLeft({required bool home}) =>
      maxSubstitutions - _sideOf(home).subs;

  /// The outfield players currently on the pitch.
  List<Player> onPitch({required bool home}) =>
      List.unmodifiable(_sideOf(home).onPitch);

  /// The substitutes still available, injured ones included: the manager may
  /// pick anyone, and the engine refuses a body that cannot play.
  List<Player> bench({required bool home}) =>
      List.unmodifiable(_sideOf(home).bench);

  /// The players sent off, in the order they went.
  List<Player> sentOff({required bool home}) =>
      List.unmodifiable(_sideOf(home).sentOff);

  _MatchSide _sideOf(bool home) => home ? _home : _away;

  /// Plays on until the clock reaches [targetMinute], or full time.
  ///
  /// Every chunk whose end minute falls inside the target is processed; a
  /// chunk that would overshoot is deferred to the next call. Deferring it
  /// keeps events at or before the displayed minute, and the step is stored so
  /// no random number is drawn twice or out of order.
  void advanceTo(int targetMinute) {
    if (isFinished) return;
    final target = targetMinute.clamp(_minute, matchMinutes);
    while (_minute < matchMinutes) {
      final step = _pendingStep ??= _minuteIncrement();
      if (_minute + step > target && target < matchMinutes) break;
      _pendingStep = null;
      _minute = min(matchMinutes, _minute + step);
      _playChunk();
    }
  }

  /// Brings [on] into the match for [off].
  ///
  /// Returns false when the change is illegal: no changes left, a player who
  /// is not on the pitch, a substitute who is not on the bench or cannot play
  /// (an injured man or a keeper, since keepers are never changed mid-match).
  bool substitute({
    required bool home,
    required Player off,
    required Player on,
  }) {
    if (isFinished) return false;
    final side = _sideOf(home);
    if (side.subs >= maxSubstitutions) return false;
    if (!side.onPitch.any((p) => p.id == off.id)) return false;
    if (!side.bench.any((p) => p.id == on.id)) return false;
    if (on.isInjured || on.primaryPosition == 'GK') return false;
    if (!_substitute(side, off, on, _minute)) return false;
    events.add(MatchEvent(
      type: 'sub',
      team: home ? 'home' : 'away',
      player: off.name,
      description: '${on.name} replaces ${off.name}.',
      minute: _minute,
    ));
    _refreshPowers();
    return true;
  }

  /// Plays any remaining minutes and builds the final result. Idempotent: the
  /// full-time screen can call it again without rerolling ratings.
  MatchResult finish() {
    final cached = _result;
    if (cached != null) return cached;
    if (!isFinished) advanceTo(matchMinutes);

    final homeRatings = _generateRatings(
      homeGoalkeeper,
      _home,
      goals: _homeScorers,
      assists: _homeAssists,
      goalDifference: _homeGoals - _awayGoals,
    );
    final awayRatings = _generateRatings(
      awayGoalkeeper,
      _away,
      goals: _awayScorers,
      assists: _awayAssists,
      goalDifference: _awayGoals - _homeGoals,
    );

    final result = MatchResult(
      homeTeam: 'Home',
      awayTeam: 'Away',
      homeGoals: _homeGoals,
      awayGoals: _awayGoals,
      events: events,
      homeRatings: homeRatings,
      awayRatings: awayRatings,
      homeMomentum: homeMomentum,
      awayMomentum: awayMomentum,
      fullTimeCommentary: 'Full-time: $_homeGoals - $_awayGoals',
    );
    _result = result;
    return result;
  }

  // ---------------------------------------------------------------------------
  // The engine
  // ---------------------------------------------------------------------------

  void _playChunk() {
    if (!_halfTimeAdded && _minute > 45) {
      events.add(MatchEvent(
        type: 'halfTime',
        team: 'home',
        player: '',
        description: 'Half-time: $_homeGoals - $_awayGoals.',
        minute: 45,
        homeScore: _homeGoals,
        awayScore: _awayGoals,
      ));
      _halfTimeAdded = true;
    }

    // Momentum follows the stronger side: the favourite spends more of the
    // match on the front foot, but the underdog still gets spells.
    final double momentum;
    if (_homeEdge >= 0) {
      momentum = 0.5 + _rng.nextDouble() * 0.5;
    } else {
      momentum = _rng.nextDouble() * 0.5;
    }
    homeMomentum.add(momentum * 100);
    awayMomentum.add((1 - momentum) * 100);

    final homeAttacks = _rng.nextDouble() < momentum;
    final attackSide = homeAttacks ? _home : _away;
    final defenceSide = homeAttacks ? _away : _home;
    final attackSquad = attackSide.onPitch;
    final defenceSquad = defenceSide.onPitch;
    // A side can be reduced by red cards, never emptied: at most a handful of
    // players can go, and the caller validates an XI at kick-off. Guard anyway
    // so a pathological squad cannot crash the match.
    if (attackSquad.isEmpty || defenceSquad.isEmpty) return;

    final attackRating = homeAttacks ? _homePower + 1.5 : _awayPower;
    final defenceRating = homeAttacks ? _awayPower : _homePower;
    final team = homeAttacks ? 'home' : 'away';
    final attacker = _randomPlayer(attackSquad);
    final defender = _randomPlayer(defenceSquad);

    // Expected goals rise with the attacking side's edge. The normal tempo
    // gives roughly 22 chunks, so ~0.10 per chunk lands a full match near
    // the 2-3 goal range instead of the goalless run the first draft had.
    final goalChance =
        (0.10 + (attackRating - defenceRating) * 0.0025).clamp(0.03, 0.18);
    final roll = _rng.nextDouble();

    if (roll < goalChance) {
      final assist =
          _rng.nextDouble() < 0.7 ? _randomPlayer(attackSquad) : null;
      final assistName = (assist != null && assist.name != attacker.name)
          ? assist.name
          : null;
      final assistId = assistName == null ? null : assist!.id;
      if (homeAttacks) {
        _homeGoals++;
      } else {
        _awayGoals++;
      }
      (homeAttacks ? _homeScorers : _awayScorers)
          .update(attacker.id, (v) => v + 1, ifAbsent: () => 1);
      if (assistId != null) {
        (homeAttacks ? _homeAssists : _awayAssists)
            .update(assistId, (v) => v + 1, ifAbsent: () => 1);
      }
      events.add(MatchEvent(
        type: 'goal',
        team: team,
        player: attacker.name,
        description: _goalDescription(attacker.name, assistName),
        minute: _minute,
        homeScore: _homeGoals,
        awayScore: _awayGoals,
        extraData: assistName == null ? null : {'assist': assistName},
      ));
      // One decisive moment per chunk keeps the feed readable at speed.
      return;
    }

    if (roll < goalChance + 0.16) {
      final saved = _rng.nextDouble() < 0.5;
      events.add(MatchEvent(
        type: saved ? 'save' : 'chance',
        team: team,
        player: attacker.name,
        description: saved
            ? '${attacker.name} forces a save from the goalkeeper.'
            : '${attacker.name} drags a shot wide of the post.',
        minute: _minute,
      ));
      _lateSubstitutions();
      return;
    }

    if (roll < goalChance + 0.30) {
      // Fouls are the bulk of the tackling in a match; a fraction of them
      // are late enough to be booked. The card is shown at the same minute
      // as the foul that earned it. Most cards are yellow, a small slice are
      // straight reds, and a second yellow is a dismissal too.
      final cardRoll = _rng.nextDouble();
      final defenceTeam = homeAttacks ? 'away' : 'home';
      if (cardRoll < 0.03) {
        _sendOff(
          defenceSide,
          defender,
          defenceTeam,
          straightRed: true,
          attacker: attacker,
        );
      } else if (cardRoll < 0.18) {
        final previous = defenceSide.bookings[defender.id] ?? 0;
        if (previous > 0) {
          _sendOff(
            defenceSide,
            defender,
            defenceTeam,
            secondYellow: true,
            attacker: attacker,
          );
        } else {
          defenceSide.bookings[defender.id] = 1;
          events.add(MatchEvent(
            type: 'card',
            team: defenceTeam,
            player: defender.name,
            description: 'Yellow card: ${defender.name} is booked for '
                'bringing down ${attacker.name}.',
            minute: _minute,
            extraData: {'playerId': defender.id, 'red': false},
          ));
        }
      } else {
        events.add(MatchEvent(
          type: 'foul',
          team: defenceTeam,
          player: defender.name,
          description: '${defender.name} fouls ${attacker.name}.',
          minute: _minute,
        ));
      }
      _lateSubstitutions();
      return;
    }

    if (roll < goalChance + 0.38) {
      events.add(MatchEvent(
        type: 'corner',
        team: team,
        player: attacker.name,
        description: '${attacker.name} wins a corner.',
        minute: _minute,
      ));
    } else if (roll < goalChance + 0.46) {
      events.add(MatchEvent(
        type: 'offside',
        team: team,
        player: attacker.name,
        description: '${attacker.name} is caught offside.',
        minute: _minute,
      ));
    } else if (roll < goalChance + 0.50) {
      events.add(MatchEvent(
        type: 'injury',
        team: team,
        player: attacker.name,
        description: '${attacker.name} is down and needs treatment.',
        minute: _minute,
        // The physio resolves the victim by id: a name can belong to two
        // players, and the wrong twin must not be sent to the treatment room.
        extraData: {'playerId': attacker.id},
      ));
      // A knock that stops play usually ends the player's afternoon: the
      // freshest substitute comes on right away, unless the bench is spent.
      // A manager's own side is different — the live screen pauses and lets
      // him choose (or tell the player to run it off), so the engine leaves
      // that side untouched.
      if (!attackSide.manualSubs) {
        final replacement = _benchPick(attackSide);
        if (replacement != null &&
            _substitute(attackSide, attacker, replacement, _minute)) {
          events.add(MatchEvent(
            type: 'sub',
            team: team,
            player: attacker.name,
            description: '${replacement.name} replaces ${attacker.name}, '
                'who cannot continue.',
            minute: _minute,
          ));
        }
      }
    } else {
      events.add(MatchEvent(
        type: 'commentary',
        team: team,
        player: '',
        description: _generateCommentary(_minute, _homeGoals, _awayGoals),
        minute: _minute,
      ));
    }

    _lateSubstitutions();
  }

  /// Fresh legs in the closing half-hour, for any side the assistant manages.
  ///
  /// The old feed invented a substitute from the XI purely to fill the event;
  /// this only sends on a real bench player. A user-managed side is skipped
  /// because its changes are the manager's to make.
  void _lateSubstitutions() {
    if (_minute < 55) return;
    if (!_home.manualSubs) _freshnessPass(_home, 'home', _minute);
    if (!_away.manualSubs) _freshnessPass(_away, 'away', _minute);
  }

  /// Recomputes both sides' strength from the eleven actually on the pitch.
  ///
  /// Called after any substitution or dismissal. A side missing a man takes a
  /// compounding penalty on top of the raw average, so a red card cannot
  /// paradoxically strengthen a team by removing its weakest starter.
  void _refreshPowers() {
    _homePower = _powerOf(_home, homeGoalkeeper, _homeTactic);
    _awayPower = _powerOf(_away, awayGoalkeeper, _awayTactic);
    _homeEdge = (_homePower + 1.5) - _awayPower;
  }

  double _powerOf(_MatchSide side, Player goalkeeper, Tactic? tactic) {
    final base = _calcTeamPower(side.onPitch, goalkeeper, tactic);
    final missing = (10 - side.onPitch.length).clamp(0, 10);
    if (missing == 0) return base;
    return (base * pow(0.96, missing)).clamp(20.0, 100.0).toDouble();
  }

  void _sendOff(
    _MatchSide side,
    Player player,
    String team, {
    bool straightRed = false,
    bool secondYellow = false,
    required Player attacker,
  }) {
    side.onPitch.removeWhere((p) => p.id == player.id);
    side.offAt[player.id] = _minute;
    side.sentOff.add(player);
    _refreshPowers();
    events.add(MatchEvent(
      type: 'card',
      team: team,
      player: player.name,
      description: straightRed
          ? 'Red card! ${player.name} is sent off for a dangerous challenge '
              'on ${attacker.name}.'
          : 'Second yellow card! ${player.name} is sent off after another '
              'foul on ${attacker.name}.',
      minute: _minute,
      extraData: {
        'playerId': player.id,
        'red': true,
        'secondYellow': secondYellow,
      },
    ));
  }

  int _minuteIncrement() {
    if ((_homeTactic?.tempo ?? Tempo.normal) == Tempo.fast ||
        (_awayTactic?.tempo ?? Tempo.normal) == Tempo.fast) {
      return _rng.nextInt(3) + 1;
    }
    return _rng.nextInt(5) + 2;
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
    return squad[_rng.nextInt(squad.length)];
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
    final finish = finishes[_rng.nextInt(finishes.length)];
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
  void _freshnessPass(_MatchSide side, String team, int minute) {
    if (side.subs >= maxSubstitutions || side.bench.isEmpty) return;
    if (_rng.nextDouble() >= 0.14) return;
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
      rating += _rng.nextDouble() * 1.4 - 0.7;
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
        rate(
          p,
          // A substitute can himself be withdrawn later, so his day ends at
          // the second change, not automatically at full time.
          ((side.offAt[p.id] ?? matchMinutes) -
                  (side.onAt[p.id] ?? matchMinutes))
              .clamp(0, matchMinutes),
          started: false,
        ),
    ];
  }

  String _generateCommentary(int minute, int homeGoals, int awayGoals) {
    final lines = [
      'Minute $minute - $homeGoals-$awayGoals. The match continues.',
      'At $minute minutes, still $homeGoals-$awayGoals.',
      'Minute $minute sees the teams still locked at $homeGoals-$awayGoals.',
      '$minute minutes played. Score: $homeGoals-$awayGoals.',
      'The clock ticks past $minute as the score remains $homeGoals-$awayGoals.',
    ];
    return lines[_rng.nextInt(lines.length)];
  }
}

/// One side's players during a match: the eleven that started, who is on the
/// pitch right now, who is left on the bench, and — once the whistle goes —
/// who played how long.
class _MatchSide {
  _MatchSide(List<Player> starters, List<Player> bench,
      {this.manualSubs = false})
      : squad = [...starters],
        onPitch = [...starters],
        bench = [
          // A bench that repeats an out-field starter is ignored: the same
          // body cannot sit on the bench and play.
          for (final substitute in bench)
            if (!starters.any((s) => s.id == substitute.id)) substitute,
        ];

  /// True when the manager makes this side's changes: automatic substitutions
  /// (injuries, tired legs) are skipped, because the match will pause instead.
  final bool manualSubs;

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

  /// Yellow cards per player id. A second one is a sending-off.
  final Map<int, int> bookings = {};

  /// Players dismissed, in order.
  final List<Player> sentOff = [];

  /// Changes made so far, against [maxSubstitutions].
  int subs = 0;
}
