import 'dart:math';

import '../data/competition_catalog.dart';
import '../models/continental.dart';
import '../models/cup.dart';
import '../models/fixture.dart';
import '../models/season.dart';
import '../models/team.dart';

/// Domestic knockout competitions: seeding, calendar anchoring and
/// progression.
///
/// A cup round is one matchday in the merged schedule — it lives inside
/// `SeasonState.rounds` at an absolute position (its anchor), interleaved
/// between league matchdays like a midweek tie. Cup fixtures are tagged with
/// their competition id, so nothing they do reaches the league table; the
/// league's own rounds stay exactly as `buildRounds` produced them.
///
/// Two shapes are supported:
///
/// * **Legacy single cup** ([attachCup]) — every club of the user's league
///   enters one bracket. Kept for old saves and for tests that only need one
///   knockout competition.
/// * **Country cups** ([attachCompetitions]) — the real competitions of the
///   user's country, drawn from the catalog: a primary cup with every
///   division in the pool, secondary cups with smaller fields, and the
///   super-cup curtain-raiser. Large pools get a preliminary round so the
///   main bracket is a clean power of two (the real stage sizes: round of 64,
///   round of 32, round of 16, quarter-finals, semi-finals, final).
///
/// Everything is deterministic: the draw is seeded from the league, year and
/// competition id, later rounds are built from the winners of the round before
/// (draws are broken by seeded penalties), and a save restored mid-cup replays
/// the same bracket because progression only ever derives state from played
/// fixtures plus the persisted [CupState].
class CupService {
  /// Draws the legacy single cup and returns it.
  ///
  /// Mutates [rounds] in place: one placeholder round is spliced in per cup
  /// round at its anchor (round 0's fixtures are drawn immediately, the others
  /// fill as the cup progresses). Call it before constructing the
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

  /// Draws every domestic competition of the country [leagueId] belongs to.
  ///
  /// [teams] is the whole database (every division of every country): the cup
  /// pool is country-wide, so an FA Cup includes the Championship and League
  /// Two, not only the user's division. [championId] and [cupWinnerId] seed
  /// the super cup with last season's winners; when they are absent (a brand
  /// new career) the two strongest clubs of the top flight contest it.
  ///
  /// Returns the cups in catalog order (primary cup first). The caller stores
  /// them on `SeasonState.cups`.
  ///
  /// [continental] lists any continental competitions the same season should
  /// carry. They are scheduled in the same pass as the domestic cups — that
  /// is what keeps every absolute anchor valid — and their league-phase
  /// fixtures, which are known at the draw, are spliced in before returning.
  static List<CupState> attachCompetitions({
    required List<List<Fixture>> rounds,
    required List<Team> teams,
    required String leagueId,
    required int currentYear,
    String? championId,
    String? cupWinnerId,
    List<ContinentalRequest> continental = const [],
  }) {
    final catalog = CompetitionCatalog.forLeague(leagueId);
    if (catalog == null) {
      // A league outside the catalog (test stubs, continental pseudo-leagues)
      // still gets the legacy single cup over its own clubs, so no career is
      // ever left without a knockout competition. Continental requests only
      // exist for catalogued top flights, so there is nothing to place here.
      final leagueClubIds = [
        for (final team in teams)
          if (team.leagueId == leagueId) team.id,
      ];
      final legacy = attachCup(
        rounds: rounds,
        teamIds: leagueClubIds,
        leagueId: leagueId,
        currentYear: currentYear,
      );
      return legacy == null ? const [] : [legacy];
    }

    final pool =
        teams.where((t) => catalog.leagues.contains(t.leagueId)).toList();

    final plans = <_CupPlan>[];
    if (pool.length >= 4) {
      for (final template in catalog.cups) {
        final plan = _planFor(
          template: template,
          catalog: catalog,
          pool: pool,
          allTeams: teams,
          leagueId: leagueId,
          currentYear: currentYear,
          championId: championId,
          cupWinnerId: cupWinnerId,
        );
        if (plan != null) plans.add(plan);
      }
    }

    _placeOnCalendar(rounds, plans, continental);
    for (final request in continental) {
      for (var k = 0; k < request.leagueAnchors.length; k++) {
        rounds[request.leagueAnchors[k]] =
            List<Fixture>.of(request.leagueSchedule[k]);
      }
    }
    final drawn = <CupState>[];
    for (final plan in plans) {
      final cup = plan.cup;
      // A league with no rounds at all (a one-club division in the data) has
      // nowhere to splice a bracket: drop the cup instead of crashing.
      if (cup.anchors.isEmpty) continue;
      final ids = [...?cup.entrants[0]]..shuffle(
          Random('$leagueId:$currentYear:${cup.id}:round0'.hashCode.abs()),
        );
      if (ids.length < 2) continue;
      rounds[cup.anchors[0]] = _drawRound(ids, cup, 0, cup.anchors[0]);
      drawn.add(cup);
    }
    return drawn;
  }

