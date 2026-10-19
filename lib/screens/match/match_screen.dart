import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/game_constants.dart';
import '../../core/constants/tactic_definitions.dart';
import '../../core/models/match.dart';
import '../../core/models/player.dart';
import '../../core/models/tactics.dart';
import '../../core/models/team.dart';
import '../../core/services/cup_service.dart';
import '../../core/services/match_simulator_service.dart';
import '../../providers/career_session_provider.dart';
import '../../providers/data_providers.dart';
import '../../providers/match_providers.dart';
import '../../providers/settings_providers.dart';
import '../../ui/ui.dart';

/// Real-time duration of the 90-minute ticker at normal speed.
///
/// A match is 90 displayed minutes; at 90 seconds one match minute lasts a
/// second, which is slow enough to read the feed without the result arriving
/// before the manager has watched it.
const int _tickerSeconds = 90;

/// Applies the Commentary and Commentary level settings to a simulated feed.
///
/// The two settings do different jobs: "Commentary off" removes the feed
/// entirely, while "Key events only" keeps the moments that change the match
/// (kick-off, goals, fouls, cards, injuries, substitutions, half-time) and
/// drops chances, corners and running text.
/// Filtering here rather than at the point of rendering means the ticker, the
/// event counter and the list can never disagree about what was shown.
List<MatchEvent> applyCommentarySettings(
  List<MatchEvent> events, {
  required bool enabled,
  required String level,
}) {
  if (!enabled) return const [];
  if (level == 'all') return events;
  // Fouls belong here: they are the physical contest the manager is watching,
  // and hiding them made the feed look frozen between goals. Kick-off and
  // half-time stay too, so the feed never opens completely blank.
  return events
      .where((e) =>
          e.isGoal ||
          e.isCard ||
          e.isInjury ||
          e.isSubstitution ||
          e.isFoul ||
          e.isKickOff ||
          e.isHalfTime)
      .toList();
}

/// The score as it stood after the events up to [minute].
///
/// The simulator pre-computes the whole match, but the live screen must only
/// show goals whose minute has already been reached. Reading the running score
/// from the revealed events (rather than the final `result.homeGoals`) is what
/// stops the full-time score appearing at kick-off.
({int home, int away}) scoreAt(List<MatchEvent> events, int minute) {
  var home = 0;
  var away = 0;
  for (final event in events) {
    if (event.minute > minute) break;
    if (event.isGoal) {
      home = event.homeScore ?? home;
      away = event.awayScore ?? away;
    }
  }
  return (home: home, away: away);
}

/// The tactics each side takes the field with.
///
/// Home and away only decide which half a club defends — the manager's
/// instructions must reach the simulation from either touchline. This used to
/// be inlined as `userIsHome ? tactic : null`, so every away match was quietly
/// played on default instructions while home matches got the full effect.
({Tactic? home, Tactic? away}) matchTacticsFor({
  required bool userIsHome,
  required Tactic userTactic,
}) =>
    (
      home: userIsHome ? userTactic : null,
      away: userIsHome ? null : userTactic,
    );

/// True when [event] must stop a live match the manager is watching.
///
/// Only his own side's injuries and dismissals interrupt: the opponent's
/// knocks are the assistant's problem, and a yellow card never stops play.
bool pausesUserMatch(MatchEvent event, {required String userTeam}) {
  if (event.team != userTeam) return false;
  if (event.isInjury) return true;
  return event.isCard && event.extraData?['red'] == true;
}

/// The full-time verdict from the user's point of view.
///
/// Reading the home score line directly made every away win display as
/// "Defeat" even though the board booked it as a win, so the verdict has to
/// be derived from the user's goals — never from [MatchResult.homeGoals].
String fullTimeOutcome({
  required MatchResult result,
  required bool userIsHome,
}) {
  final userGoals = userIsHome ? result.homeGoals : result.awayGoals;
  final oppGoals = userIsHome ? result.awayGoals : result.homeGoals;
  if (userGoals == oppGoals) return 'Draw';
  return userGoals > oppGoals ? 'Victory' : 'Defeat';
}

class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key, this.rng});

  /// Seeds the match engine. Production leaves this null and the engine seeds
  /// itself; a widget test can pass a fixed seed to replay a known match.
  final Random? rng;

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

enum _MatchPhase { pre, starting, live, halfTime, fullTime, error }

/// Validation failure with a user-presentable message.
class _MatchValidationException implements Exception {
  const _MatchValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  _MatchPhase _phase = _MatchPhase.pre;
  MatchResult? _result;
  int _currentMinute = 0;

  /// The match being played. The engine is driven minute by minute so a
  /// substitution or a red card changes the rest of the afternoon.
  MatchSimulation? _simulation;
  String _homeName = 'Home';
  String _awayName = 'Away';

  /// Milliseconds of match clock already played. Kept here rather than read
  /// from [Timer.tick] so pausing for an injury resumes where it stopped.
  int _elapsedMs = 0;

