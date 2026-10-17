import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/player.dart';
import '../../core/models/team.dart';
import '../../providers/career_session_provider.dart';
import '../../providers/data_providers.dart';
import '../../ui/ui.dart';

/// Home — the single screen a manager opens between matches.
///
/// Everything a manager needs to decide "what next" fits one scroll: the next
/// fixture with its Play button, the season numbers, the club's finances, the
/// pressure gauges, and the three destinations that matter. The mini league
/// table and the standalone form guide used to live here; both duplicated a
/// screen that already exists (League table, and the form pills now folded into
/// the fixture card), so they were dropped rather than re-laid out.
class CareerDashboardScreen extends ConsumerWidget {
  const CareerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(careerSessionProvider);
    if (session == null) return const _NoCareerBody();

    final team = session.team;
    final dbAsync = ref.watch(playerDatabaseProvider);
    final db = dbAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClubCrest(team: team, size: 26),
            const SizedBox(width: 10),
            Flexible(
              child: Text(team.name, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'League table',
            icon: const Icon(Icons.table_chart_outlined),
            onPressed: () => context.push('/league-table'),
          ),
          IconButton(
            tooltip: 'Main menu',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => context.push('/main-menu'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _NextMatchHero(
              session: session,
              opponent: _opponentTeam(session, db),
              // Distinguishing "still parsing the CSV" from "no opponent" stops
              // the hero from claiming a fixture is TBC while it is only loading.
              databaseLoading: dbAsync.isLoading,
            ),
            const SizedBox(height: 12),
            _StatGrid(session: session),
            const SizedBox(height: 12),
            _PressureCard(session: session),
            const SizedBox(height: 12),
            _QuickActions(),
          ],
        ),
      ),
    );
  }
}

class _NoCareerBody extends StatelessWidget {
  const _NoCareerBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: EmptyState(
        icon: Icons.sports_soccer_outlined,
        title: 'No active career',
        message: 'Start a new career to manage a club.',
        action: PrimaryButton(
          label: 'New Career',
          icon: Icons.add,
          onPressed: () => context.go('/new-career'),
        ),
      ),
    );
  }
}

/// Hero: the next fixture, the form pills and the Play button in one card.
class _NextMatchHero extends ConsumerWidget {
  const _NextMatchHero({
    required this.session,
    required this.opponent,
    this.databaseLoading = false,
  });

  final CareerSession session;
  final Team? opponent;