  /// Fills the next round of every cup whose previous round has completed.
  ///
  /// Call after every simulated or played matchday. Cheap, and idempotent:
  /// a round that already has fixtures (or a cup with nothing completed)
  /// returns doing nothing.
  ///
  /// Drawn cup ties are resolved at this point by seeded penalties: the
  /// scoreline stays an honest draw, but progression needs a winner to
  /// build the next round.
  static void progressCup(SeasonState season) {
    for (final cup in season.cups) {
      _progressOne(season, cup);
    }
  }

  static void _progressOne(SeasonState season, CupState cup) {
    for (var k = 0; k < cup.anchors.length; k++) {
      final round = season.rounds[cup.anchors[k]];
      if (round.isEmpty) return; // should not happen for a filled round
      if (round.any((f) => !f.played)) return; // still in progress
      if (k + 1 >= cup.anchors.length) return; // bracket finished
      // The next cup round may already exist without having been played
      // (that keeps the loop a no-op across repeated calls after one fill).
      final nextRound = season.rounds[cup.anchors[k + 1]];
      if (nextRound.isNotEmpty) continue;
      final contenders = <String>[
        for (final f in round) tieWinner(season, f),
        if (cup.byes[k] != null) cup.byes[k]!,
        ...?cup.entrants[k + 1],
      ];
      season.rounds[cup.anchors[k + 1]] =
          _drawRound(contenders, cup, k + 1, cup.anchors[k + 1]);
      return;
    }
  }

  /// The id of the cup's winning club, or null when the cup is not finished
  /// (or was never attached).
  ///
  /// Normally a single final fixture decides it. An odd-contender bracket can
  /// reach the end with one match plus a bye; the bye team then feels
  /// short-changed sitting out the title match, so a seeded coin decides
  /// between the two finalists — rare, but fair instead of silent.
  static String? cupWinnerOf(SeasonState season, {CupState? cup}) {
    final target = cup ?? season.cup;
    if (target == null) return null;
    return winnerOf(season, target);
  }

  /// The winner of a specific competition, or null while it is undecided.
  static String? winnerOf(SeasonState season, CupState cup) {
    if (cup.anchors.isEmpty) return null;
    final finalRound = season.rounds[cup.anchors.last];
    if (finalRound.isEmpty) return null;
    if (finalRound.any((f) => !f.played)) return null;
    final matchWinner =
        finalRound.isEmpty ? null : tieWinner(season, finalRound.first);
    final bye = cup.byes[cup.anchors.length - 1];
    if (bye == null) return matchWinner;
    if (matchWinner == null) return bye;
    final seed =
        '${season.leagueId}:${season.currentYear}:cup-final-bye:${cup.id}'
            .hashCode
            .abs();
    return Random(seed).nextBool() && bye != matchWinner ? bye : matchWinner;
  }

  /// Whether [cup]'s final has been drawn and played.
  static bool isDecided(SeasonState season, CupState cup) {
    if (cup.anchors.isEmpty) return false;
    final round = season.rounds[cup.anchors.last];
    return round.isNotEmpty && round.every((f) => f.played);
  }

