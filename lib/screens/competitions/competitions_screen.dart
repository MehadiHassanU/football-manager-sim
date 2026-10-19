import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/continental_catalog.dart';
import '../../core/models/continental.dart';
import '../../core/models/cup.dart';
import '../../core/models/fixture.dart';
import '../../core/models/season.dart';
import '../../core/models/team.dart';
import '../../core/services/continental_service.dart';
import '../../core/services/cup_service.dart';
import '../../core/utils/season_calendar.dart';
import '../../providers/career_session_provider.dart';
import '../../providers/data_providers.dart';
import '../../ui/ui.dart';

/// The season's knockout competitions, drawn as brackets.
///
/// One card per competition: the club's own route through it (results, byes,
/// the next date it might play), the full round-by-round draw, and the
/// winner when the final has been played. The career's trophy cabinet closes
/// the screen — the long-term answer to "what have I actually won?".
///
/// The bracket is rebuilt from the season's fixtures and the persisted draw
/// state, so it is always the truth the match engine played, never a separate
/// copy that could drift from the calendar.
class CompetitionsScreen extends ConsumerWidget {
  const CompetitionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(careerSessionProvider);
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Competitions')),
        body: const Center(child: Text('No active career.')),
      );
    }
    final season = session.season;
    final teams =
        ref.watch(playerDatabaseProvider).valueOrNull?.teams ?? <Team>[];
    final names = {for (final team in teams) team.id: team.name};
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Competitions'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                SeasonCalendar.seasonLabel(season.currentYear),
                style: theme.textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (season.continental.isNotEmpty)
            for (final competition in season.continental) ...[
              _ContinentalCard(
                season: season,
                comp: competition,
                userId: session.team.id,
                names: names,
              ),
              const SizedBox(height: 12),
            ]
          else if (ContinentalCatalog.qualifiesFrom(session.team.leagueId))
            _ContinentalQualificationCard(
              region: ContinentalCatalog.regionOf(session.team.leagueId)!,
            ),
          if (season.cups.isEmpty)
            const _EmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'No competitions yet',
              message: 'This season was created before cup competitions. '
                  'The country\'s cups arrive with the next season.',
            )
          else
            for (final cup in season.cups) ...[
              _CompetitionCard(
                season: season,
                cup: cup,
                userId: session.team.id,
                names: names,
              ),
              const SizedBox(height: 12),
            ],
          const SizedBox(height: 8),
          _TrophyCabinet(trophies: session.trophies),
        ],
      ),
    );
  }
}

class _CompetitionCard extends StatelessWidget {
  const _CompetitionCard({
    required this.season,
    required this.cup,
    required this.userId,
    required this.names,
  });

