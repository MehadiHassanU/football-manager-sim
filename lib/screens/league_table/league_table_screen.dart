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
        body: const EmptyState(icon: Icons.table_chart_outlined, title: 'No active career'),
      );
    }

    final standings = session.season.standings;
    final db = ref.watch(playerDatabaseProvider).valueOrNull;
    final entries = standings.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('League Table'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Home',
          onPressed: () => context.go('/home'),
        ),
      ),
      body: entries.isEmpty
          ? const EmptyState(
              icon: Icons.table_chart_outlined,
              title: 'No matches played yet',
              message: 'Standings appear after the first matchday.',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final isUser = entry.key == session.team.id;
                final team =
                    db?.teams.where((t) => t.id == entry.key).firstOrNull;
                return Card(
                  color: isUser
                      ? AppTheme.pitchGreen.withValues(alpha: 0.1)
                      : null,
                  child: ListTile(
                    leading: SizedBox(
                      width: 30,
                      child: Text(
                        '${index + 1}',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    title: Text(
                      team?.name ?? entry.key,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            isUser ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                    trailing: Text(
                      '${entry.value} pts',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
