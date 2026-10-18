import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/team.dart';
import '../../providers/career_session_provider.dart';
import '../../providers/data_providers.dart';
import '../../ui/ui.dart';

class LeagueTableScreen extends ConsumerStatefulWidget {
  const LeagueTableScreen({super.key});

  @override
  ConsumerState<LeagueTableScreen> createState() => _LeagueTableScreenState();
}

class _LeagueTableScreenState extends ConsumerState<LeagueTableScreen> {
  /// False shows the standings, true the season's top scorers.
  bool _showScorers = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(careerSessionProvider);
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('League Table')),
        body: const EmptyState(
            icon: Icons.table_chart_outlined, title: 'No active career'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('League Table ${session.season.currentYear}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Home',
          onPressed: () => context.go('/home'),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Table'),
                  icon: Icon(Icons.table_chart_outlined, size: 16),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Top scorers'),
                  icon: Icon(Icons.sports_soccer, size: 16),
                ),
              ],
              selected: {_showScorers},
              onSelectionChanged: (selection) =>
                  setState(() => _showScorers = selection.first),
            ),
          ),
          Expanded(
            child: _showScorers
                ? _ScorersList(session: session)
                : _StandingsList(session: session),
          ),
        ],
      ),
    );
  }
}

/// The league table itself: position, club, played, goal difference, points.
class _StandingsList extends ConsumerWidget {
  const _StandingsList({required this.session});

  final CareerSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standings = session.season.table();
    final db = ref.watch(playerDatabaseProvider).valueOrNull;
    final theme = Theme.of(context);
    // Team lookup index built once per build instead of a linear scan per
    // visible row while the list scrolls.
    final teamById = {
      for (final t in db?.teams ?? const <Team>[]) t.id: t,
    };

    if (standings.isEmpty) {
      return const EmptyState(
        icon: Icons.table_chart_outlined,
        title: 'No matches played yet',
        message: 'Standings appear after the first matchday.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: standings.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _TableHeader(theme: theme);
        final row = standings[index - 1];
        final isUser = row.teamId == session.team.id;
        final team = teamById[row.teamId];
        final record = row.record;
        final gd = record.goalDifference;
        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          color: isUser ? AppTheme.pitchGreen.withValues(alpha: 0.1) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '${row.position}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: Text(
                    team?.name ?? row.teamId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isUser ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
                _cell(theme, '${record.played}'),
                _cell(theme, gd > 0 ? '+$gd' : '$gd'),
                SizedBox(
                  width: 38,
                  child: Text(
                    '${record.points}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// One right-aligned numeric column.
  Widget _cell(ThemeData theme, String value) => SizedBox(
        width: 38,
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: theme.textTheme.bodyMedium,
        ),
      );
}

/// The season's leading scorers, goals and assists, best first.
class _ScorersList extends StatelessWidget {
  const _ScorersList({required this.session});

  final CareerSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = session.season.topScorers(limit: 25);
    if (top.isEmpty) {
      return const EmptyState(
        icon: Icons.sports_soccer,
        title: 'No goals yet',
        message: 'The leading scorers appear once the season is under way.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: top.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _ScorersHeader(theme: theme);
        final row = top[index - 1];
        final isUser = row.clubId == session.team.id;
        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          color: isUser ? AppTheme.pitchGreen.withValues(alpha: 0.1) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '$index',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.playerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: isUser ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                      Text(
                        row.clubName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 38,
                  child: Text(
                    '${row.goals}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(
                  width: 38,
                  child: Text(
                    '${row.assists}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Column headings, aligned to the standings rows below.
class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final label = theme.textTheme.labelSmall;
    Widget cell(String text,
            {double width = 38, TextAlign align = TextAlign.right}) =>
        SizedBox(
          width: width,
          child: Text(text, textAlign: align, style: label),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          cell('', width: 24, align: TextAlign.left),
          Expanded(child: Text('', style: label)),
          cell('P'),
          cell('GD'),
          cell('Pts'),
        ],
      ),
    );
  }
}

/// Column headings for the scorer list: goals then assists.
class _ScorersHeader extends StatelessWidget {
  const _ScorersHeader({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final label = theme.textTheme.labelSmall;
    Widget cell(String text,
            {double width = 38, TextAlign align = TextAlign.right}) =>
        SizedBox(
          width: width,
          child: Text(text, textAlign: align, style: label),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          cell('', width: 24, align: TextAlign.left),
          Expanded(child: Text('', style: label)),
          cell('G'),
          cell('A'),
        ],
      ),
    );
  }
}