  /// The next event the pause rules have not inspected yet.
  int _checkedEvents = 0;

  /// True while a substitution sheet is open, so a pending pause cannot stack
  /// a second sheet on top of it.
  bool _subsSheetOpen = false;

  /// Which end the user's club played: the full-time verdict is computed from
  /// his side, not from the home score line.
  bool _userIsHome = true;
  Timer? _ticker;
  String? _errorMessage;

  /// The penalties verdict for a drawn cup tie, shown on the full-time screen.
  ({String text, bool advanced})? _shootout;

  /// Guards against applying the match result twice (ticker completion and
  /// Skip both funnel into [_finishMatch]).
  bool _resultApplied = false;
  final _scrollController = ScrollController();

  /// Seconds the ticker takes; adjusted by the match-speed setting.
  int get _durationSeconds => switch (ref.read(matchSpeedProvider)) {
        'slow' => 180,
        'fast' => 45,
        _ => _tickerSeconds,
      };

  /// Cadence between live updates, per speed setting.
  ///
  /// Total duration is unchanged per speed; a faster cadence reveals events
  /// in smaller steps so the feed feels responsive on 'fast' instead of
  /// popping whole minutes at once.
  int get _tickIntervalMs => switch (ref.read(matchSpeedProvider)) {
        'slow' => 900,
        'fast' => 160,
        _ => 500,
      };

