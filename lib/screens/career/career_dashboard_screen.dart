import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/career_providers.dart';
import '../../providers/team_providers.dart';
import '../../providers/season_providers.dart';

class CareerDashboardScreen extends ConsumerWidget {
  const CareerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(managerProvider);
    final team = ref.watch(teamProvider);
    final season = ref.watch(seasonProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Career Dashboard')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Manager: ${manager.name}',
                style: Theme.of(context).textTheme.headlineSmall),
            Text('Age: ${manager.age} | Nationality: ${manager.nationality}'),
            const SizedBox(height: 16),
            if (team != null) ...[
              Text('Team: ${team.name}',
                  style: Theme.of(context).textTheme.headlineSmall),
              Text('League: ${team.leagueId}'),
              Text('Budget: ${team.budget}'),
              Text(
                  'Matchday: ${season.currentMatchday}/${season.totalMatchdays}'),
              Text('Points: ${season.standings[team.id] ?? 0}'),
              const SizedBox(height: 16),
            ],
            ElevatedButton(
              onPressed: () => context.go('/match'),
              child: const Text('Play Next Match'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => Navigator.of(context)
                  .pushReplacementNamed('/team-management'),
              child: const Text('Team Management'),
            ),
          ],
        ),
      ),
    );
  }
}
