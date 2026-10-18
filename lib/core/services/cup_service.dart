import 'dart:math';

import '../models/cup.dart';
import '../models/fixture.dart';
import '../models/season.dart';

/// The national knockout cup: seeding, calendar anchoring and progression.
///
/// A cup round is one matchday in the merged schedule — it lives inside
/// `SeasonState.rounds` at an absolute position (its anchor), interleaved
/// between league matchdays like a midweek tie. Cup fixtures are tagged
/// `competition: 'cup'`, so nothing they do reaches the league table; the
/// league's own rounds stay exactly as [buildRounds] produced them.
///
/// Everything is deterministic: the draw is seeded from the league and year,
/// later rounds are built from the winners of the round before (draws are
/// broken by seeded penalties), and a save restored mid-cup replays the
/// same bracket because [progressCup] only ever derives state from played
/// fixtures plus the persisted [CupState].
class CupService {
  /// Draws the bracket and returns the cup it belongs to.
  ///
  /// Mutates [rounds] in place: one placeholder round is spliced in per cup
  /// round at its anchor (round 0's fixtures are drawn immediately, the
  /// others fill as the cup progresses). Call it before constructing the
  /// [SeasonState] so the returned cup can be passed straight into the
  /// constructor alongside the already-spliced rounds.
  ///
  /// [teamIds] must be every club of the league (the schedule's ids), since
  /// all of them enter the draw. Small leagues skip the cup entirely — a
  /// bracket of fewer than four clubs is not worth a season slot.
  static CupState? attachCup({
    required List<List<Fixture>> rounds,
    required List<String> teamIds,
    required String leagueId,
    required int currentYear,
    String cupName = 'National Cup',
  }) {
    if (teamIds.length < 4) return null;
    final leagueRounds = rounds.length;
    final bracketTies = _tiesPerRound(teamIds.length);
    final bracketRounds = bracketTies.length;
    // The cup needs calendar room: every bracket round lands between league
    // matchdays, never stacked on the opening day or the very end.
    if (leagueRounds < bracketRounds * 2) return null;

    final anchors = _anchorPositions(leagueRounds, bracketRounds);
    final cup = CupState(name: cupName, anchors: anchors, ties: bracketTies);

    final seed = '$leagueId:$currentYear:cup'.hashCode.abs();
    final ids = [...teamIds]..shuffle(Random(seed));

    for (final anchor in anchors) {
      rounds.insert(anchor, <Fixture>[]);
    }
    rounds[anchors[0]] = _drawRound(ids, cup, 0, anchors[0]);
    return cup;
  }

  /// Fills the next cup round once the one before it has fully completed.
  ///
  /// Call after every simulated or played matchday. Cheap, and idempotent:
  /// a round that already has fixtures (or a cup with nothing completed)
  /// returns doing nothing.
  ///
  /// Drawn cup ties are resolved at this point by seeded penalties: the
  /// scoreline stays an honest draw, but progression needs a winner to
  /// build the next round.
  static void progressCup(SeasonState season) {
    final cup = season.cup;
    if (cup == null) return;
    for (var k = 0; k < cup.anchors.length; k++) {
      final round = season.rounds[cup.anchors[k]];
      if (round.isEmpty) return; // should not happen for a filled round
      if (round.any((f) => !f.played)) return; // still in progress
      if (k + 1 >= cup.anchors.length) return; // bracket finished
      // The next cup round may already exist without having been played
      // (that keeps the loop a no-op across repeated calls after one fill).
      if (k + 1 < cup.anchors.length &&
          season.rounds[cup.anchors[k + 1]].isNotEmpty) {
        // Advance the scan to the round already drawn and stop filling
        // anything this pass; one round fills per completed matchday.
        continue;
      }
      final contenders = [
        for (final f in round) tieWinner(season, f),
        if (cup.byes[k] != null) cup.byes[k]!,
      ];
      season.rounds[cup.anchors[k + 1]] = _drawRound(contenders, cup, k + 1,
          cup.anchors[k + 1]);
      return;
    }
  }

  /// The id of the cup's winning club, or null when the cup is not finished
  /// (or was never attached).
  ///
  /// Normally a single final fixture decides it. An odd-contender bracket
  /// can reach the end with one match plus a bye; the bye team then feels
  /// short-changed sitting out the title match, so a seeded coin decides
  /// between the two finalists — rare, but fair instead of silent.
  static String? cupWinnerOf(SeasonState season) {
    final cup = season.cup;
    if (cup == null) return null;
    final finalRound = season.rounds[cup.anchors.last];
    if (finalRound.isEmpty) return null;
    if (finalRound.any((f) => !f.played)) return null;
    final matchWinner = tieWinner(season, finalRound.single);
    final bye = cup.byes[cup.anchors.length - 1];
    if (bye == null) return matchWinner;
    final seed =
        '${season.leagueId}:${season.currentYear}:cup-final-bye'
            .hashCode
            .abs();
    return Random(seed).nextBool() && bye != matchWinner
        ? bye
        : matchWinner;
  }

  /// Which bracket round is scheduled at the absolute [round] position, or
  /// -1 when that position is a league matchday.
  static int cupRoundIndexOf(SeasonState season, int round) {
    final cup = season.cup;
    if (cup == null) return -1;
    return cup.anchors.indexOf(round);
  }

