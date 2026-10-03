import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/game_constants.dart';
import '../../core/constants/tactic_definitions.dart';
import '../../core/models/match.dart';
import '../../core/models/player.dart';
import '../../core/models/tactics.dart';
import '../../core/models/team.dart';
import '../../core/services/match_simulator_service.dart';
import '../../providers/career_session_provider.dart';
import '../../providers/data_providers.dart';
import '../../providers/match_providers.dart';
import '../../providers/settings_providers.dart';
import '../../ui/ui.dart';

/// Real-time duration of the 90-minute ticker at normal speed.
const int _tickerSeconds = 60;

class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key});

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
  final _sim = MatchSimulatorService();
  _MatchPhase _phase = _MatchPhase.pre;
  MatchResult? _result;
  int _currentMinute = 0;
  Timer? _ticker;
  int _eventsShown = 0;
  String? _errorMessage;

  /// Guards against applying the match result twice (ticker completion and
  /// Skip both funnel into [_finishMatch]).
  bool _resultApplied = false;
  final _scrollController = ScrollController();

  /// Seconds the ticker takes; adjusted by the match-speed setting.
  int get _durationSeconds => switch (ref.read(matchSpeedProvider)) {
        'slow' => 90,
        'fast' => 30,
        _ => _tickerSeconds,
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
      final userSquad =
          _startingXi(session.team.squad, session.tactic.formation);
      if (userSquad.isEmpty) {
        throw const _MatchValidationException(
            'Your starting XI is incomplete. Check your squad.');
      }
      final oppSquad = _startingXi(opponent.squad, session.tactic.formation);
      if (oppSquad.isEmpty) {
        throw _MatchValidationException(
            '${opponent.name} has no available players for this match.');
      }
      final userGk = _pickGoalkeeper(session.team.squad) ??
          _fallbackGoalkeeper(session.team.name);
      final oppGk =
          _pickGoalkeeper(opponent.squad) ?? _fallbackGoalkeeper(opponent.name);

      // Home and away come from the fixture, so an away match is actually
      // simulated (and reported) as the away side.
      final userIsHome = session.season
              .currentFixtureFor(session.team.id)
              ?.isHomeFor(session.team.id) ??
          true;

      debugPrint('[MATCH] Simulation started: '
          '${session.team.name} vs ${opponent.name} '
          '(${userIsHome ? 'home' : 'away'})');
      final watch = Stopwatch()..start();
      final result = _sim.simulateMatch(
        homeGoalkeeper: userIsHome ? userGk : oppGk,
        homeSquad: userIsHome ? userSquad : oppSquad,
        awayGoalkeeper: userIsHome ? oppGk : userGk,
        awaySquad: userIsHome ? oppSquad : userSquad,
        homeTactic: userIsHome ? session.tactic : null,
      );
      watch.stop();
      debugPrint(
          '[MATCH] Simulation finished in ${watch.elapsedMilliseconds}ms '
          '(${result.events.length} events, ${result.homeGoals}-${result.awayGoals})');

      // Label the result with the real fixture names, in home/away order.
      final labeled = MatchResult(
        homeTeam: userIsHome ? session.team.name : opponent.name,
        awayTeam: userIsHome ? opponent.name : session.team.name,
        homeGoals: result.homeGoals,
        awayGoals: result.awayGoals,
        events: result.events,
        playerRatings: result.playerRatings,
        homeMomentum: result.homeMomentum,
        awayMomentum: result.awayMomentum,
        fullTimeCommentary: result.fullTimeCommentary,
      );

      if (!mounted) return;
      setState(() {
        _result = labeled;
        _resultApplied = false;
        _phase = _MatchPhase.live;
        _currentMinute = 0;
        _eventsShown = 0;
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

  /// Replays the pre-computed result as a live ticker.
  ///
  /// The displayed minute is driven purely by elapsed ticks
  /// (`tick / totalTicks * matchMinutes`), so it is guaranteed to reach
  /// [matchMinutes] and terminate. (The previous formula derived the minute
  /// from the last commentary event, which is always < 90 — the match could
  /// never finish and the timer never cancelled.)
  void _startTicker() {
    _ticker?.cancel();
    final totalTicks = _durationSeconds * 2; // ticks are 500ms apart
    debugPrint('[MATCH] Ticker started ($_durationSeconds}s)');
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted || _result == null) {
        timer.cancel();
        return;
      }
      final minute = ((timer.tick / totalTicks) * matchMinutes)
          .floor()
          .clamp(0, matchMinutes);
      setState(() {
        _currentMinute = minute;
        while (_eventsShown < _result!.events.length &&
            _result!.events[_eventsShown].minute <= minute) {
          _eventsShown++;
        }
      });
      if (minute >= matchMinutes) {
        timer.cancel();
        _finishMatch();
      }
    });
  }

  void _finishMatch() {
    if (_result == null || _resultApplied) return;
    _resultApplied = true;
    debugPrint(
        '[MATCH] Full time: ${_result!.homeTeam} ${_result!.resultText} ${_result!.awayTeam}');

    final session = ref.read(careerSessionProvider);
    if (session != null) {
      applyMatchResult(ref, _result!);
      ref.read(lastMatchResultProvider.notifier).state = _result;
      ref.read(currentMatchProvider.notifier).state = _result;
    }
    if (mounted) {
      setState(() => _phase = _MatchPhase.fullTime);
    }
  }

  void _skipToEnd() {
    if (_result == null || _resultApplied) return;
    _ticker?.cancel();
    setState(() => _currentMinute = matchMinutes);
    _finishMatch();
  }

  void _applyHalfTimeTweak(Tactic tactic) {
    final session = ref.read(careerSessionProvider);
    if (session != null) {
      session.tactic = tactic;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Tactics updated: ${tactic.displayName}')),
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
      _MatchPhase.live || _MatchPhase.halfTime => _LiveMatch(
          result: _result!,
          minute: _currentMinute,
          events: _result!.events.take(_eventsShown).toList(),
          homeMomentum: _momentumAt(_result!.homeMomentum, _currentMinute),
          awayMomentum: _momentumAt(_result!.awayMomentum, _currentMinute),
          onHalfTime: _openHalfTime,
          onSkip: _skipToEnd,
        ),
      _MatchPhase.fullTime => _FullTime(result: _result!),
      _MatchPhase.error => _MatchError(
          message: _errorMessage ?? 'Something went wrong.',
          onRetry: _startMatch,
        ),
    };
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

  List<double> _momentumAt(List<double> series, int minute) {
    if (series.isEmpty) return [];
    final upTo = ((minute / matchMinutes) * series.length)
        .floor()
        .clamp(1, series.length);
    return series.sublist(0, upTo);
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
            const SizedBox(height: 4),
            Text('The match plays out in about a minute.',
                style: theme.textTheme.bodySmall),
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

class _LiveMatch extends StatelessWidget {
  const _LiveMatch({
    required this.result,
    required this.minute,
    required this.events,
    required this.homeMomentum,
    required this.awayMomentum,
    required this.onHalfTime,
    required this.onSkip,
  });

  final MatchResult result;
  final int minute;
  final List<MatchEvent> events;
  final List<double> homeMomentum;
  final List<double> awayMomentum;
  final VoidCallback onHalfTime;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live'),
        actions: [
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
                      result.homeTeam,
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
                        '${result.homeGoals} - ${result.awayGoals}',
                        key:
                            ValueKey('${result.homeGoals}-${result.awayGoals}'),
                        style: theme.textTheme.displaySmall
                            ?.copyWith(fontSize: 36),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      result.awayTeam,
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
      'chance' => (Icons.bolt, const Color(0xFF40C4FF)),
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
              event.isGoal
                  ? 'GOAL! ${event.player}'
                  : (event.description.isEmpty
                      ? event.type
                      : event.description),
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
  const _FullTime({required this.result});

  final MatchResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcome = result.homeGoals == result.awayGoals
        ? 'Draw'
        : result.homeGoals > result.awayGoals
            ? 'Victory'
            : 'Defeat';

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
                          '${r.rating}',
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

/// The out-field players that start, picked for the manager's chosen
/// [Formation] so the shape set on the tactics screen is the shape that
/// actually takes the field.
List<Player> _startingXi(List<Player> squad, Formation formation) =>
    startingOutfield(squad, formation);

Player? _pickGoalkeeper(List<Player> squad) {
  for (final p in squad) {
    if (p.primaryPosition == 'GK') return p;
  }
  return null;
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