  /// The cup played at the absolute [round] position, or null on a league
  /// matchday.
  static CupState? cupAtRound(SeasonState season, int round) {
    for (final cup in season.cups) {
      if (cup.anchors.contains(round)) return cup;
    }
    return null;
  }

  /// Which bracket round of [cup] is scheduled at the absolute [round]
  /// position, or -1 when that position belongs to another competition.
  static int cupRoundIndexOf(SeasonState season, int round, {CupState? cup}) {
    final target = cup ?? cupAtRound(season, round);
    if (target == null) return -1;
    return target.anchors.indexOf(round);
  }

  /// The human name of cup round [k] ('Quarter-finals', 'Final', …).
  ///
  /// New competitions carry their real stage names on [CupState.roundNames];
  /// older saves fall back to the bracket shape recorded at the draw.
  static String roundNameOf(SeasonState season, int k, {CupState? cup}) {
    final target = cup ?? season.cup;
    if (target == null || k < 0 || k >= target.anchors.length) return 'Cup';
    if (k < target.roundNames.length) return target.roundNames[k];
    if (k < target.ties.length) return _nameForMatches(target.ties[k]);
    // Older persisted cups predate [CupState.ties]; fall back to whatever
    // is drawn, where an empty round reads as the round of its anchor.
    return _nameForMatches(season.rounds[target.anchors[k]].length);
  }