  /// The human name of cup round [k] ('Quarter-finals', 'Final', …).
  ///
  /// Names come from the bracket shape recorded at the draw, so an undrawn
  /// future round still knows it will hold two ties or one.
  static String roundNameOf(SeasonState season, int k) {
    final cup = season.cup;
    if (cup == null || k < 0 || k >= cup.anchors.length) return 'Cup';
    if (k < cup.ties.length) return _nameForMatches(cup.ties[k]);
    // Older persisted cups predate [CupState.ties]; fall back to whatever
    // is drawn, where an empty round reads as the round of its anchor.
    return _nameForMatches(season.rounds[cup.anchors[k]].length);
  }

  /// True when the user's club is still alive in the cup. A club is only
  /// ever eliminated by LOSING a tie it attended, so survival is deduced by
  /// walking the bracket: any round it enters carries it forward while it
  /// keeps winning, an undrawn round ahead is undecided (alive), and it only
  /// fails to appear in a drawn round after being knocked out or taking a
  /// recorded bye.
  static bool clubIsAlive(SeasonState season, String teamId) {
    final cup = season.cup;
    if (cup == null) return false;
    for (var k = 0; k < cup.anchors.length; k++) {
      final round = season.rounds[cup.anchors[k]];
      if (round.isEmpty) return true; // not drawn yet: anything can happen
      if (cup.byes[k] == teamId) continue; // sat the round out by the draw
      final attended = round.any((f) => f.involves(teamId));
      if (!attended) continue; // not yet entered, or already knocked out
      if (round.any((f) => !f.played)) return true; // tie still to be played
      final winner =
          tieWinner(season, round.firstWhere((f) => f.involves(teamId)));
      if (winner != teamId) return false; // knocked out right here
    }
    // Walked the whole bracket: the cup is decided, so nobody is "alive".
    return false;
  }

  // ---------------------------------------------------------------------------

  /// Match counts per bracket round for [teams] entrants, in draw order.
  ///
  /// The contender chain is a ceil-halving (each odd level sheds one team to
  /// a bye), so this shape is fully known at the draw and never depends on
  /// results: 8 clubs -> [4, 2, 1], 20 -> [10, 5, 2, 1, 1]. Its length is
  /// the number of bracket rounds.
  static List<int> _tiesPerRound(int teams) {
    final ties = <int>[];
    var remaining = teams;
    while (remaining > 1) {
      final matches = remaining ~/ 2;
      ties.add(matches);
      remaining = matches + (remaining.isOdd ? 1 : 0);
    }
    return ties;
  }

  /// Absolute rounds-list positions, spread evenly between league matchdays.
  ///
  /// [leagueRounds] is the count BEFORE splicing; the inserted cup rounds
  /// shift later league rounds, and the `+index` below compensates exactly
  /// for the cups inserted before each position.
  static List<int> _anchorPositions(int leagueRounds, int bracketRounds) {
    return [
      for (var k = 0; k < bracketRounds; k++)
        ((k + 1) * leagueRounds) ~/ (bracketRounds + 1) + k,
    ];
  }

  /// Builds the fixtures for one cup round from [contenders] in bracket
  /// order: sequential pairs, alternating which side nominally hosts. An odd
  /// contender count means the trailing team takes a bye, which is recorded
  /// in [CupState.byes] so the next progression can repeat the fact.
  static List<Fixture> _drawRound(
    List<String> contenders,
    CupState cup,
    int cupRoundIndex,
    int anchor,
  ) {
    final fixtures = <Fixture>[];
    final pairs = contenders.length ~/ 2;
    for (var i = 0; i < pairs; i++) {
      final a = contenders[i * 2];
      final b = contenders[i * 2 + 1];
      final flip = i.isOdd;
      fixtures.add(Fixture(
        homeTeamId: flip ? b : a,
        awayTeamId: flip ? a : b,
        round: anchor,
        leg: 0,
        competition: 'cup',
      ));
    }
    if (contenders.length.isOdd) {
      cup.byes[cupRoundIndex] = contenders.last;
    }
    return fixtures;
  }

  /// The team that goes through a played tie. Draws go to seeded penalties,
  /// so the outcome is deterministic across restores — and it is the single
  /// source of truth the bracket, the board news and the full-time screen all
  /// read, so they can never tell the manager different stories.
  static String tieWinner(SeasonState season, Fixture fixture) {
    if (fixture.homeGoals != fixture.awayGoals) {
      return fixture.homeGoals > fixture.awayGoals
          ? fixture.homeTeamId
          : fixture.awayTeamId;
    }
    final seed =
        '${season.leagueId}:${season.currentYear}:cup-pens:'
                '${fixture.homeTeamId}:${fixture.awayTeamId}'
            .hashCode
            .abs();
    return Random(seed).nextBool() ? fixture.homeTeamId : fixture.awayTeamId;
  }

  /// The shootout line for a finished drawn cup tie, from [teamId]'s point of
  /// view — or null when the tie needs no deciding (a league fixture, or
  /// somebody won it in normal time).
  static ({String text, bool advanced})? shootoutNote({
    required SeasonState season,
    required Fixture tie,
    required String teamId,
    required int homeGoals,
    required int awayGoals,
  }) {
    if (tie.competition != 'cup' || homeGoals != awayGoals) return null;
    return tieWinner(season, tie) == teamId
        ? (text: 'Through on penalties', advanced: true)
        : (text: 'Knocked out on penalties', advanced: false);
  }

  static String _nameForMatches(int matches) {
    switch (matches) {
      case 1:
        return 'Final';
      case 2:
        return 'Semi-finals';
      case 4:
        return 'Quarter-finals';
      case 8:
        return 'Last 16';
      case 16:
        return 'Last 32';
      case 32:
        return 'Last 64';
      default:
        return 'Round of ${matches * 2}';
    }
  }
}