  final SeasonState season;
  final CupState cup;
  final String userId;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final winner = CupService.winnerOf(season, cup);
    final alive = CupService.clubIsAlive(season, userId, cup: cup);
    final entered = cup.entrants.isEmpty ||
        cup.entrants.values.any((ids) => ids.contains(userId));
    final currentRound = _currentRoundIndex();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      cup.kind == CupKind.superCup
                          ? Icons.shield_outlined
                          : Icons.emoji_events_outlined,
                      size: 20,
                      color: alive
                          ? AppTheme.pitchGreen
                          : theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cup.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _KindChip(kind: cup.kind),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _statusLine(winner: winner, alive: alive, entered: entered),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: winner == userId
                        ? AppTheme.pitchGreen
                        : theme.colorScheme.onSurface.withValues(alpha: 0.68),
                    fontWeight: winner == userId ? FontWeight.w700 : null,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'YOUR ROUTE',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.1,
                fontSize: 11,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
            child: entered
                ? _YourRoute(
                    season: season,
                    cup: cup,
                    userId: userId,
                    names: names,
                    alive: alive,
                  )
                : Text(
                    'Did not qualify for this competition this season.',
                    style: theme.textTheme.bodySmall,
                  ),
          ),
          const Divider(height: 1),
          _Bracket(
            season: season,
            cup: cup,
            userId: userId,
            names: names,
            currentRound: currentRound,
          ),
        ],
      ),
    );
  }

  /// The round the season is on (or the last one before it within this cup).
  int _currentRoundIndex() {
    final anchor = season.currentMatchday;
    final index = cup.anchors.indexOf(anchor);
    if (index >= 0) return index;
    var last = -1;
    for (var k = 0; k < cup.anchors.length; k++) {
      if (cup.anchors[k] <= anchor) last = k;
    }
    return last;
  }

  String _statusLine({
    required String? winner,
    required bool alive,
    required bool entered,
  }) {
    if (winner != null) {
      return winner == userId
          ? 'Champions — the cup is in the cabinet.'
          : 'Winners: ${_name(winner)}.';
    }
    if (!entered) return 'Not in this season\'s draw.';
    if (alive) {
      final next = _nextFixtureRound();
      if (next == null) return 'Still in the draw.';
      final roundName = CupService.roundNameOf(season, next.$1, cup: cup);
      final date = SeasonCalendar.formatDate(
        SeasonCalendar.dateOf(season, cup.anchors[next.$1]),
      );
      return 'Still in — ${next.$2} in the $roundName on $date.';
    }
    final exit = CupService.clubExitLabel(season, userId, cup: cup);
    if (exit == 'Runners-up') return 'Runners-up — beaten in the final.';
    return exit == null ? 'Knocked out.' : '$exit.';
  }

  /// The next drawn round with a user tie, or the next round the club could
  /// still reach when the bracket has not been drawn that far.
  (int, String)? _nextFixtureRound() {
    for (var k = 0; k < cup.anchors.length; k++) {
      final round = season.rounds[cup.anchors[k]];
      if (round.any((f) => f.involves(userId) && !f.played)) {
        final tie = round.firstWhere((f) => f.involves(userId));
        return (k, 'a tie against ${_opponent(tie)}');
      }
      if (round.isEmpty) {
        return (k, 'a possible tie');
      }
    }
    return null;
  }

  String _opponent(Fixture tie) =>
      tie.homeTeamId == userId ? _name(tie.awayTeamId) : _name(tie.homeTeamId);

  String _name(String id) => names[id] ?? id;
}

class _YourRoute extends StatelessWidget {
  const _YourRoute({
    required this.season,
    required this.cup,
    required this.userId,
    required this.names,
    required this.alive,
  });

  final SeasonState season;
  final CupState cup;
  final String userId;
  final Map<String, String> names;
  final bool alive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    var shownPending = false;

    for (var k = 0; k < cup.anchors.length; k++) {
      final round = season.rounds[cup.anchors[k]];
      final label = CupService.roundNameOf(season, k, cup: cup);
      final date = SeasonCalendar.formatDate(
        SeasonCalendar.dateOf(season, cup.anchors[k]),
      );
      final tie = round.where((f) => f.involves(userId)).firstOrNull;
      final bye = cup.byes[k] == userId;
      if (tie != null) {
        rows.add(_ResultRow(
          season: season,
          label: label,
          date: date,
          tie: tie,
          userId: userId,
          names: names,
        ));
        continue;
      }
      if (bye) {
        rows.add(_RouteLine(
          icon: Icons.subdirectory_arrow_right,
          title: 'Bye — $label',
          subtitle: date,
        ));
        continue;
      }
      if (round.isEmpty && alive && !shownPending) {
        rows.add(_RouteLine(
          icon: Icons.schedule,
          title: 'Possible $label',
          subtitle: '$date, if the club gets there',
          muted: true,
        ));
        shownPending = true;
      }
    }

    if (rows.isEmpty) {
      return Text(
        alive
            ? 'The draw has not reached the club yet.'
            : 'No ties played in this competition.',
        style: theme.textTheme.bodySmall,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          rows[i],
        ],
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.season,
    required this.label,
    required this.date,
    required this.tie,
    required this.userId,
    required this.names,
  });

  final SeasonState season;
  final String label;
  final String date;
  final Fixture tie;
  final String userId;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHome = tie.homeTeamId == userId;
    final opponentId = isHome ? tie.awayTeamId : tie.homeTeamId;
    final opponent = names[opponentId] ?? opponentId;
    final goalsFor = isHome ? tie.homeGoals : tie.awayGoals;
    final goalsAgainst = isHome ? tie.awayGoals : tie.homeGoals;
    final winner = tie.played ? CupService.tieWinner(season, tie) : null;
    final advanced = winner == userId;
    final drew = tie.homeGoals == tie.awayGoals;
    final result = !tie.played
        ? 'v'
        : goalsFor > goalsAgainst
            ? 'W'
            : goalsFor < goalsAgainst
                ? 'L'
                : (advanced ? 'W' : 'L');
    final score = tie.played ? '$goalsFor–$goalsAgainst' : '—';
    final pens = tie.played && drew && tie.competition != 'league';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResultBadge(
          result: tie.played ? result : '·',
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label — ${isHome ? 'vs' : 'at'} $opponent',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '$date${tie.played ? ' · $score${pens ? ' (pens)' : ''}' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (tie.played)
          Text(
            result,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: result == 'W'
                  ? AppTheme.pitchGreen
                  : result == 'L'
                      ? theme.colorScheme.error
                      : null,
            ),
          ),
      ],
    );
  }
}

