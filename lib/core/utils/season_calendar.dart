import '../models/cup.dart';
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
    this.cupName,
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

  /// 'FA Cup', 'EFL Cup'… for cup rounds; null on league rows.
  final String? cupName;

  /// 'Quarter-finals', 'Final'… for cup rounds; null on league rows.
  final String? cupRoundLabel;

  /// The round the season is sitting on right now.
  final bool isCurrent;

  /// Whether this row belongs to a knockout competition.
  bool get isCup => cupName != null || (fixture?.competition ?? 'league') != 'league';

  /// 'FA Cup · Quarter-finals', or null on a league row.
  String? get competitionLabel {
    if (cupName == null) return null;
    return cupRoundLabel == null ? cupName : '$cupName · $cupRoundLabel';
  }
}

/// The season read as a calendar of real dates.
///
/// League rounds are Saturday afternoons; cup rounds are the midweek date in
/// the same week as the league round they sit beside. The two therefore share
/// a week instead of each consuming one, which is what lets a 38-match league
/// season carry two domestic cups (and, later, continental nights) without
/// running past the following summer.
///
/// The mapping is derived from the round list and the cup anchors, so it adds
/// no stored dates and every save — old or new — renders the same calendar.
class SeasonCalendar {
  SeasonCalendar._();

  /// The first Saturday of August: the opening weekend of the season. The
  /// calendar is anchored to a Saturday rather than to 1 August so matchdays
  /// stay on Saturdays whatever weekday the month starts on.
  static DateTime startOfSeason(int year) {
    var date = DateTime(year, 8, 1);
    while (date.weekday != DateTime.saturday) {
      date = date.add(const Duration(days: 1));
    }
    return date;
  }

  /// The date round [round] is played on. Kept for callers that only have a
  /// year and a round number (and for older saves); [season] models the
  /// packed calendar with cups on midweek dates.
  static DateTime dateOfRound(int year, int round) =>
      startOfSeason(year).add(Duration(days: 7 * round));

  /// The real date of [round] in [season]: Saturdays for league matchdays,
  /// Wednesdays for cup rounds.
  static DateTime dateOf(SeasonState season, int round) {
    final anchors = <int>{for (final cup in season.cups) ...cup.anchors};
    var leagueBefore = 0;
    final limit = round < season.rounds.length ? round : season.rounds.length;
    for (var i = 0; i < limit; i++) {
      if (!anchors.contains(i)) leagueBefore++;
    }
    final start = startOfSeason(season.currentYear);
    if (round > season.rounds.length) {
      // An injury return can land past the last fixture: keep ticking a week
      // per round rather than folding the extra weeks onto the final date.
      return start.add(
        Duration(days: 7 * leagueBefore + 7 * (round - season.rounds.length)),
      );
    }
    if (anchors.contains(round)) {
      // Midweek: the Wednesday before the next league weekend. A curtain-
      // raiser before the opening weekend sits in the previous July.
      final days = leagueBefore == 0 ? -3 : 7 * leagueBefore - 3;
      return start.add(Duration(days: days));
    }
    return start.add(Duration(days: 7 * leagueBefore));
  }

  /// Cup ties used to be shown four days before their slot; kept for any
  /// caller that still offsets a derived date (the winter-break marker does).
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
    final cupOfRound = <int, (CupState, int)>{};
    for (final cup in season.cups) {
      for (var k = 0; k < cup.anchors.length; k++) {
        cupOfRound[cup.anchors[k]] = (cup, k);
      }
    }

    for (var round = 0; round < season.rounds.length; round++) {
      final date = dateOf(season, round);
      final cupRound = cupOfRound[round];
      final cup = cupRound?.$1;
      final label =
          cupRound == null ? null : CupService.roundNameOf(season, cupRound.$2, cup: cup);

      if (round == season.winterBreakRound && cup == null) {
        // Midweek ahead of the paused round, so the list never runs backwards
        // in time, whichever row the round itself produces.
        entries.add(CalendarEntry(
          round: round,
          date: date.subtract(cupMidweekShift),
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
          cupName: cup?.name,
          cupRoundLabel: label,
          isCurrent: round == season.currentMatchday,
        ));
        continue;
      }

      if (cup != null && cup.byes[cupRound!.$2] == teamId) {
        entries.add(CalendarEntry(
          round: round,
          date: date,
          kind: CalendarEntryKind.bye,
          cupName: cup.name,
          cupRoundLabel: label,
          isCurrent: round == season.currentMatchday,
        ));
      } else if (cup != null &&
          season.fixturesForRound(round).isEmpty &&
          CupService.clubIsAlive(season, teamId, cup: cup)) {
        // The bracket draws a round only when the one before it is done, so
        // a round ahead is a date the club might play on — which is exactly
        // what the manager opens the calendar for.
        entries.add(CalendarEntry(
          round: round,
          date: date,
          kind: CalendarEntryKind.cupSlot,
          cupName: cup.name,
          cupRoundLabel: label,
          isCurrent: round == season.currentMatchday,
        ));
      } else if (cup == null && round == season.currentMatchday) {
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