  @override
  void dispose() {
    _ticker?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Kick Off
  // ---------------------------------------------------------------------------

  Future<void> _startMatch() async {
    // Double-tap / re-entry guard: only the idle "pre" phase may start a match.
    if (_phase != _MatchPhase.pre && _phase != _MatchPhase.error) return;
    debugPrint('[MATCH] Kick Off pressed');

    setState(() {
      _phase = _MatchPhase.starting;
      _errorMessage = null;
    });

    try {
      final session = ref.read(careerSessionProvider);
      final db = ref.read(playerDatabaseProvider).valueOrNull;

      debugPrint('[MATCH] Validating fixture');
      if (session == null) {
        throw const _MatchValidationException(
            'No active career. Start a career first.');
      }
      if (db == null || db.players.isEmpty) {
        throw const _MatchValidationException(
            'The player database is still loading. Try again in a moment.');
      }
      final opponent = _pickOpponent(session, db);
      if (opponent == null) {
        throw const _MatchValidationException(
            'No opponent is available for this fixture.');
      }
      if (session.team.squad.isEmpty) {
        throw const _MatchValidationException(
            'Your squad is empty. Sign or promote players before kick off.');
      }
      // The manager's stored picks (if any) shape his XI; everything else the
      // assistant fills in. Players he named on the bench are reserved there
      // and cannot be picked into the XI. The opponent is always the
      // assistant's pick.
      final benchReserved = <int>{
        for (final id in session.benchIds)
          if (id > 0) id,
      };
      final lineup = resolveMatchLineup(
        session.team.squad,
        session.tactic.formation,
        session.startXI,
        reservedIds: benchReserved,
      );
      final userSquad = lineup.outfield;
      if (userSquad.isEmpty) {
        throw const _MatchValidationException(
            'Your starting XI is incomplete. Check your squad.');
      }
      final oppSquad = _startingXi(opponent.squad, session.tactic.formation);
      if (oppSquad.isEmpty) {
        throw _MatchValidationException(
            '${opponent.name} has no available players for this match.');
      }
      final userGk = lineup.goalkeeper ??
          _pickGoalkeeper(session.team.squad) ??
          _fallbackGoalkeeper(session.team.name);
      final oppGk =
          _pickGoalkeeper(opponent.squad) ?? _fallbackGoalkeeper(opponent.name);

      // The benches: the manager's stored picks with assistant cover, and an
      // automatic bench for the opponent.
      final userBench = resolveBenchPlayers(
        session.team.squad,
        {
          userGk.id,
          for (final p in userSquad) p.id,
        },
        session.benchIds,
      );
      final oppBench = resolveBenchPlayers(
        opponent.squad,
        {
          oppGk.id,
          for (final p in oppSquad) p.id,
        },
        const [],
      );

      // Home and away come from the fixture, so an away match is actually
      // simulated (and reported) as the away side.
      final userIsHome = session.season
              .currentFixtureFor(session.team.id)
              ?.isHomeFor(session.team.id) ??
          true;

      debugPrint('[MATCH] Simulation started: '
          '${session.team.name} vs ${opponent.name} '
          '(${userIsHome ? 'home' : 'away'})');
      final tactics = matchTacticsFor(
        userIsHome: userIsHome,
        userTactic: session.tactic,
      );
      // The match is not played out here: the ticker advances it, which is
      // what lets the manager change his team mid-match. His side is marked
      // manual, so injuries pause the game instead of being auto-substituted;
      // the opponent is left to the assistant.
      final simulation = MatchSimulation(
        homeGoalkeeper: userIsHome ? userGk : oppGk,
        homeSquad: userIsHome ? userSquad : oppSquad,
        awayGoalkeeper: userIsHome ? oppGk : userGk,
        awaySquad: userIsHome ? oppSquad : userSquad,
        homeBench: userIsHome ? userBench : oppBench,
        awayBench: userIsHome ? oppBench : userBench,
        homeTactic: tactics.home,
        awayTactic: tactics.away,
        manualHome: userIsHome,
        manualAway: !userIsHome,
        rng: widget.rng,
      );

      if (!mounted) return;
      setState(() {
        _homeName = userIsHome ? session.team.name : opponent.name;
        _awayName = userIsHome ? opponent.name : session.team.name;
        _simulation = simulation;
        _userIsHome = userIsHome;
        _result = null;
        _resultApplied = false;
        _phase = _MatchPhase.live;
        _currentMinute = 0;
        _elapsedMs = 0;
        _checkedEvents = 0;
      });
      _startTicker();
    } catch (e, st) {
      debugPrint('[MATCH] Kick Off failed: $e');
      debugPrintStack(stackTrace: st, maxFrames: 12);
      if (!mounted) return;
      setState(() {
        _phase = _MatchPhase.error;
        _errorMessage = e.toString();
      });
    }
  }

  /// Drives the clock and the simulation together.
  ///
  /// The displayed minute is derived from elapsed real time, while the engine
  /// is advanced only by whole chunks. A chunk that would overshoot the clock
  /// is held for the next tick, so events never appear before their minute.
  /// The elapsed offset lives in [_elapsedMs] rather than in [Timer.tick] so
  /// pausing for an injury does not rewind or skip the match.
  void _startTicker() {
    _ticker?.cancel();
    final intervalMs = _tickIntervalMs;
    final totalMs = _durationSeconds * 1000;
    debugPrint(
        '[MATCH] Ticker started ($_durationSeconds s, ${intervalMs}ms/tick)');
    _ticker = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      final simulation = _simulation;
      if (!mounted || simulation == null || _resultApplied) {
        timer.cancel();
        return;
      }
      _elapsedMs += intervalMs;
      final minute = ((_elapsedMs / totalMs) * matchMinutes)
          .floor()
          .clamp(0, matchMinutes);
      setState(() {
        _currentMinute = minute;
        simulation.advanceTo(minute);
      });

      final pause = _pauseForUserEvent(simulation);
      if (pause != null) {
        // Stop the clock where it stands: the manager has a decision to make.
        timer.cancel();
        unawaited(_openPauseSheet(pause));
        return;
      }
      if (minute >= matchMinutes) {
        timer.cancel();
        _finishMatch();
      }
    });
  }

  /// The first new injury or sending-off suffered by the manager's side, if
  /// any, since the last time this was asked.
  _MatchPause? _pauseForUserEvent(MatchSimulation simulation) {
    final userTeam = _userIsHome ? 'home' : 'away';
    while (_checkedEvents < simulation.events.length) {
      final event = simulation.events[_checkedEvents++];
      if (!pausesUserMatch(event, userTeam: userTeam)) continue;
      return _MatchPause(event: event, redCard: !event.isInjury);
    }
    return null;
  }

  /// Stops the match and lets the manager react to his own bad news.
  ///
  /// An injury leaves the player on the pitch until the manager decides: the
  /// sheet offers a replacement or "carry on". A sending-off has already
  /// removed the player, so the same sheet is just a chance to rebalance with
  /// the people still available. Either way the clock stays paused until the
  /// sheet closes.
  Future<void> _openPauseSheet(_MatchPause pause) async {
    if (_subsSheetOpen) return;
    final simulation = _simulation;
    if (simulation == null) return;
    _subsSheetOpen = true;
    final playerId = pause.event.extraData?['playerId'];
    final injured = !pause.redCard && playerId != null
        ? simulation
            .onPitch(home: _userIsHome)
            .where((p) => p.id == playerId)
            .firstOrNull
        : null;
    final pick = await _showSubstitutions(
      headline: pause.redCard
          ? '${pause.event.player} is sent off'
          : '${pause.event.player} is injured',
      message: pause.redCard
          ? 'The match is paused. You are down to ten — make a change or '
              'carry on a man short.'
          : 'The match is paused. Bring on a substitute, or tell him to '
              'carry on.',
      forcedOff: injured,
      playOnLabel: 'Carry on',
    );
    _subsSheetOpen = false;
    if (!mounted) return;
    if (pick != null) _applySubstitution(pick);
    if (!mounted || _resultApplied) return;
    if (_currentMinute >= matchMinutes) {
      // The injury happened in the last chunk: there is no time left to
      // restart the clock for, so go straight to the whistle.
      _finishMatch();
    } else if (_phase == _MatchPhase.live) {
      _startTicker();
    }
  }

  /// Opens the substitution sheet from the live screen, pausing the clock
  /// while the manager decides.
  Future<void> _openSubstitutions() async {
    final simulation = _simulation;
    if (simulation == null || _resultApplied || _subsSheetOpen) return;
    _subsSheetOpen = true;
    _ticker?.cancel();
    final left = simulation.substitutionsLeft(home: _userIsHome);
    final pick = await _showSubstitutions(
      headline: 'Substitutions',
      message: left <= 0
          ? 'All $maxSubstitutions changes have been used.'
          : '$left of $maxSubstitutions changes left.',
      playOnLabel: 'Close',
    );
    _subsSheetOpen = false;
    if (!mounted) return;
    if (pick != null) _applySubstitution(pick);
    if (!mounted || _resultApplied) return;
    if (_currentMinute >= matchMinutes) {
      _finishMatch();
    } else if (_phase == _MatchPhase.live) {
      _startTicker();
    }
  }

  bool _applySubstitution(_Substitution pick) {
    final simulation = _simulation;
    if (simulation == null) return false;
    final ok = simulation.substitute(
      home: _userIsHome,
      off: pick.off,
      on: pick.on,
    );
    if (ok) setState(() {});
    return ok;
  }

  Future<_Substitution?> _showSubstitutions({
    required String headline,
    required String message,
    Player? forcedOff,
    required String playOnLabel,
  }) {
    final simulation = _simulation;
    if (simulation == null) return Future.value();
    final userHome = _userIsHome;
    return showModalBottomSheet<_Substitution>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _SubstitutionSheet(
        headline: headline,
        message: message,
        onPitch: simulation.onPitch(home: userHome),
        bench: [
          for (final p in simulation.bench(home: userHome))
            if (!p.isInjured && p.primaryPosition != 'GK') p,
        ],
        substitutionsLeft: simulation.substitutionsLeft(home: userHome),
        forcedOff: forcedOff,
        playOnLabel: playOnLabel,
      ),
    );
  }

  void _finishMatch() {
    final simulation = _simulation;
    if (simulation == null || _resultApplied) return;
    _resultApplied = true;
    final raw = simulation.finish();

    // Label the result with the real fixture names, in home/away order. The
    // commentary setting only filters the live feed; the timeline stays whole.
    final commentaryOn = ref.read(commentaryEnabledProvider);
    final result = MatchResult(
      homeTeam: _homeName,
      awayTeam: _awayName,
      homeGoals: raw.homeGoals,
      awayGoals: raw.awayGoals,
      events: raw.events,
      homeRatings: raw.homeRatings,
      awayRatings: raw.awayRatings,
      homeMomentum: raw.homeMomentum,
      awayMomentum: raw.awayMomentum,
      fullTimeCommentary: commentaryOn ? raw.fullTimeCommentary : '',
    );
    _result = result;
    debugPrint(
        '[MATCH] Full time: ${result.homeTeam} ${result.resultText} ${result.awayTeam}');

    final session = ref.read(careerSessionProvider);
    BoardVerdict? verdict;
    if (session != null) {
      // The shootout outcome is carved in the tie's seed, so it is knowable
      // the moment the whistle goes — before the result is applied.
      _shootout = _shootoutNoteFor(session, result);
      verdict = applyMatchResult(ref, result);
      ref.read(lastMatchResultProvider.notifier).state = result;
      ref.read(currentMatchProvider.notifier).state = result;
    }
    if (mounted) {
      setState(() => _phase = _MatchPhase.fullTime);
    }
    if (verdict != null && verdict.sacked) {
      unawaited(_announceSacking(verdict));
    }
  }

  /// Ends the career the board has just revoked and returns to the main menu.
  ///
  /// Guarded on [context.mounted] because it runs after an await (the save is
  /// erased), and the user can leave the screen while that is in flight.
  Future<void> _announceSacking(BoardVerdict verdict) async {
    await sackManager(ref);
    if (!mounted) return;
    ref.read(currentMatchProvider.notifier).state = null;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('You have been sacked'),
        content: Text(
          '${verdict.reason}\n\nThe career has ended and the save was '
          'deleted. You can start a new one from the main menu.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Back to main menu'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    context.go('/main-menu');
  }

  void _skipToEnd() {
    final simulation = _simulation;
    if (simulation == null || _resultApplied) return;
    _ticker?.cancel();
    simulation.advanceTo(matchMinutes);
    setState(() => _currentMinute = matchMinutes);
    _finishMatch();
  }

  /// Stores the half-time team talk for the matches still to come.
  ///
  /// The engine is resumable, but the half-time sheet still only sets the plan
  /// for the next match: the manager's in-match lever is the substitution
  /// sheet, which the engine does apply to the remainder.
  void _applyHalfTimeTweak(Tactic tactic) {
    final session = ref.read(careerSessionProvider);
    if (session != null) {
      session.tactic = tactic;
      notifySessionChanged(ref);
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Tactic set for your next match: ${tactic.displayName}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(careerSessionProvider);
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Match')),
        body: const EmptyState(
          icon: Icons.sports_soccer_outlined,
          title: 'No active career',
          message: 'Start a career first to play matches.',
        ),
      );
    }

    return switch (_phase) {
      _MatchPhase.pre || _MatchPhase.starting => _PreMatch(
          session: session,
          onStart: _startMatch,
          enabled: _hasSquad(),
          starting: _phase == _MatchPhase.starting,
        ),
      _MatchPhase.live || _MatchPhase.halfTime => _liveMatch(),
      _MatchPhase.fullTime => _FullTime(
          result: _result!, shootout: _shootout, userIsHome: _userIsHome),
      _MatchPhase.error => _MatchError(
          message: _errorMessage ?? 'Something went wrong.',
          onRetry: _startMatch,
        ),
    };
  }

  /// The live view: the events generated so far and the score they produced.
  Widget _liveMatch() {
    final simulation = _simulation!;
    final feed = applyCommentarySettings(
      simulation.events,
      enabled: ref.read(commentaryEnabledProvider),
      level: ref.read(commentaryLevelProvider),
    );
    return LiveMatch(
      homeTeam: _homeName,
      awayTeam: _awayName,
      homeGoals: simulation.homeGoals,
      awayGoals: simulation.awayGoals,
      minute: _currentMinute,
      events: feed,
      homeMomentum: simulation.homeMomentum,
      awayMomentum: simulation.awayMomentum,
      substitutionsLeft: simulation.substitutionsLeft(home: _userIsHome),
      onSubstitutes: _openSubstitutions,
      onHalfTime: _openHalfTime,
      onSkip: _skipToEnd,
    );
  }

  bool _hasSquad() {
    final session = ref.read(careerSessionProvider);
    return session != null && session.team.squad.isNotEmpty;
  }

  void _openHalfTime() {
    final session = ref.read(careerSessionProvider);
    if (session == null) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => _HalfTimeSheet(
        current: session.tactic,
        onApply: _applyHalfTimeTweak,
      ),
    );
  }
}