class _ResultBadge extends StatelessWidget {
  const _ResultBadge({required this.result});

  final String result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = result == 'W'
        ? AppTheme.pitchGreen
        : result == 'L'
            ? theme.colorScheme.error
            : theme.colorScheme.outline;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        result,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RouteLine extends StatelessWidget {
  const _RouteLine({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.muted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = muted
        ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
        : theme.colorScheme.onSurface.withValues(alpha: 0.75);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.bodyMedium?.copyWith(color: color)),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bracket extends StatelessWidget {
  const _Bracket({
    required this.season,
    required this.cup,
    required this.userId,
    required this.names,
    required this.currentRound,
  });

  final SeasonState season;
  final CupState cup;
  final String userId;
  final Map<String, String> names;
  final int currentRound;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tiles = <Widget>[];
    for (var k = 0; k < cup.anchors.length; k++) {
      final round = season.rounds[cup.anchors[k]];
      final label = CupService.roundNameOf(season, k, cup: cup);
      final date = SeasonCalendar.formatDate(
        SeasonCalendar.dateOf(season, cup.anchors[k]),
      );
      if (round.isEmpty) {
        // One hinted tile for the next undrawn round is enough; the rest are
        // dates the bracket has not reached.
        tiles.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            children: [
              Icon(Icons.lock_clock,
                  size: 16, color: theme.colorScheme.outline),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$label · $date — yet to be drawn',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ));
        break;
      }
      final played = round.every((f) => f.played);
      final hasUser = round.any((f) => f.involves(userId));
      tiles.add(ExpansionTile(
        initiallyExpanded: hasUser || k == currentRound,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: hasUser ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '$date · ${round.length} ${round.length == 1 ? 'tie' : 'ties'}'
          '${played ? ' · played' : ''}',
          style: theme.textTheme.bodySmall,
        ),
        children: [
          for (final tie in round)
            _TieRow(
              season: season,
              tie: tie,
              userId: userId,
              names: names,
            ),
        ],
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
          child: Text(
            'BRACKET',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.1,
              fontSize: 11,
            ),
          ),
        ),
        ...tiles,
      ],
    );
  }
}

class _TieRow extends StatelessWidget {
  const _TieRow({
    required this.season,
    required this.tie,
    required this.userId,
    required this.names,
  });

  final SeasonState season;
  final Fixture tie;
  final String userId;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ours = tie.involves(userId);
    final winner = tie.played ? CupService.tieWinner(season, tie) : null;
    final drew = tie.homeGoals == tie.awayGoals;
    String side(String id) => names[id] ?? id;
    final style = theme.textTheme.bodySmall?.copyWith(
      fontWeight: ours ? FontWeight.w700 : FontWeight.w400,
      color: winner == null || winner == tie.homeTeamId
          ? theme.colorScheme.onSurface
          : theme.colorScheme.onSurface.withValues(alpha: 0.55),
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: ours
          ? BoxDecoration(
              color: AppTheme.pitchGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              side(tie.homeTeamId),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          Container(
            width: 58,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            child: Text(
              tie.played ? '${tie.homeGoals} – ${tie.awayGoals}' : 'v',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              side(tie.awayTeamId),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: ours ? FontWeight.w700 : FontWeight.w400,
                color: winner == null || winner == tie.awayTeamId
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
          if (tie.played && drew)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                'pens',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontSize: 9,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.kind});

  final CupKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (kind) {
      CupKind.national => 'Cup',
      CupKind.leagueCup => 'League cup',
      CupKind.superCup => 'Super cup',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
      ),
    );
  }
}

class _TrophyCabinet extends StatelessWidget {
  const _TrophyCabinet({required this.trophies});

