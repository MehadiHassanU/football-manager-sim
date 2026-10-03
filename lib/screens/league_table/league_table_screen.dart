import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/career_session_provider.dart';
import '../../providers/data_providers.dart';
import '../../ui/ui.dart';

class LeagueTableScreen extends ConsumerWidget {
  const LeagueTableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(careerSessionProvider);
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('League Table')),
        body: const EmptyState(
            icon: Icons.table_chart_outlined, title: 'No active career'),
      );
    }

    final standings = session.season.table();
    final db = ref.watch(playerDatabaseProvider).valueOrNull;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('League Table ${session.season.currentYear}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Home',
          onPressed: () => context.go('/home'),
        ),
      ),
      body: standings.isEmpty
          ? const EmptyState(
              icon: Icons.table_chart_outlined,
              title: 'No matches played yet',
              message: 'Standings appear after the first matchday.',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: standings.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return _TableHeader(theme: theme);
                final row = standings[index - 1];
                final isUser = row.teamId == session.team.id;
                final team =
                    db?.teams.where((t) => t.id == row.teamId).firstOrNull;
                final record = row.record;
                final gd = record.goalDifference;
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  color: isUser
                      ? AppTheme.pitchGreen.withValues(alpha: 0.1)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
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
                              fontWeight:
                                  isUser ? FontWeight.w700 : FontWeight.w400,
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
            ),
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

/// Column headings, aligned to the rows below.
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
