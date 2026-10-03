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
    final db = ref.watch(playerDatabaseProvider).valueOrNull;

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
            onPressed: () => context.go('/league-table'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _NextMatchHero(
                session: session, opponent: _opponentTeam(session, db)),
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
  const _NextMatchHero({required this.session, required this.opponent});

  final CareerSession session;
  final Team? opponent;

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

    return Card(
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
                      ? _placeholder(context, align: CrossAxisAlignment.end)
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
                      _primaryLabel(hasFixture, isBye, isComplete),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
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
    );
  }

  String _primaryLabel(bool hasFixture, bool isBye, bool isComplete) {
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
      {required CrossAxisAlignment align}) {
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
          child: Icon(Icons.help_outline,
              size: 20, color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: 8),
        Text('Opponent',
            style: theme.textTheme.titleMedium?.copyWith(fontSize: 14)),
        Text('to be confirmed', style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Four compact number tiles: position, points, form, budget.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.session});

  final CareerSession session;

  @override
  Widget build(BuildContext context) {
    final team = session.team;
    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Position',
            value: team.matchesPlayed == 0 ? '—' : '${team.leaguePosition}',
            icon: Icons.leaderboard_outlined,
            onTap: () => context.go('/league-table'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: 'Points',
            value: '${team.points}',
            icon: Icons.stars_outlined,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: 'Record',
            value: team.matchesPlayed == 0
                ? '—'
                : '${team.wins}-${team.draws}-${team.losses}',
            icon: Icons.timeline_outlined,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: 'Budget',
            value: _formatMoney(team.transferBudget),
            icon: Icons.savings_outlined,
            onTap: () => context.go('/transfers'),
          ),
        ),
      ],
    );
  }
}

class _PressureCard extends StatelessWidget {
  const _PressureCard({required this.session});

  final CareerSession session;

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
            onPressed: () => context.go('/transfers'),
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Transfers'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => context.go('/settings'),
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Settings'),
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