  final List<String> trophies;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events, size: 20),
                const SizedBox(width: 8),
                Text(
                  'TROPHY CABINET',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.1,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                Text(
                  '${trophies.length}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (trophies.isEmpty)
              Text(
                'No silverware yet. The first one is always the loudest.',
                style: theme.textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final trophy in trophies)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.pitchGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.pitchGreen.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        trophy,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 36, color: theme.colorScheme.outline),
            const SizedBox(height: 10),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinentalQualificationCard extends StatelessWidget {
  const _ContinentalQualificationCard({
    required this.region,
  });

  final String region;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final competitions = ContinentalCatalog.competitionsOf(region);
    if (competitions.isEmpty) return const SizedBox.shrink();
    final top = competitions[0];
    final second = competitions.length > 1 ? competitions[1] : null;
    final third = competitions.length > 2 ? competitions[2] : null;
    final route = third != null
        ? 'The top four go to the ${top.name}, the next two to the '
            '${second!.name} and seventh to the ${third.name}.'
        : second != null
            ? 'The top four go to the ${top.name} and the next places to the '
                '${second.name}.'
            : 'The top four qualify for the ${top.name}.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.public, size: 20),
                const SizedBox(width: 8),
                Text(
                  'CONTINENTAL FOOTBALL',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.1,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Not qualified this season',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '$route The club is watching ${ContinentalCatalog.regionName(region)}'
              ' from home this year.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinentalCard extends StatelessWidget {
  const _ContinentalCard({
    required this.season,
    required this.comp,
    required this.userId,
    required this.names,
  });

  final SeasonState season;
  final ContinentalState comp;
  final String userId;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final winner = ContinentalService.winnerOf(season, comp);
    final exit = ContinentalService.clubExitLabel(season, comp, userId);
    final table = ContinentalService.tableOf(season, comp);
    final standing = table.where((row) => row.teamId == userId).firstOrNull;
    final leagueDone = comp.leagueAnchors.isNotEmpty &&
        comp.leagueAnchors.every((anchor) {
          final round = season.rounds[anchor];
          return round.isNotEmpty && round.every((f) => f.played);
        });
    final next = _nextLine();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.public, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        comp.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _ContinentChip(
                      label: ContinentalCatalog.regionName(comp.region),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _status(winner, exit, standing, leagueDone),
                  style: theme.textTheme.bodyMedium,
                ),
                if (next != null) ...[
                  const SizedBox(height: 3),
                  Text(next, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          _ContinentalRoute(
            season: season,
            comp: comp,
            userId: userId,
            names: names,
          ),
          const Divider(height: 1),
          _ContinentalStandings(
            season: season,
            comp: comp,
            userId: userId,
            names: names,
          ),
          _ContinentalKnockout(
            season: season,
            comp: comp,
            userId: userId,
            names: names,
          ),
        ],
      ),
    );
  }

  String _status(
    String? winner,
    String? exit,
    LeagueStanding? standing,
    bool leagueDone,
  ) {
    if (winner == userId) {
      return 'Champions of ${ContinentalCatalog.regionName(comp.region)} '
          '— the trophy is in the cabinet.';
    }
    if (winner != null) {
      return 'Winners: ${names[winner] ?? winner}.';
    }
    if (exit != null) return '$exit.';
    if (!leagueDone && standing != null) {
      final games = standing.record.played;
      return 'League phase — ${standing.position} of ${comp.clubIds.length} '
          'after $games ${games == 1 ? 'game' : 'games'} · '
          '${standing.record.points} pts.';
    }
    return 'Still in the competition.';
  }

  String? _nextLine() {
    String dateOf(int anchor) =>
        SeasonCalendar.formatDate(SeasonCalendar.dateOf(season, anchor));
    String labelOf(int anchor) =>
        ContinentalService.labelAt(season, anchor)?.$2 ?? 'Knockout round';

    for (final anchor in comp.leagueAnchors) {
      final fixture = season.userFixtureForRound(anchor, userId);
      if (fixture != null && !fixture.played) {
        return 'Next: ${labelOf(anchor)} · ${dateOf(anchor)}';
      }
    }
    for (final anchor in comp.knockoutAnchors) {
      final round = season.rounds[anchor];
      final fixture = round.where((f) => f.involves(userId)).firstOrNull;
      if (fixture != null && !fixture.played) {
        return 'Next: ${labelOf(anchor)} · ${dateOf(anchor)}';
      }
      if (round.isEmpty && ContinentalService.isAlive(season, comp, userId)) {
        return 'Next: ${labelOf(anchor)} · ${dateOf(anchor)} '
            '(if the club gets there)';
      }
    }
    return null;
  }
}

class _ContinentChip extends StatelessWidget {
  const _ContinentChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
      ),
    );
  }
}