  /// True when the user's club is still alive in [cup] (the primary cup by
  /// default). A club is only ever eliminated by LOSING a tie it attended, so
  /// survival is deduced by walking the bracket: any round it enters carries
  /// it forward while it keeps winning, an undrawn round ahead is undecided
  /// (alive), and it only fails to appear in a drawn round after being
  /// knocked out or taking a recorded bye.
  static bool clubIsAlive(SeasonState season, String teamId, {CupState? cup}) {
    final target = cup ?? season.cup;
    if (target == null) return false;
    for (var k = 0; k < target.anchors.length; k++) {
      final round = season.rounds[target.anchors[k]];
      if (round.isEmpty) return true; // not drawn yet: anything can happen
      if (target.byes[k] == teamId) continue; // sat the round out by the draw
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

  /// How far the club got in [cup]: 'Winners', 'Runners-up', the round it
  /// lost in, or null when it never entered / the bracket is still live.
  static String? clubExitLabel(SeasonState season, String teamId,
      {CupState? cup}) {
    final target = cup ?? season.cup;
    if (target == null) return null;
    if (clubIsAlive(season, teamId, cup: target)) return null;
    final winner = winnerOf(season, target);
    if (winner == teamId) return 'Winners';
    for (var k = target.anchors.length - 1; k >= 0; k--) {
      final round = season.rounds[target.anchors[k]];
      final tie = round.where((f) => f.involves(teamId)).firstOrNull;
      if (tie == null) continue;
      if (!tie.played) return null;
      final last = k == target.anchors.length - 1;
      if (last) return 'Runners-up';
      return 'Out in the ${roundNameOf(season, k, cup: target)}';
    }
    return null;
  }

  // -------------------------------------------------------------------------

  /// Builds the plan for one template: the entrant list, bracket shape,
  /// real stage names and the competition state (anchors are filled after
  /// the whole calendar is scheduled).
  static _CupPlan? _planFor({
    required CupTemplate template,
    required CountryCompetitions catalog,
    required List<Team> pool,
    required List<Team> allTeams,
    required String leagueId,
    required int currentYear,
    String? championId,
    String? cupWinnerId,
  }) {
    if (template.isSuperCup) {
      return _superCupPlan(
        template: template,
        catalog: catalog,
        allTeams: allTeams,
        leagueId: leagueId,
        currentYear: currentYear,
        championId: championId,
        cupWinnerId: cupWinnerId,
      );
    }

    final sorted = [...pool]..sort((a, b) {
        final byReputation = b.reputation.compareTo(a.reputation);
        return byReputation != 0 ? byReputation : a.id.compareTo(b.id);
      });

    var clubs = sorted;
    var field = _largestPowerOfTwo(sorted.length).clamp(4, 64);
    if (template.fieldSize != null) {
      final invited = min(template.fieldSize!, sorted.length);
      field = _largestPowerOfTwo(invited).clamp(4, 64);
      clubs = sorted.take(field).toList();
      if (clubs.length < 4) return null;
      // A secondary cup is a straight knockout over its invited field.
      final entrants = {
        0: [for (final team in clubs) team.id]..shuffle(
            Random('$leagueId:$currentYear:${template.id}'.hashCode.abs())),
      };
      return _buildPlan(
        template: template,
        entrants: entrants,
        field: clubs.length,
        hasPreliminary: false,
      );
    }

    if (clubs.length < 4) return null;
    if (clubs.length == field) {
      final entrants = {
        0: [for (final team in clubs) team.id]..shuffle(
            Random('$leagueId:$currentYear:${template.id}'.hashCode.abs())),
      };
      return _buildPlan(
        template: template,
        entrants: entrants,
        field: field,
        hasPreliminary: false,
      );
    }

    // A preliminary round trims the field to a clean power of two. The
    // bottom `2 * (n - field)` clubs play it; the best `2 * field - n`
    // clubs join the main bracket, exactly like the top flight entering the
    // real round of 64.
    final preliminaryCount = 2 * (clubs.length - field);
    final bottom = clubs.sublist(clubs.length - preliminaryCount);
    final top = clubs.sublist(0, 2 * field - clubs.length);
    if (bottom.length.isOdd || top.isEmpty) return null;
    final seed = '$leagueId:$currentYear:${template.id}'.hashCode.abs();
    final rng = Random(seed);
    final entrants = {
      0: [for (final team in bottom) team.id]..shuffle(rng),
      1: [for (final team in top) team.id]..shuffle(rng),
    };
    return _buildPlan(
      template: template,
      entrants: entrants,
      field: field,
      hasPreliminary: true,
    );
  }

  static _CupPlan? _superCupPlan({
    required CupTemplate template,
    required CountryCompetitions catalog,
    required List<Team> allTeams,
    required String leagueId,
    required int currentYear,
    String? championId,
    String? cupWinnerId,
  }) {
    final top = allTeams.where((t) => t.leagueId == catalog.topLeague).toList()
      ..sort((a, b) {
        final byReputation = b.reputation.compareTo(a.reputation);
        return byReputation != 0 ? byReputation : a.id.compareTo(b.id);
      });
    if (top.length < 2) return null;

    var champion = championId;
    var cupWinner = cupWinnerId;
    if (champion == null || champion == cupWinner) {
      champion = top.first.id;
    }
    if (cupWinner == null || cupWinner == champion) {
      cupWinner = top.firstWhere((t) => t.id != champion).id;
    }
    if (champion == cupWinner) return null;
    return _buildPlan(
      template: template,
      entrants: {
        0: [champion, cupWinner],
      },
      field: 2,
      hasPreliminary: false,
    );
  }

  static _CupPlan? _buildPlan({
    required CupTemplate template,
    required Map<int, List<String>> entrants,
    required int field,
    required bool hasPreliminary,
  }) {
    final mainRounds = _log2(field);
    final totalRounds = mainRounds + (hasPreliminary ? 1 : 0);
    final ties = <int>[];
    var contenders = (entrants[0] ?? const []).length;
    for (var k = 0; k < totalRounds; k++) {
      if (k > 0) contenders += (entrants[k] ?? const []).length;
      final matches = contenders ~/ 2;
      if (matches == 0) return null;
      ties.add(matches);
      contenders = matches + (contenders.isOdd ? 1 : 0);
    }
    if (ties.last != 1) return null;

    final names = template.roundNames ??
        [
          if (hasPreliminary) 'Preliminary round',
          ..._stageNames(field),
        ];
    if (names.length != totalRounds) {
      // A template that names fewer rounds than its bracket has is a data
      // bug, not a reason to lose the cup: fall back to stage names.
      return _CupPlan(
        cup: CupState(
          id: template.id,
          name: template.name,
          kind: template.kind,
          competition: template.id,
          anchors: <int>[],
          ties: ties,
          entrants: entrants,
          roundNames: [
            if (hasPreliminary) 'Preliminary round',
            ..._stageNames(field),
          ],
          byes: <int, String>{},
        ),
      );
    }
    return _CupPlan(
      cup: CupState(
        id: template.id,
        name: template.name,
        kind: template.kind,
        competition: template.id,
        anchors: <int>[],
        ties: ties,
        entrants: entrants,
        roundNames: names,
        byes: <int, String>{},
      ),
    );
  }

  /// Assigns a calendar gap to every cup round and splices the anchors in.
  ///
  /// A gap is the space after league round `g - 1` (gap 0 is before the
  /// opening weekend). Cup rounds are spread through the season; two
  /// competitions never share a gap, so no week carries two knockout ties.
  /// The super cup takes gap 0 as the curtain-raiser.
  ///
  /// Continental rounds are placed in the same pass, in gaps no domestic cup
  /// claimed, so a European night never lands in the same week as a cup tie.
  /// Their league-phase fixtures are copied in by the caller once the whole
  /// insertion is done.
  static void _placeOnCalendar(
    List<List<Fixture>> rounds,
    List<_CupPlan> plans,
    List<ContinentalRequest> continental,
  ) {
    final leagueRounds = rounds.length;
    if (leagueRounds == 0) return;
    final occupied = <int>{};
    final gapOf = <_CupPlan, List<int>>{};
    for (final plan in plans) {
      final cup = plan.cup;
      final count = cup.ties.length;
      final gaps = <int>[];
      if (cup.kind == CupKind.superCup) {
        // One match before the league starts, the way a real super cup opens
        // the season.
        gaps.add(0);
        occupied.add(0);
        gapOf[plan] = gaps;
        continue;
      }
      for (var k = 0; k < count; k++) {
        // The national cup final is the last knockout date of the season:
        // after the league has finished, the way a real cup final closes the
        // campaign. The secondary cup keeps the evenly spread dates (its
        // final traditionally lands in the winter/spring).
        var target = cup.kind == CupKind.national && k == count - 1
            ? leagueRounds
            : ((k + 1) * leagueRounds) ~/ (count + 1);
        target = target.clamp(1, leagueRounds);
        var guard = 0;
        while (occupied.contains(target) && guard < leagueRounds * 2) {
          target++;
          if (target > leagueRounds) target = 1;
          guard++;
        }
        occupied.add(target);
        gaps.add(target);
      }
      gapOf[plan] = gaps;
    }

    // Continental rounds: one midweek per competition round, spread evenly
    // through the weeks the domestic cups did not take.
    final continentalGaps = <ContinentalRequest, List<int>>{};
    for (final request in continental) {
      final count = request.leagueRounds + 9;
      final gaps = <int>[];
      for (var k = 0; k < count; k++) {
        var target = ((k + 1) * leagueRounds) ~/ (count + 1);
        target = target.clamp(1, leagueRounds);
        var guard = 0;
        while (occupied.contains(target) && guard < leagueRounds * 2) {
          target++;
          if (target > leagueRounds) target = 1;
          guard++;
        }
        occupied.add(target);
        gaps.add(target);
      }
      continentalGaps[request] = gaps;
    }

    final gapCounts = <int, int>{};
    for (final entry in gapOf.entries) {
      for (final gap in entry.value) {
        gapCounts[gap] = (gapCounts[gap] ?? 0) + 1;
      }
    }
    for (final entry in continentalGaps.entries) {
      for (final gap in entry.value) {
        gapCounts[gap] = (gapCounts[gap] ?? 0) + 1;
      }
    }
    final sortedGaps = gapCounts.keys.toList()..sort();
    final gapStart = <int, int>{};
    var running = 0;
    for (final gap in sortedGaps) {
      gapStart[gap] = gap + running;
      running += gapCounts[gap]!;
    }

    final nextInGap = <int, int>{};
    for (final plan in plans) {
      final cup = plan.cup;
      final anchors = <int>[];
      for (final gap in gapOf[plan]!) {
        final index = nextInGap[gap] ?? 0;
        nextInGap[gap] = index + 1;
        anchors.add(gapStart[gap]! + index);
      }
      cup.anchors.addAll(anchors);
    }
    for (final request in continental) {
      final anchors = <int>[];
      for (final gap in continentalGaps[request]!) {
        final index = nextInGap[gap] ?? 0;
        nextInGap[gap] = index + 1;
        anchors.add(gapStart[gap]! + index);
      }
      request.leagueAnchors
        ..clear()
        ..addAll(anchors.take(request.leagueRounds));
      request.knockoutAnchors
        ..clear()
        ..addAll(anchors.skip(request.leagueRounds));
    }

    final allAnchors = <int>[
      for (final plan in plans) ...plan.cup.anchors,
      for (final request in continental) ...[
        ...request.leagueAnchors,
        ...request.knockoutAnchors,
      ],
    ]..sort();
    for (final anchor in allAnchors) {
      rounds.insert(anchor, <Fixture>[]);
    }
  }

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
        competition: cup.competition,
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
    final seed = '${season.leagueId}:${season.currentYear}:cup-pens:'
            '${fixture.homeTeamId}:${fixture.awayTeamId}'
        .hashCode
        .abs();
    return Random(seed).nextBool() ? fixture.homeTeamId : fixture.awayTeamId;
  }

  /// The shootout line for a finished drawn cup tie, from [teamId]'s point of
  /// view — or null when the tie needs no deciding (a league fixture, a
  /// continental leg, or somebody won it in normal time).
  static ({String text, bool advanced})? shootoutNote({
    required SeasonState season,
    required Fixture tie,
    required String teamId,
    required int homeGoals,
    required int awayGoals,
  }) {
    if (tie.competition == 'league' || homeGoals != awayGoals) return null;
    // Only a domestic cup tie is decided by a shootout at this point:
    // continental legs ride the aggregate, so the note must never speak for
    // one even when the competition id has never been a cup.
    final domestic = season.cups.any((cup) => cup.anchors.contains(tie.round));
    if (!domestic) return null;
    return tieWinner(season, tie) == teamId
        ? (text: 'Through on penalties', advanced: true)
        : (text: 'Knocked out on penalties', advanced: false);
  }

  /// The real stage name for a main bracket of [field] clubs.
  static List<String> _stageNames(int field) {
    final names = <String>[];
    var clubs = field;
    while (clubs >= 2) {
      names.add(_stageNameForClubs(clubs));
      clubs ~/= 2;
    }
    return names;
  }

  static String _stageNameForClubs(int clubs) {
    switch (clubs) {
      case 2:
        return 'Final';
      case 4:
        return 'Semi-finals';
      case 8:
        return 'Quarter-finals';
      case 16:
        return 'Round of 16';
      case 32:
        return 'Round of 32';
      case 64:
        return 'Round of 64';
      default:
        return 'Round of $clubs';
    }
  }

  static int _largestPowerOfTwo(int value) {
    var power = 1;
    while (power * 2 <= value) {
      power *= 2;
    }
    return power;
  }

  static int _log2(int value) {
    var power = 0;
    var v = value;
    while (v > 1) {
      v ~/= 2;
      power++;
    }
    return power;
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

/// A competition about to be placed on the calendar: its persisted state
/// (anchors empty until scheduling) and the shape facts the scheduler needs.
class _CupPlan {
  _CupPlan({required this.cup});

  final CupState cup;
}
