import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/fixture.dart';
import '../../core/models/season.dart';
import '../../core/models/team.dart';
import '../../core/services/cup_service.dart';
import '../../core/utils/season_calendar.dart';
import '../../providers/career_session_provider.dart';
import '../../providers/data_providers.dart';
import '../../ui/ui.dart';

/// The season as a diary: every league and cup date still to come, with the
/// results already banked alongside.
///
/// Dates are derived from the matchday counter (see [SeasonCalendar]), so the
/// screen adds no stored state and every save — old or new — renders the same
/// calendar.
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(careerSessionProvider);
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Schedule')),
        body: const EmptyState(
          icon: Icons.calendar_month_outlined,
          title: 'No active career',
          message: 'Start a career first to see its schedule.',
        ),
      );
    }

    final season = session.season;
    final teamId = session.team.id;
    final entries = SeasonCalendar.build(season, teamId);
    final db = ref.watch(playerDatabaseProvider).valueOrNull;
    final nameOf = <String, String>{};
    for (final team in db?.teams ?? const <Team>[]) {
      nameOf[team.id] = team.name;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Schedule')),
      body: entries.isEmpty
          ? const EmptyState(
              icon: Icons.event_busy_outlined,
              title: 'No schedule',
              message: 'This season has not been drawn yet.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: _rows(context, season, teamId, entries, nameOf),
            ),
    );
  }

  /// The header, month headings and one row per entry, in season order.
  List<Widget> _rows(
    BuildContext context,
    SeasonState season,
    String teamId,
    List<CalendarEntry> entries,
    Map<String, String> nameOf,
  ) {
    final rows = <Widget>[_SeasonHeader(season: season)];
    String? lastMonth;
    for (final entry in entries) {
      final month = SeasonCalendar.monthLabel(entry.date);
      if (month != lastMonth) {
        lastMonth = month;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
          child: Text(month,
              style: Theme.of(context).textTheme.titleSmall),
        ));
      }
      rows.add(_CalendarRow(
        entry: entry,
        teamId: teamId,
        opponentName: _opponentName(entry.fixture, teamId, nameOf),
        pens: _pensSuffix(season, entry.fixture, teamId),
      ));
    }
    return rows;
  }
}

/// The other club in the tie, or an empty string for rows without one.
String _opponentName(
  Fixture? fixture,
  String teamId,
  Map<String, String> nameOf,
) {
  final id = fixture?.opponentOf(teamId);
  if (id == null) return '';
  return nameOf[id] ?? id;
}

/// 'won on pens' / 'lost on pens' for a drawn cup tie already played; null
/// for everything else. The verdict itself comes from [CupService], so the
/// calendar can never disagree with the bracket.
String? _pensSuffix(SeasonState season, Fixture? fixture, String teamId) {
  if (fixture == null || !fixture.played || fixture.competition == 'league') {
    return null;
  }
  final note = CupService.shootoutNote(
    season: season,
    tie: fixture,
    teamId: teamId,
    homeGoals: fixture.homeGoals,
    awayGoals: fixture.awayGoals,
  );
  if (note == null) return null;
  return note.advanced ? 'won on pens' : 'lost on pens';
}

/// Season heading plus where the career currently stands.
class _SeasonHeader extends StatelessWidget {
  const _SeasonHeader({required this.season});

  final SeasonState season;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = season.isPreSeason
        ? 'Pre-season'
        : season.isPostSeason
            ? 'Season complete'
            : season.isWinterBreak
                ? 'Winter break · resume from Home'
                : 'Matchday ${season.matchdayNumber} '
                    'of ${season.totalMatchdays}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_outlined, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Season ${SeasonCalendar.seasonLabel(season.currentYear)}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(state, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One dated row: the tie, its competition and either the result already
/// banked or the NEXT UP marker on the round the season is sitting on.
class _CalendarRow extends StatelessWidget {
  const _CalendarRow({
    required this.entry,
    required this.teamId,
    required this.opponentName,
    required this.pens,
  });

  final CalendarEntry entry;
  final String teamId;
  final String opponentName;
  final String? pens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (entry.kind == CalendarEntryKind.winterBreak) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Expanded(child: Divider(height: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'Winter break',
                style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1),
              ),
            ),
            const Expanded(child: Divider(height: 1)),
          ],
        ),
      );
    }

    final fixture = entry.fixture;
    final isHome = fixture?.isHomeFor(teamId) ?? false;
    final title = switch (entry.kind) {
      CalendarEntryKind.bye => entry.cupRoundLabel == null
          ? 'No fixture this week'
          : 'Bye · through to the next round',
      CalendarEntryKind.cupSlot => 'Cup tie',
      _ => isHome ? 'vs $opponentName' : 'at $opponentName',
    };
    final competition = entry.isCup
        ? (entry.competitionLabel ?? 'Cup')
        : 'League';
    final subtitleBase = switch (entry.kind) {
      CalendarEntryKind.bye => competition,
      CalendarEntryKind.cupSlot => '$competition · if through',
      _ => '$competition · ${isHome ? 'Home' : 'Away'}',
    };
    // The shootout verdict rides the detail line rather than the score
    // column, where it could be squeezed out by a long club name.
    final subtitle =
        pens == null ? subtitleBase : '$subtitleBase · $pens';

    String? resultText;
    Color? resultColor;
    if (fixture != null && fixture.played) {
      final mine = isHome ? fixture.homeGoals : fixture.awayGoals;
      final theirs = isHome ? fixture.awayGoals : fixture.homeGoals;
      final won = mine > theirs;
      final drew = mine == theirs;
      resultText = '${won ? 'W' : drew ? 'D' : 'L'} $mine–$theirs';
      if (won) {
        resultColor = AppTheme.pitchGreen;
      } else if (!drew) {
        resultColor = const Color(0xFFEF5350);
      } else if (pens != null) {
        // A drawn cup tie is won or lost on the shootout, not the scoreline.
        resultColor = pens == 'won on pens'
            ? AppTheme.pitchGreen
            : const Color(0xFFEF5350);
      } else {
        resultColor = const Color(0xFFFFB300);
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: entry.isCurrent
              ? AppTheme.pitchGreen
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: entry.isCurrent ? 1.4 : 1,
        ),
        color: entry.isCurrent
            ? AppTheme.pitchGreen.withValues(alpha: 0.07)
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              SeasonCalendar.formatDate(entry.date),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: entry.isCurrent ? FontWeight.w800 : null,
                color: entry.isCurrent ? AppTheme.pitchGreen : null,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (entry.isCurrent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.pitchGreen.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'NEXT UP',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppTheme.pitchGreen,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            )
          else if (resultText != null)
            Text(
              resultText,
              style: theme.textTheme.labelMedium?.copyWith(
                color: resultColor,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}