class _ContinentalRoute extends StatelessWidget {
  const _ContinentalRoute({
    required this.season,
    required this.comp,
    required this.userId,
    required this.names,
  });

  final SeasonState season;
  final ContinentalState comp;
  final String userId;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    for (var k = 0; k < comp.leagueAnchors.length; k++) {
      final anchor = comp.leagueAnchors[k];
      final fixture = season.userFixtureForRound(anchor, userId);
      if (fixture == null) continue;
      rows.add(_ContinentalLegRow(
        label: 'League phase · Matchday ${k + 1}',
        date: SeasonCalendar.formatDate(SeasonCalendar.dateOf(season, anchor)),
        fixture: fixture,
        userId: userId,
        names: names,
      ));
    }
    for (var k = 0; k < comp.knockoutAnchors.length; k++) {
      final anchor = comp.knockoutAnchors[k];
      final fixture =
          season.rounds[anchor].where((f) => f.involves(userId)).firstOrNull;
      if (fixture == null) continue;
      final stage = k ~/ 2;
      final leg = stage == 4 ? 1 : (k.isEven ? 1 : 2);
      rows.add(_ContinentalLegRow(
        label: ContinentalService.stageLabel(stage, leg),
        date: SeasonCalendar.formatDate(SeasonCalendar.dateOf(season, anchor)),
        fixture: fixture,
        userId: userId,
        names: names,
      ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR ROUTE',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.1,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Text(
              'The league phase has not started yet.',
              style: theme.textTheme.bodySmall,
            )
          else
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              rows[i],
            ],
        ],
      ),
    );
  }
}

class _ContinentalLegRow extends StatelessWidget {
  const _ContinentalLegRow({
    required this.label,
    required this.date,
    required this.fixture,
    required this.userId,
    required this.names,
  });

  final String label;
  final String date;
  final Fixture fixture;
  final String userId;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHome = fixture.isHomeFor(userId);
    final opponentId = isHome ? fixture.awayTeamId : fixture.homeTeamId;
    final opponent = names[opponentId] ?? opponentId;
    final goalsFor = isHome ? fixture.homeGoals : fixture.awayGoals;
    final goalsAgainst = isHome ? fixture.awayGoals : fixture.homeGoals;
    final result = goalsFor > goalsAgainst
        ? 'W'
        : goalsFor < goalsAgainst
            ? 'L'
            : 'D';
    final score = fixture.played ? '$goalsFor–$goalsAgainst' : '—';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResultBadge(result: fixture.played ? result : '·'),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label — ${isHome ? 'vs' : 'at'} $opponent',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '$date${fixture.played ? ' · $score' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (fixture.played)
          Text(
            result,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: result == 'W'
                  ? AppTheme.pitchGreen
                  : result == 'L'
                      ? theme.colorScheme.error
                      : null,
            ),
          ),
      ],
    );
  }
}

class _ContinentalStandings extends StatelessWidget {
  const _ContinentalStandings({
    required this.season,
    required this.comp,
    required this.userId,
    required this.names,
  });

  final SeasonState season;
  final ContinentalState comp;
  final String userId;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final table = ContinentalService.tableOf(season, comp);
    return ExpansionTile(
      key: PageStorageKey('continental-table-${comp.id}'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Text(
        'League phase table',
        style:
            theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        'Top 8 straight to the round of 16 · 9th to 24th to the play-off',
        style: theme.textTheme.bodySmall,
      ),
      children: [
        _ContinentalTableRow(
          position: '#',
          club: 'Club',
          played: 'P',
          goalDifference: 'GD',
          points: 'Pts',
          header: true,
        ),
        const SizedBox(height: 2),
        for (final row in table)
          _ContinentalTableRow(
            position: '${row.position}',
            club: names[row.teamId] ?? row.teamId,
            played: '${row.record.played}',
            goalDifference: '${row.record.goalDifference}',
            points: '${row.record.points}',
            ours: row.teamId == userId,
          ),
      ],
    );
  }
}

class _ContinentalTableRow extends StatelessWidget {
  const _ContinentalTableRow({
    required this.position,
    required this.club,
    required this.played,
    required this.goalDifference,
    required this.points,
    this.ours = false,
    this.header = false,
  });

