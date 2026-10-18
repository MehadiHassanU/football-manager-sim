import '../models/fixture.dart';
import '../models/season.dart';
import '../services/cup_service.dart';

/// What a row of the season calendar represents.
enum CalendarEntryKind {
  /// A league or cup tie the manager's club plays.
  fixture,

  /// The round goes ahead without the club: a league bye, or a cup bye
  /// recorded in the bracket.
  bye,

  /// A cup round the bracket has not drawn yet, shown while the club is
  /// still alive: a date it might play on.
  cupSlot,

  /// The league's winter pause — a marker in the season, not a match.
  winterBreak,
}

/// One dated row of the season calendar.
class CalendarEntry {
  const CalendarEntry({
    required this.round,
    required this.date,
    required this.kind,
    this.fixture,
    this.cupRoundLabel,
    this.isCurrent = false,
  });

  /// Index into `SeasonState.rounds`.
  final int round;

  /// The day the round is played on, derived from the season year.
  final DateTime date;

  final CalendarEntryKind kind;

  /// The club's tie — null on bye and winter-break rows.
  final Fixture? fixture;

  /// 'Quarter-finals', 'Final'… for cup rounds; null on league rows.
  final String? cupRoundLabel;

  /// The round the season is sitting on right now.
  final bool isCurrent;

  /// Whether this row belongs to the cup.
  bool get isCup => cupRoundLabel != null || fixture?.competition == 'cup';
}

/// The season read as a calendar of real dates.
///
/// The game's clock is the matchday counter: matchday 0 sits at the start of
/// August and every round ticks it a week forward. That same clock already
/// underlies injuries (an expected return is a date), so the schedule screen
/// reads it rather than storing dates of its own — no save changes, and an
/// old save lands on the same calendar.
class SeasonCalendar {
  SeasonCalendar._();

  /// The date round [round] is played on: 1 August of the season year, one
  /// week per round. This is the same convention [InjuryService] dates
  /// injuries by, and it is deliberately derived rather than stored.
  static DateTime dateOfRound(int year, int round) =>
      DateTime(year, 8, 1).add(Duration(days: 7 * round));

  /// Cup ties read as midweek fixtures: shown four days before the Saturday
  /// their matchday slot keeps. Presentation only — nothing else in the game
  /// reads a shifted date.
  static const Duration cupMidweekShift = Duration(days: 4);

  /// The rows of the season in playing order, from [teamId]'s point of view.
  ///
  /// Only rounds that mean something to the club appear: its own ties, cup
  /// dates it could still reach, its byes, the winter break, and the current
  /// round even when it is a bye. Rounds where the club is not involved and
  /// does not play — other clubs' cup progression after an early exit,
  /// historical league byes — carry nothing worth a row.
  static List<CalendarEntry> build(SeasonState season, String teamId) {
    if (season.rounds.isEmpty) return const [];

    final entries = <CalendarEntry>[];
    final cup = season.cup;
    final cupRoundOfAnchor = <int, int>{
      if (cup != null)
        for (var k = 0; k < cup.anchors.length; k++) cup.anchors[k]: k,
    };

    for (var round = 0; round < season.rounds.length; round++) {
      final derived = dateOfRound(season.currentYear, round);
      final cupRound = cupRoundOfAnchor[round];
      final date =
          cupRound == null ? derived : derived.subtract(cupMidweekShift);

      if (round == season.winterBreakRound) {
        // Midweek ahead of the paused round, so the list never runs backwards
        // in time, whichever row the round itself produces.
        entries.add(CalendarEntry(
          round: round,
          date: derived.subtract(cupMidweekShift),
          kind: CalendarEntryKind.winterBreak,
        ));
      }

      final fixture = season.userFixtureForRound(round, teamId);
      if (fixture != null) {
        entries.add(CalendarEntry(
          round: round,
          date: date,
          kind: CalendarEntryKind.fixture,
          fixture: fixture,
          cupRoundLabel: cupRound == null
              ? null
              : CupService.roundNameOf(season, cupRound),
          isCurrent: round == season.currentMatchday,
        ));
        continue;
      }

      if (cupRound != null && cup?.byes[cupRound] == teamId) {
        entries.add(CalendarEntry(
          round: round,
          date: date,
          kind: CalendarEntryKind.bye,
          cupRoundLabel: CupService.roundNameOf(season, cupRound),
          isCurrent: round == season.currentMatchday,
        ));
      } else if (cupRound != null &&
          season.fixturesForRound(round).isEmpty &&
          CupService.clubIsAlive(season, teamId)) {
        // The bracket draws a round only when the one before it is done, so
        // a round ahead is a date the club might play on — which is exactly
        // what the manager opens the calendar for.
        entries.add(CalendarEntry(
          round: round,
          date: date,
          kind: CalendarEntryKind.cupSlot,
          cupRoundLabel: CupService.roundNameOf(season, cupRound),
          isCurrent: round == season.currentMatchday,
        ));
      } else if (cupRound == null && round == season.currentMatchday) {
        // A league bye is only news as the current state of the season: the
        // manager needs to know this week will not be played.
        entries.add(CalendarEntry(
          round: round,
          date: date,
          kind: CalendarEntryKind.bye,
          isCurrent: true,
        ));
      }
    }
    return entries;
  }

  /// 'Sat 15 Aug' — the year is implied by the season heading.
  static String formatDate(DateTime date) =>
      '${_weekdays[date.weekday - 1]} ${date.day} '
      '${_monthNames[date.month - 1]}';

  /// 'August 2026' — the group heading above a month's rows.
  static String monthLabel(DateTime date) =>
      '${_longMonthNames[date.month - 1]} ${date.year}';

  /// '2026/27' — the season heading.
  static String seasonLabel(int year) =>
      '$year/${((year + 1) % 100).toString().padLeft(2, '0')}';

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const _longMonthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
}