/// An injury or dismissal the manager must react to.
class _MatchPause {
  const _MatchPause({required this.event, required this.redCard});

  final MatchEvent event;
  final bool redCard;
}

/// The change a manager picked in the substitution sheet.
class _Substitution {
  const _Substitution({required this.off, required this.on});

  final Player off;
  final Player on;
}

/// Bottom sheet for a change.
///
/// Two shapes share one sheet. With [forcedOff] set — the injury pause — the
/// player coming off is fixed and each available substitute is a one-tap
/// choice. Without it the manager picks both halves of the change, which is
/// what the live "Subs" button opens. [playOnLabel] closes without a change.
class _SubstitutionSheet extends StatefulWidget {
  const _SubstitutionSheet({
    required this.headline,
    required this.message,
    required this.onPitch,
    required this.bench,
    required this.substitutionsLeft,
    required this.playOnLabel,
    this.forcedOff,
  });

  final String headline;
  final String message;
  final List<Player> onPitch;
  final List<Player> bench;
  final int substitutionsLeft;
  final String playOnLabel;
  final Player? forcedOff;

  @override
  State<_SubstitutionSheet> createState() => _SubstitutionSheetState();
}

class _SubstitutionSheetState extends State<_SubstitutionSheet> {
  Player? _off;
  Player? _on;