  /// True while the player database is still being parsed.
  final bool databaseLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final season = session.season;
    final progress = season.totalMatchdays == 0
        ? 0.0
        : (season.currentMatchday / season.totalMatchdays).clamp(0.0, 1.0);
    // The fixture decides everything: the home/away badge, whether the club
    // can play at all, and whether the round is a bye.
    final fixture = season.currentFixtureFor(session.team.id);
    final hasFixture = fixture != null;
    final isBye =
        !hasFixture && !season.isPostSeason && season.rounds.isNotEmpty;
    final isComplete = season.isPostSeason;
    // A league can end up with too few clubs that cleared the squad filter to
    // build any schedule at all. Say so rather than showing a dead button.
    final noSchedule = season.rounds.isEmpty;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Tapping the fixture is how a manager inspects the opposition, so the
        // whole card is the target rather than a small chevron.
        onTap: opponent == null ? null : () => _openPreview(context, opponent!),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      prettifyLeagueId(session.team.leagueId),
                      style: theme.textTheme.labelSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (season.totalMatchdays > 0)
                    Text(
                      'Matchday ${season.currentMatchday + 1}/${season.totalMatchdays}',
                      style: theme.textTheme.labelSmall,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor:
                      theme.colorScheme.onSurface.withValues(alpha: 0.08),
                  valueColor: const AlwaysStoppedAnimation(AppTheme.pitchGreen),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _side(
                      context,
                      team: session.team,
                      align: CrossAxisAlignment.start,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      hasFixture && !fixture.isHomeFor(session.team.id)
                          ? 'at'
                          : 'vs',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: opponent == null
                        ? _placeholder(
                            context,
                            align: CrossAxisAlignment.end,
                            loading: databaseLoading,
                          )
                        : _side(
                            context,
                            team: opponent!,
                            align: CrossAxisAlignment.end,
                          ),
                  ),
                ],
              ),
              if (session.userResults.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Form', style: theme.textTheme.labelSmall),
                    const SizedBox(width: 8),
                    FormGuide(
                      results: session.userResults,
                      team: session.team,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _primaryAction(
                          context, ref, hasFixture, isBye, isComplete),
                      icon: Icon(_primaryIcon(isBye, isComplete)),
                      label: Text(
                        _primaryLabel(
                            hasFixture, isBye, isComplete, noSchedule),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              if (noSchedule) ...[
                const SizedBox(height: 8),
                Text(
                  'No schedule could be built: no other club in this league has '
                  'a full squad. Pick a club from a larger league.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              if (isBye) ...[
                const SizedBox(height: 8),
                Text(
                  'No fixture this matchday - the league has an odd number of '
                  'clubs. Everyone else still plays.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              if (season.isWinterBreak && !isComplete) ...[
                const SizedBox(height: 8),
                Text(
                  'Winter break - the league resumes at matchday '
                  '${season.matchdayNumber}.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _primaryLabel(
    bool hasFixture,
    bool isBye,
    bool isComplete,
    bool noSchedule,
  ) {
    if (noSchedule) return 'No fixtures';
    if (isComplete) return 'Start next season';
    if (isBye) return 'Skip matchday';
    if (session.season.isWinterBreak) return 'Resume season';
    return 'Play match';
  }

  IconData _primaryIcon(bool isBye, bool isComplete) {
    if (isComplete) return Icons.skip_next;
    if (isBye) return Icons.fast_forward;
    return Icons.play_arrow;
  }

  VoidCallback? _primaryAction(
    BuildContext context,
    WidgetRef ref,
    bool hasFixture,
    bool isBye,
    bool isComplete,
  ) {
    if (isComplete) return () => _rollIntoNextSeason(context, ref);
    if (isBye) return () => advancePastBye(ref);
    if (session.season.isWinterBreak) return () => resumeFromWinterBreak(ref);
    if (hasFixture) return () => context.go('/match');
    return null;
  }

  /// Closes the season, applies any movement, and reports the outcome before
  /// the new season begins.
  Future<void> _rollIntoNextSeason(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final outcome = rollIntoNextSeason(ref);
    if (outcome == null) return;
    final movement = switch (outcome.movement) {
      'promoted' => 'Promoted!',
      'relegated' => 'Relegated.',
      _ => 'Staying put.',
    };
    messenger.showSnackBar(SnackBar(
      content: Text(
        '${outcome.year}/${(outcome.year + 1) % 100}: finished '
        '${ordinalSuffix(outcome.position)} on ${outcome.points} points. '
        '$movement',
      ),
    ));
  }

  static String ordinalSuffix(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    return switch (n % 10) {
      1 => '${n}st',
      2 => '${n}nd',
      3 => '${n}rd',
      _ => '${n}th',
    };
  }

  Widget _side(
    BuildContext context, {
    required Team team,
    required CrossAxisAlignment align,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: align,
      children: [
        ClubCrest(team: team, size: 40),
        const SizedBox(height: 8),
        Text(
          team.name,
          style: theme.textTheme.titleMedium?.copyWith(fontSize: 14),
          textAlign:
              align == CrossAxisAlignment.end ? TextAlign.end : TextAlign.start,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        Text('${_avgOvr(team)} OVR', style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _placeholder(BuildContext context,
      {required CrossAxisAlignment align, required bool loading}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(11),
          ),
          child: loading
              ? Padding(
                  padding: const EdgeInsets.all(11),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onSurface,
                  ),
                )
              : Icon(Icons.help_outline,
                  size: 20, color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: 8),
        Text(loading ? 'Loading' : 'Opponent',
            style: theme.textTheme.titleMedium?.copyWith(fontSize: 14)),
        Text(loading ? 'club data…' : 'to be confirmed',
            style: theme.textTheme.bodySmall),
      ],
    );
  }

  /// Opens the opponent's detail sheet: the fixture card previously showed an
  /// opponent's name and nothing else, with no way to see who you are facing.
  void _openPreview(BuildContext context, Team opponent) {
    final season = session.season;
    final fixture = season.currentFixtureFor(session.team.id);
    showModalBottomSheet<void>(
      context: context,
      // A bottom sheet defaults to at most half the screen height, which the
      // key-player list overflows on a short phone. Taking the full height and
      // scrolling inside keeps every row reachable.
      isScrollControlled: true,
      builder: (sheetContext) => _FixturePreviewSheet(
        matchday: season.currentMatchday + 1,
        totalMatchdays: season.totalMatchdays,
        isHome: fixture?.isHomeFor(session.team.id) ?? true,
        ourStrength: _avgOvr(session.team),
        ourShortName: session.team.shortName,
        opponent: opponent,
        onViewTable: () {
          Navigator.pop(sheetContext);
          context.push('/league-table');
        },
      ),
    );
  }
}

/// Bottom sheet describing the next opponent.
class _FixturePreviewSheet extends StatelessWidget {
  const _FixturePreviewSheet({
    required this.matchday,
    required this.totalMatchdays,
    required this.isHome,
    required this.ourStrength,
    required this.ourShortName,
    required this.opponent,
    required this.onViewTable,
  });

  final int matchday;
  final int totalMatchdays;
  final bool isHome;
  final int ourStrength;
  final String ourShortName;
  final Team opponent;
  final VoidCallback onViewTable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final theirs = _avgOvr(opponent);
    // Positive means the fixture is winnable on paper.
    final edge = ourStrength - theirs;
    final verdict = edge >= 8
        ? 'Favourable on paper'
        : edge <= -8
            ? 'A tough fixture'
            : 'Roughly even';

    // One key player per line of the pitch, strongest first.
    final byPosition = <String, Player>{};
    for (final p in opponent.squad) {
      final key = p.primaryPosition;
      final current = byPosition[key];
      if (current == null || p.ovr > current.ovr) byPosition[key] = p;
    }
    final keyPlayers = byPosition.values.toList()
      ..sort((a, b) => b.ovr.compareTo(a.ovr));

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClubCrest(team: opponent, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(opponent.name,
                            style: theme.textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis),
                        Text(
                          'Matchday $matchday of $totalMatchdays · '
                          '${isHome ? 'Home' : 'Away'} · $verdict',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: MeterBar(
                        label: opponent.shortName, value: theirs.toDouble()),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MeterBar(
                        label: ourShortName, value: ourStrength.toDouble()),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Key players', style: theme.textTheme.labelSmall),
              const SizedBox(height: 8),
              if (keyPlayers.isEmpty)
                Text('Squad data unavailable.',
                    style: theme.textTheme.bodySmall)
              else
                for (final p in keyPlayers.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        PositionChip(position: p.primaryPosition),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(p.name,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium),
                        ),
                        OvrBadge(ovr: p.ovr, size: 28),
                      ],
                    ),
                  ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onViewTable,
                  icon: const Icon(Icons.table_chart_outlined, size: 18),
                  label: const Text('League table'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One-line season strip: position, points, record and budget.
///
/// Four separate cards were too narrow for their labels on a 360 dp phone —
/// they ellipsized into "PO…", "RE…" and "BU…", and the record was cut to
/// "15-…". A single strip with hairline dividers keeps all four numbers on one
/// line and lets each value shrink rather than lose characters.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.session});

  final CareerSession session;

  @override
  Widget build(BuildContext context) {
    final team = session.team;
    final hasPlayed = team.matchesPlayed > 0;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: IntrinsicHeight(
          child: Row(
            children: [
              _StatCell(
                label: 'POS',
                value: hasPlayed ? '${team.leaguePosition}' : '—',
                icon: Icons.leaderboard_outlined,
                color: AppTheme.pitchGreen,
                onTap: () => context.push('/league-table'),
              ),
              const _StripDivider(),
              _StatCell(
                label: 'PTS',
                value: '${team.points}',
                icon: Icons.stars_outlined,
                color: const Color(0xFF40C4FF),
              ),
              const _StripDivider(),
              _StatCell(
                label: 'W-D-L',
                value: hasPlayed
                    ? '${team.wins}-${team.draws}-${team.losses}'
                    : '—',
                icon: Icons.timeline_outlined,
                color: const Color(0xFFFFB74D),
              ),
              const _StripDivider(),
              _StatCell(
                label: 'BUDGET',
                value: _formatMoney(team.transferBudget),
                icon: Icons.savings_outlined,
                color: const Color(0xFF7CDD72),
                onTap: () => context.push('/transfers'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StripDivider extends StatelessWidget {
  const _StripDivider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(vertical: 10),
        color: Theme.of(context).dividerTheme.color ?? Colors.white12,
      );
}

/// One column of the season strip.
class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 13, color: color),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PressureCard extends StatelessWidget {
  const _PressureCard({required this.session});

  final CareerSession session;

  /// Where the board expects the club to finish, as a league position.
  ///
  /// Halfway up a league of N clubs; never better than 1st, never worse than
  /// the last place a club could occupy.
  static int boardTarget(int clubCount) {
    if (clubCount <= 1) return 1;
    return (clubCount / 2).ceil().clamp(1, clubCount);
  }

  /// The objective line, including where the club currently sits against it.
  String _boardObjectiveText() {
    final team = session.team;
    final clubCount = session.season.records.length;
    if (clubCount == 0) return 'Board target: not set yet.';
    final target = boardTarget(clubCount);
    if (team.matchesPlayed == 0) {
      return 'Board target: finish in the top $target of $clubCount.';
    }
    final position = team.leaguePosition;
    return position <= target
        ? 'Board target: top $target of $clubCount — you are $position'
            '${position == 1 ? 'st' : position == 2 ? 'nd' : position == 3 ? 'rd' : 'th'}.'
        : 'Board target: top $target of $clubCount — you are $position'
            '${position == 1 ? 'st' : position == 2 ? 'nd' : position == 3 ? 'rd' : 'th'}, outside it.';
  }

  @override
  Widget build(BuildContext context) {
    final team = session.team;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MeterBar(label: 'Fan trust', value: team.fanTrust.toDouble()),
            const SizedBox(height: 10),
            MeterBar(
              label: 'Sack risk',
              value: session.manager.sackablePercent.toDouble(),
              color: const Color(0xFFEF5350),
            ),
            const SizedBox(height: 10),
            MeterBar(
              label: 'Legacy',
              value: session.manager.legacyScore.toDouble(),
              color: const Color(0xFF40C4FF),
            ),
            const SizedBox(height: 12),
            if (session.boardNote.isNotEmpty) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    session.manager.sackablePercent >= 70
                        ? Icons.report_problem_outlined
                        : Icons.campaign_outlined,
                    size: 16,
                    color: session.manager.sackablePercent >= 70
                        ? const Color(0xFFEF5350)
                        : null,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      session.boardNote,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                const Icon(Icons.flag_outlined, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _boardObjectiveText(),
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.payments_outlined, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Wage bill ${_formatMoney(_wageBill(team.squad))} · '
                    'revenue ${_formatMoney(team.revenue)}',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => context.go('/squad'),
            icon: const Icon(Icons.groups_outlined, size: 18),
            label: const Text('Squad'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => context.push('/transfers'),
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Transfers'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            // The league table is a drill-down from Home; Settings was already
            // a tab in the shell below, so that button was a duplicate.
            onPressed: () => context.push('/league-table'),
            icon: const Icon(Icons.table_chart_outlined, size: 18),
            label: const Text('Table'),
          ),
        ),
      ],
    );
  }
}

/// The club due to play this matchday, or null when the club has a bye.
Team? _opponentTeam(CareerSession session, PlayerDatabase? db) {
  if (db == null) return null;
  final fixtureId = session.season
      .currentFixtureFor(session.team.id)
      ?.opponentOf(session.team.id);
  if (fixtureId == null) return null;
  return db.teams.where((t) => t.id == fixtureId).firstOrNull;
}

double _wageBill(List<Player> squad) {
  var total = 0.0;
  for (final p in squad) {
    total += p.weeklyWage;
  }
  return total;
}

/// Average squad OVR, or 0 for an empty squad (the CSV filter guarantees a
/// club always has players, but a restored save could be short).
int _avgOvr(Team team) {
  if (team.squad.isEmpty) return 0;
  var total = 0;
  for (final p in team.squad) {
    total += p.ovr;
  }
  return (total / team.squad.length).round();
}

String _formatMoney(num amount) {
  if (amount >= 1000000000) {
    return '€${(amount / 1000000000).toStringAsFixed(1)}B';
  }
  if (amount >= 1000000) {
    return '€${(amount / 1000000).toStringAsFixed(0)}M';
  }
  if (amount >= 1000) return '€${(amount / 1000).toStringAsFixed(0)}K';
  return '€${amount.toStringAsFixed(0)}';
}