  final String position;
  final String club;
  final String played;
  final String goalDifference;
  final String points;
  final bool ours;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        (header ? theme.textTheme.labelSmall : theme.textTheme.bodySmall)
            ?.copyWith(
      fontWeight: ours ? FontWeight.w800 : null,
      color: ours ? AppTheme.pitchGreen : null,
    );
    Widget cell(String value, double width,
            {TextAlign align = TextAlign.right}) =>
        SizedBox(
          width: width,
          child: Text(value, style: style, textAlign: align),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3),
      color: ours ? AppTheme.pitchGreen.withValues(alpha: 0.06) : null,
      child: Row(
        children: [
          cell(position, 26),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              club,
              style: style,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          cell(played, 26),
          cell(goalDifference, 32),
          cell(points, 34),
        ],
      ),
    );
  }
}

class _ContinentalKnockout extends StatelessWidget {
  const _ContinentalKnockout({
    required this.season,
    required this.comp,
    required this.userId,
    required this.names,
  });

  final SeasonState season;
  final ContinentalState comp;
  final String userId;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tiles = <Widget>[];
    for (var stage = 0; stage < 5; stage++) {
      final anchor = comp.knockoutAnchors[stage == 4 ? 8 : stage * 2];
      final firstLeg = season.rounds[anchor];
      if (firstLeg.isEmpty) continue;
      final date = SeasonCalendar.formatDate(
        SeasonCalendar.dateOf(season, anchor),
      );
      final hasUser = firstLeg.any((f) => f.involves(userId));
      tiles.add(ExpansionTile(
        key: PageStorageKey('continental-knockout-${comp.id}-$stage'),
        initiallyExpanded: hasUser,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: Text(
          ContinentalService.stageName(stage),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: hasUser ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '$date · ${firstLeg.length} '
          '${firstLeg.length == 1 ? 'tie' : 'ties'}',
          style: theme.textTheme.bodySmall,
        ),
        children: [
          for (final tie in firstLeg)
            _ContinentalTieRow(
              season: season,
              comp: comp,
              tie: tie,
              userId: userId,
              names: names,
            ),
        ],
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
          child: Text(
            'KNOCKOUTS',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.1,
              fontSize: 11,
            ),
          ),
        ),
        if (tiles.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Text(
              'The bracket is drawn when the league phase ends.',
              style: theme.textTheme.bodySmall,
            ),
          )
        else
          ...tiles,
      ],
    );
  }
}

class _ContinentalTieRow extends StatelessWidget {
  const _ContinentalTieRow({
    required this.season,
    required this.comp,
    required this.tie,
    required this.userId,
    required this.names,
  });

  final SeasonState season;
  final ContinentalState comp;
  final Fixture tie;
  final String userId;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ours = tie.involves(userId);
    final aggregate = ContinentalService.aggregateOf(season, comp, tie);
    final complete = _complete();
    final winner =
        complete ? ContinentalService.tieWinner(season, comp, tie) : null;
    String side(String id) => names[id] ?? id;
    final style = theme.textTheme.bodySmall?.copyWith(
      fontWeight: ours ? FontWeight.w700 : FontWeight.w400,
      color: winner == null || winner == tie.homeTeamId
          ? theme.colorScheme.onSurface
          : theme.colorScheme.onSurface.withValues(alpha: 0.55),
    );
    final score = !tie.played
        ? 'v'
        : '${aggregate.home}–${aggregate.away}'
            '${complete && aggregate.penalties ? ' (pens)' : ''}';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: ours
          ? BoxDecoration(
              color: AppTheme.pitchGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              side(tie.homeTeamId),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(score, style: theme.textTheme.labelMedium),
          ),
          Expanded(
            child: Text(
              side(tie.awayTeamId),
              overflow: TextOverflow.ellipsis,
              style: style?.copyWith(
                color: winner == null || winner == tie.awayTeamId
                    ? style.color
                    : theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _complete() {
    if (!tie.played) return false;
    final index = comp.knockoutAnchors.indexOf(tie.round);
    if (index < 0 || index >= 8) return true;
    final stage = index ~/ 2;
    final otherAnchor =
        comp.knockoutAnchors[stage * 2 + (index.isEven ? 1 : 0)];
    final other = season.rounds[otherAnchor];
    return other.isNotEmpty && other.every((f) => f.played);
  }
}