  @override
  void initState() {
    super.initState();
    _off = widget.forcedOff;
  }

  bool get _canSubmit =>
      widget.substitutionsLeft > 0 &&
      _off != null &&
      _on != null &&
      _off!.id != _on!.id;

  List<Player> get _benchByQuality => [...widget.bench]
    ..sort((a, b) => b.ovr.compareTo(a.ovr));

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop(_Substitution(off: _off!, on: _on!));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final forced = widget.forcedOff;
    final available = widget.substitutionsLeft > 0 && widget.bench.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Material(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.72,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.headline, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(widget.message, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 16),
                  if (!available)
                    Text(
                      widget.substitutionsLeft <= 0
                          ? 'No substitutions left.'
                          : 'No fit outfield substitutes are available.',
                      style: theme.textTheme.bodyMedium,
                    )
                  else if (forced != null) ...[
                    Text('Bring on for ${forced.name}',
                        style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final player in _benchByQuality)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(player.name),
                                subtitle: Text(
                                    '${player.primaryPosition} · ${player.ovr} OVR'),
                                trailing:
                                    const Icon(Icons.add_circle_outline),
                                onTap: () => Navigator.of(context).pop(
                                  _Substitution(off: forced, on: player),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    DropdownButtonFormField<Player>(
                      key: const ValueKey('sub-off'),
                      initialValue: _off,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Off'),
                      items: [
                        for (final p in widget.onPitch)
                          DropdownMenuItem(
                            key: ValueKey('sub-off-${p.id}'),
                            value: p,
                            child: Text(
                              '${p.name} · ${p.primaryPosition} · ${p.ovr} OVR',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (p) => setState(() => _off = p),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Player>(
                      key: const ValueKey('sub-on'),
                      initialValue: _on,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'On'),
                      items: [
                        for (final p in _benchByQuality)
                          DropdownMenuItem(
                            key: ValueKey('sub-on-${p.id}'),
                            value: p,
                            child: Text(
                              '${p.name} · ${p.primaryPosition} · ${p.ovr} OVR',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (p) => setState(() => _on = p),
                    ),
                    const SizedBox(height: 16),
                    PrimaryButton(
                      key: const ValueKey('sub-confirm'),
                      label: 'Make substitution',
                      icon: Icons.swap_horiz,
                      onPressed: _canSubmit ? _submit : null,
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(widget.playOnLabel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreMatch extends ConsumerWidget {
  const _PreMatch({
    required this.session,
    required this.onStart,
    required this.enabled,
    required this.starting,
  });

  final CareerSession session;
  final VoidCallback onStart;
  final bool enabled;
  final bool starting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final db = ref.watch(playerDatabaseProvider).valueOrNull;
    final opponent = db == null ? null : _pickOpponent(session, db);
    final duration = switch (ref.read(matchSpeedProvider)) {
      'slow' => 'three minutes',
      'fast' => '45 seconds',
      _ => '90 seconds',
    };
    final lineup = resolveMatchLineup(
      session.team.squad,
      session.tactic.formation,
      session.startXI,
      reservedIds: {
        for (final id in session.benchIds)
          if (id > 0) id,
      },
    );
    final bench = resolveBenchPlayers(
      session.team.squad,
      {
        if (lineup.goalkeeper != null) lineup.goalkeeper!.id,
        for (final p in lineup.outfield) p.id,
      },
      session.benchIds,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Match')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.stadium_outlined,
                size: 56, color: AppTheme.pitchGreen),
            const SizedBox(height: 16),
            Text('Ready for kick-off?', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Matchday ${session.season.matchdayNumber}'
              '${opponent != null ? ' · vs ${opponent.name}' : ''}',
              style: theme.textTheme.bodyMedium,
            ),
            if (_cupTieLabel(session) case final cupLabel?) ...[
              const SizedBox(height: 4),
              Text(
                cupLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.pitchGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text('The match plays out in about $duration.',
                style: theme.textTheme.bodySmall),
            if (bench.isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Substitutes: ${bench.map((p) => p.name).join(', ')}',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (starting) ...[
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: AppTheme.pitchGreen),
              ),
            ] else
              PrimaryButton(
                label: 'Kick Off',
                icon: Icons.play_arrow,
                onPressed: enabled ? onStart : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _MatchError extends StatelessWidget {
  const _MatchError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Match')),
      body: ErrorState(
        message: "Match couldn't start.\n$message",
        onRetry: onRetry,
      ),
    );
  }
}

class LiveMatch extends StatelessWidget {
  const LiveMatch({
    super.key,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeGoals,
    required this.awayGoals,
    required this.minute,
    required this.events,
    required this.homeMomentum,
    required this.awayMomentum,
    required this.substitutionsLeft,
    required this.onSubstitutes,
    required this.onHalfTime,
    required this.onSkip,
  });

  final String homeTeam;
  final String awayTeam;

  /// The score at [minute] — not the final score, which is what used to be
  /// printed from kick-off.
  final int homeGoals;
  final int awayGoals;
  final int minute;
  final List<MatchEvent> events;
  final List<double> homeMomentum;
  final List<double> awayMomentum;

  /// How many changes the manager has left this match.
  final int substitutionsLeft;
  final VoidCallback onSubstitutes;
  final VoidCallback onHalfTime;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live'),
        actions: [
          TextButton.icon(
            onPressed: onSubstitutes,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: Text('Subs $substitutionsLeft'),
          ),
          if (minute < matchMinutes)
            TextButton(
              onPressed: onSkip,
              child: const Text('Skip'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Scoreboard
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      homeTeam,
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        '$homeGoals - $awayGoals',
                        key: ValueKey('$homeGoals-$awayGoals'),
                        style: theme.textTheme.displaySmall
                            ?.copyWith(fontSize: 36),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      awayTeam,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text("$minute'", style: theme.textTheme.bodySmall),
            ),
            // Momentum bars
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _MomentumBars(home: homeMomentum, away: awayMomentum),
            ),
            const Divider(height: 24),
            // Event feed
            Expanded(
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final event = events[events.length - 1 - index];
                  return _EventTile(event: event);
                },
              ),
            ),
            if (minute >= 45 && minute < 47)
              Padding(
                padding: const EdgeInsets.all(12),
                child: PrimaryButton(
                  label: 'Half-time team talk',
                  icon: Icons.sports,
                  onPressed: onHalfTime,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MomentumBars extends StatelessWidget {
  const _MomentumBars({required this.home, required this.away});

  final List<double> home;
  final List<double> away;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Expanded(
            child: _MomentumSeries(values: home, color: AppTheme.pitchGreen),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _MomentumSeries(
              values: away,
              color: const Color(0xFFEF5350),
              reverse: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentumSeries extends StatelessWidget {
  const _MomentumSeries({
    required this.values,
    required this.color,
    this.reverse = false,
  });

  final List<double> values;
  final Color color;
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MomentumPainter(values: values, color: color, reverse: reverse),
      size: Size.infinite,
    );
  }
}

class _MomentumPainter extends CustomPainter {
  _MomentumPainter({
    required this.values,
    required this.color,
    required this.reverse,
  });

  final List<double> values;
  final Color color;
  final bool reverse;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final y = size.height - (values[i].clamp(0, 100) / 100) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    if (reverse) {
      // Mirror horizontally for the away side.
      canvas.save();
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
      canvas.drawPath(path, paint);
      canvas.restore();
    } else {
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_MomentumPainter oldDelegate) =>
      oldDelegate.values.length != values.length;
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final MatchEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = switch (event.type) {
      'goal' => (Icons.sports_soccer, const Color(0xFF00C853)),
      'card' => (Icons.style, const Color(0xFFFFB74D)),
      'injury' => (Icons.healing, const Color(0xFFEF5350)),
      'chance' || 'save' => (Icons.bolt, const Color(0xFF40C4FF)),
      'foul' => (Icons.pan_tool_alt_outlined, const Color(0xFFFF8A65)),
      'corner' => (Icons.flag_outlined, const Color(0xFF9CCC65)),
      'offside' => (Icons.outlined_flag, const Color(0xFFB0BEC5)),
      'sub' => (Icons.swap_horiz, const Color(0xFF80DEEA)),
      'kickoff' || 'halfTime' => (Icons.timer_outlined, AppTheme.pitchGreen),
      _ => (
          Icons.chat_bubble_outline,
          theme.colorScheme.onSurface.withValues(alpha: 0.3)
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text("${event.minute}'", style: theme.textTheme.labelSmall),
          ),
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              event.description.isEmpty ? event.type : event.description,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: event.isGoal ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HalfTimeSheet extends StatelessWidget {
  const _HalfTimeSheet({required this.current, required this.onApply});

  final Tactic current;
  final void Function(Tactic) onApply;

  @override
  Widget build(BuildContext context) {
    Tactic draft = current;
    return StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Half-time team talk',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Saved for your next match. Changes to the side on the pitch '
              'are made with the Subs button.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _dropdown<PlayingStyle>(
              context,
              'Playing style',
              PlayingStyle.values,
              draft.playingStyle,
              (v) => setState(() => draft = draft.copyWith(playingStyle: v)),
            ),
            const SizedBox(height: 12),
            _dropdown<Tempo>(
              context,
              'Tempo',
              Tempo.values,
              draft.tempo,
              (v) => setState(() => draft = draft.copyWith(tempo: v)),
            ),
            const SizedBox(height: 12),
            _dropdown<PressingIntensity>(
              context,
              'Pressing',
              PressingIntensity.values,
              draft.pressing,
              (v) => setState(() => draft = draft.copyWith(pressing: v)),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Send them back out',
              onPressed: () => onApply(draft),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown<T>(
    BuildContext context,
    String label,
    List<T> values,
    T current,
    void Function(T?) onChanged,
  ) {
    return DropdownButtonFormField<T>(
      initialValue: current,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final v in values)
          DropdownMenuItem(value: v, child: Text(_label(v.toString()))),
      ],
      onChanged: onChanged,
    );
  }

  String _label(String enumSource) {
    final name = enumSource.split('.').last;
    return name.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]}').trim();
  }
}

class _FullTime extends StatelessWidget {
  const _FullTime({required this.result, this.shootout, this.userIsHome = true});

  final MatchResult result;

  /// The penalties verdict for a drawn cup tie, when the match was one.
  final ({String text, bool advanced})? shootout;

  /// True when the user's club was the home side. The verdict is read from
  /// the user's goals, so an away win reads "Victory", not "Defeat".
  final bool userIsHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcome = fullTimeOutcome(result: result, userIsHome: userIsHome);

    return Scaffold(
      appBar: AppBar(title: const Text('Full Time')),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text(outcome.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 14,
                    letterSpacing: 2,
                    color: AppTheme.pitchGreen,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('${result.homeTeam} ${result.resultText} ${result.awayTeam}',
                style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(result.fullTimeCommentary, style: theme.textTheme.bodySmall),
            if (shootout != null) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (shootout!.advanced
                          ? AppTheme.pitchGreen
                          : const Color(0xFFEF5350))
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  shootout!.text,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: shootout!.advanced
                        ? AppTheme.pitchGreen
                        : const Color(0xFFEF5350),
                  ),
                ),
              ),
            ],
            const Divider(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child:
                    Text('Player ratings', style: theme.textTheme.titleMedium),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: result.playerRatings.length,
                itemBuilder: (context, index) {
                  final r = result.playerRatings[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: PositionChip(position: r.position),
                    title:
                        Text(r.playerName, style: theme.textTheme.bodyMedium),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (r.goals > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(Icons.sports_soccer,
                                size: 14, color: AppTheme.pitchGreen),
                          ),
                        Text(
                          r.rating.toStringAsFixed(1),
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: 'Back to Home',
                  onPressed: () => context.go('/home'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- helpers ---

/// The club the user is actually due to play this matchday.
///
/// The fixture is the only source of truth. The rival fallback is a safety net
/// for a save whose club is missing from the database, not a way to pick an
/// opponent.
Team? _pickOpponent(CareerSession session, PlayerDatabase db) {
  final opponentId = session.season
      .currentFixtureFor(session.team.id)
      ?.opponentOf(session.team.id);
  if (opponentId != null) {
    final match = db.teams.where((t) => t.id == opponentId).firstOrNull;
    if (match != null) return match;
  }
  final rivals = db.teams
      .where(
          (t) => t.leagueId == session.team.leagueId && t.id != session.team.id)
      .toList();
  return rivals.isEmpty ? null : rivals.first;
}

/// 'Cup · Semi-finals' when the club is due a knockout tie this matchday,
/// else null: league fixtures need no competition tag.
String? _cupTieLabel(CareerSession session) {
  final season = session.season;
  final fixture =
      season.userFixtureForRound(season.currentMatchday, session.team.id);
  final cup = season.cupAt(season.currentMatchday);
  if (fixture == null || cup == null || fixture.competition == 'league') {
    return null;
  }
  final cupRound = cup.anchors.indexOf(season.currentMatchday);
  return '${cup.name} · ${CupService.roundNameOf(season, cupRound, cup: cup)}';
}

/// The penalties verdict for the tie the manager just played, or null when
/// the match was a league game or was settled in normal time.
({String text, bool advanced})? _shootoutNoteFor(
  CareerSession session,
  MatchResult result,
) {
  final fixture = session.season.currentFixtureFor(session.team.id);
  if (fixture == null) return null;
  return CupService.shootoutNote(
    season: session.season,
    tie: fixture,
    teamId: session.team.id,
    homeGoals: result.homeGoals,
    awayGoals: result.awayGoals,
  );
}

/// The out-field players that start, picked for the manager's chosen
/// [Formation] so the shape set on the tactics screen is the shape that
/// actually takes the field.
List<Player> _startingXi(List<Player> squad, Formation formation) =>
    startingOutfield(squad, formation);

Player? _pickGoalkeeper(List<Player> squad) {
  final keepers = squad.where((p) => p.primaryPosition == 'GK').toList();
  // A fit keeper takes the gloves; an injured one only plays when there is
  // nobody else at all (the synthetic fallback is strictly worse).
  for (final keeper in keepers) {
    if (!keeper.isInjured) return keeper;
  }
  return keepers.isEmpty ? null : keepers.first;
}

/// Synthetic keeper used only when a squad has no goalkeeper at all, so a
/// match can still be simulated instead of crashing on a null keeper.
Player _fallbackGoalkeeper(String teamName) {
  return Player(
    name: '$teamName Keeper',
    id: -(teamName.hashCode + 999),
    nationality: 'Unknown',
    age: 27,
    ovr: 68,
    pac: 60,
    sho: 40,
    pas: 55,
    dri: 55,
    def: 60,
    phy: 65,
    acceleration: 58,
    sprintSpeed: 58,
    positioning: 66,
    finishing: 40,
    shotPower: 45,
    longShots: 35,
    volleys: 35,
    penalties: 45,
    vision: 50,
    crossing: 35,
    freeKickAccuracy: 30,
    shortPassing: 55,
    longPassing: 52,
    curve: 40,
    agility: 62,
    balance: 60,
    reactions: 68,
    ballControl: 52,
    composure: 62,
    interceptions: 40,
    headingAccuracy: 55,
    defAwareness: 60,
    standingTackle: 42,
    slidingTackle: 38,
    jumping: 66,
    staminaStat: 62,
    strength: 64,
    aggression: 50,
    gkDiving: 68,
    gkHandling: 66,
    gkKicking: 60,
    gkPositioning: 67,
    gkReflexes: 69,
    primaryPosition: 'GK',
    alternativePositions: const [],
    preferredFoot: 'Right',
    weakFootQuality: 2,
    skillMoves: 1,
    height: '190cm',
    weight: '85kg',
    playTraits: const [],
    currentTeam: teamName,
    currentLeague: 'league',
  );
}
