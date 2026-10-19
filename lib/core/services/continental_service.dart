import 'dart:math';

import '../data/competition_catalog.dart';
import '../data/continental_catalog.dart';
import '../models/continental.dart';
import '../models/fixture.dart';
import '../models/season.dart';
import '../models/team.dart';

/// Continental football: a league phase whose fixtures are known at the draw,
/// then two-legged knockouts seeded from that table and a single-leg final.
///
/// The service only ever reads and writes `SeasonState.rounds`; the persisted
/// [ContinentalState] carries the anchors and the field, nothing else. That
/// keeps the table and the bracket rebuildable from the schedule itself, which
/// is the same contract the domestic cups follow.
class ContinentalService {
  ContinentalService._();

  /// Stage names of the knockout phase, in bracket order.
  static const List<String> _stageNames = [
    'Play-off round',
    'Round of 16',
    'Quarter-finals',
    'Semi-finals',
    'Final',
  ];

  /// The continental competition the manager's club qualifies for this
  /// season, or null when it qualifies for none.
  ///
  /// Season one has no table behind it, so the whole field is reputation.
  /// From the second season the manager's own finish decides which
  /// competition the club enters — top four into the Champions League, next
  /// two into the Europa League, seventh into the Conference League for a
  /// big league — and the club swaps into that field even when its
  /// reputation alone would not have put it there. Only a top-division club
  /// can qualify: a Championship side stays at home.
  static ContinentalRequest? buildRequest({
    required List<Team> teams,
    required String leagueId,
    required String userId,
    required int year,
    int? previousPosition,
    String? previousLeagueId,
  }) {
    final region = ContinentalCatalog.regionOf(leagueId);
    if (region == null) return null;
    final templates = ContinentalCatalog.competitionsOf(region);
    if (templates.isEmpty) return null;
    // Only the top flight of a country feeds continental football.
    final country = CompetitionCatalog.forLeague(leagueId);
    if (country == null || country.topLeague != leagueId) return null;

    final pool = [
      for (final team in teams)
        if (ContinentalCatalog.regionOf(team.leagueId) == region) team,
    ]..sort((a, b) {
        final byReputation = b.reputation.compareTo(a.reputation);
        return byReputation != 0 ? byReputation : a.id.compareTo(b.id);
      });
    if (pool.length < 8) return null;
    final ranked = [for (final team in pool) team.id];
    final userIndex = ranked.indexOf(userId);
    if (userIndex < 0) return null;

    final tier = _qualificationTier(
      templates: templates,
      teams: teams,
      leagueId: leagueId,
      previousPosition: previousPosition,
      previousLeagueId: previousLeagueId,
      userIndex: userIndex,
    );
    if (tier == null) return null;
    final template = templates[tier];

    // The field is the reputation slice for the tier, with the manager's club
    // swapped in for the weakest seed when its finish — not its reputation —
    // is what earned the place.
    final slices = <List<String>>[];
    var cursor = 0;
    for (final entry in templates) {
      if (cursor >= ranked.length) {
        slices.add(<String>[]);
        continue;
      }
      final end = min(cursor + entry.clubCount, ranked.length);
      slices.add(ranked.sublist(cursor, end));
      cursor = end;
    }
    for (final slice in slices) {
      slice.remove(userId);
    }
    final field = [...slices[tier]];
    for (final id in ranked) {
      if (field.length >= template.clubCount) break;
      if (!field.contains(id)) field.add(id);
    }
    if (field.length < 8) return null;
    if (!field.contains(userId)) {
      field.removeLast();
      field.add(userId);
    }

    final schedule = leaguePhaseSchedule(
      clubIds: field,
      games: template.leagueGames,
      competition: template.id,
      seed: '$leagueId:$year:${template.id}'.hashCode.abs(),
    );
    return ContinentalRequest(
      id: template.id,
      name: template.name,
      region: region,
      clubIds: field,
      leagueRounds: template.leagueGames,
      leagueSchedule: schedule,
    );
  }

  static int? _qualificationTier({
    required List<ContinentalTemplate> templates,
    required List<Team> teams,
    required String leagueId,
    required int? previousPosition,
    required String? previousLeagueId,
    required int userIndex,
  }) {
    if (previousPosition != null &&
        previousPosition > 0 &&
        previousLeagueId == leagueId) {
      final size = teams.where((t) => t.leagueId == leagueId).length;
      final big = size >= 10;
      if (previousPosition <= (big ? 4 : 2)) return 0;
      if (previousPosition <= (big ? 6 : 3)) {
        return templates.length > 1 ? 1 : null;
      }
      if (previousPosition <= (big ? 7 : 4)) {
        return templates.length > 2 ? 2 : null;
      }
      return null;
    }
    var cursor = 0;
    for (var tier = 0; tier < templates.length; tier++) {
      cursor += templates[tier].clubCount;
      if (userIndex < cursor) return tier;
    }
    return null;
  }

  /// The league-phase fixtures for a field, one matchday at a time.
  ///
  /// The circle method gives every club exactly one game per matchday against
  /// a fresh opponent — the same partial round-robin a real league phase uses,
  /// just without the seeding pots. The club order is shuffled by [seed] so a
  /// field's reputation ranking does not also decide its fixtures.
  static List<List<Fixture>> leaguePhaseSchedule({
    required List<String> clubIds,
    required int games,
    required String competition,
    required int seed,
  }) {
    final ids = [...clubIds]..shuffle(Random(seed));
    final n = ids.length;
    final schedule = <List<Fixture>>[];
    for (var round = 0; round < games && round < n - 1; round++) {
      final fixtures = <Fixture>[];
      for (var i = 0; i < n ~/ 2; i++) {
        final a = ids[i];
        final b = ids[n - 1 - i];
        final flip = (i + round).isOdd;
        fixtures.add(Fixture(
          homeTeamId: flip ? b : a,
          awayTeamId: flip ? a : b,
          round: 0,
          leg: 0,
          competition: competition,
        ));
      }
      schedule.add(fixtures);
      final held = ids.removeAt(1);
      ids.add(held);
    }
    return schedule;
  }

  /// Fills every knockout round that has become available.
  ///
  /// Idempotent: a round that is already drawn is left alone, so calling this
  /// after every matchday is safe. The league phase must be complete before
  /// the play-off round is seeded, and each knockout stage must be complete
  /// before the next is drawn.
  static void progress(SeasonState season) {
    for (final comp in season.continental) {
      _progressOne(season, comp);
    }
  }

  static void _progressOne(SeasonState season, ContinentalState comp) {
    final anchors = comp.knockoutAnchors;
    if (anchors.length < 9 || comp.leagueAnchors.isEmpty) return;
    if (!_leagueComplete(season, comp)) return;

    final table = tableOf(season, comp);
    if (table.length < 12) return;

    // The play-off round is the first thing drawn once the league phase ends.
    if (season.rounds[anchors[0]].isEmpty) {
      final playoff = <String>[
        for (var i = 8; i < min(24, table.length); i++) table[i].teamId,
      ];
      if (playoff.length.isOdd) playoff.removeLast();
      if (playoff.length < 2) return;
      final pairs = <(String, String)>[];
      var lo = 0;
      var hi = playoff.length - 1;
      while (lo < hi) {
        pairs.add((playoff[lo], playoff[hi])); // (better seed, worse seed)
        lo++;
        hi--;
      }
      _fillTwoLegged(season, comp, 0, pairs);
      return;
    }

    for (var stage = 0; stage < 4; stage++) {
      final leg1 = season.rounds[anchors[stage * 2]];
      final leg2 = season.rounds[anchors[stage * 2 + 1]];
      if (leg1.isEmpty || leg2.isEmpty) return;
      if (leg1.any((f) => !f.played) || leg2.any((f) => !f.played)) return;
      if (stage == 3) {
        // Semi-finals done: the single-leg final is played at the better
        // seed's nominal home.
        if (season.rounds[anchors[8]].isNotEmpty) return;
        final winners = _stageWinners(season, comp, stage);
        if (winners.length != 2) return;
        final home = _rankOf(table, winners[0]) <= _rankOf(table, winners[1])
            ? winners[0]
            : winners[1];
        final away = home == winners[0] ? winners[1] : winners[0];
        season.rounds[anchors[8]] = [
          Fixture(
            homeTeamId: home,
            awayTeamId: away,
            round: anchors[8],
            leg: 0,
            competition: comp.id,
          ),
        ];
        return;
      }
      if (season.rounds[anchors[(stage + 1) * 2]].isNotEmpty) continue;
      final winners = _stageWinners(season, comp, stage);
      if (winners.length < 2) return;
      final pairs = <(String, String)>[];
      if (stage == 0) {
        // The eight league-phase leaders meet the play-off winners, best
        // against worst.
        final field = <String>[
          for (var i = 0; i < min(8, table.length); i++) table[i].teamId,
          ...winners,
        ]..sort((a, b) => _rankOf(table, a).compareTo(_rankOf(table, b)));
        for (var i = 0; i < field.length ~/ 2; i++) {
          pairs.add((field[i], field[field.length - 1 - i]));
        }
      } else {
        // Later rounds keep the bracket order: adjacent ties meet.
        for (var i = 0; i + 1 < winners.length; i += 2) {
          pairs.add((winners[i], winners[i + 1]));
        }
      }
      if (pairs.isEmpty) return;
      _fillTwoLegged(season, comp, stage + 1, pairs);
      return;
    }
  }

  static void _fillTwoLegged(
    SeasonState season,
    ContinentalState comp,
    int stage,
    List<(String, String)> pairs,
  ) {
    final first = comp.knockoutAnchors[stage * 2];
    final second = comp.knockoutAnchors[stage * 2 + 1];
    // The better-seeded club hosts the second leg.
    season.rounds[first] = [
      for (final pair in pairs)
        Fixture(
          homeTeamId: pair.$2,
          awayTeamId: pair.$1,
          round: first,
          leg: 0,
          competition: comp.id,
        ),
    ];
    season.rounds[second] = [
      for (final pair in pairs)
        Fixture(
          homeTeamId: pair.$1,
          awayTeamId: pair.$2,
          round: second,
          leg: 1,
          competition: comp.id,
        ),
    ];
  }

  static List<String> _stageWinners(
    SeasonState season,
    ContinentalState comp,
    int stage,
  ) {
    final leg1 = season.rounds[comp.knockoutAnchors[stage * 2]];
    return [for (final fixture in leg1) tieWinner(season, comp, fixture)];
  }

  /// The club that wins the two-legged tie [fixture] belongs to, decided on
  /// aggregate and seeded penalties when the legs are level.
  ///
  /// A leg that is not yet paired (or not yet played) falls back to its own
  /// result, which keeps callers working mid-tie.
  static String tieWinner(
    SeasonState season,
    ContinentalState comp,
    Fixture fixture,
  ) {
    final index = comp.knockoutAnchors.indexOf(fixture.round);
    if (index < 0 || index >= 8) return _decideOne(season, comp, fixture);
    final stage = index ~/ 2;
    final otherAnchor =
        comp.knockoutAnchors[stage * 2 + (index.isEven ? 1 : 0)];
    if (otherAnchor >= season.rounds.length) {
      return _decideOne(season, comp, fixture);
    }
    final other = season.rounds[otherAnchor]
        .where((f) =>
            f.homeTeamId == fixture.awayTeamId &&
            f.awayTeamId == fixture.homeTeamId)
        .firstOrNull;
    if (other == null || !fixture.played || !other.played) {
      return _decideOne(season, comp, fixture);
    }
    final home = fixture.homeTeamId;
    final away = fixture.awayTeamId;
    final homeGoals = fixture.homeGoals + other.awayGoals;
    final awayGoals = fixture.awayGoals + other.homeGoals;
    if (homeGoals != awayGoals) return homeGoals > awayGoals ? home : away;
    return _penalties(season, comp, fixture);
  }

  static String _decideOne(
    SeasonState season,
    ContinentalState comp,
    Fixture fixture,
  ) {
    if (fixture.homeGoals != fixture.awayGoals) {
      return fixture.homeGoals > fixture.awayGoals
          ? fixture.homeTeamId
          : fixture.awayTeamId;
    }
    return _penalties(season, comp, fixture);
  }

  static String _penalties(
    SeasonState season,
    ContinentalState comp,
    Fixture fixture,
  ) {
    final seed = '${season.leagueId}:${season.currentYear}:${comp.id}:pens:'
            '${fixture.homeTeamId}:${fixture.awayTeamId}'
        .hashCode
        .abs();
    return Random(seed).nextBool() ? fixture.homeTeamId : fixture.awayTeamId;
  }

  static bool _leagueComplete(SeasonState season, ContinentalState comp) {
    for (final anchor in comp.leagueAnchors) {
      final round = season.rounds[anchor];
      if (round.isEmpty || round.any((f) => !f.played)) return false;
    }
    return true;
  }

  /// The league-phase table: points, goal difference, goals for, then the
  /// draw seed so the order never flickers between rebuilds.
  static List<LeagueStanding> tableOf(
    SeasonState season,
    ContinentalState comp,
  ) {
    final records = <String, LeagueRecord>{
      for (final id in comp.clubIds) id: LeagueRecord(),
    };
    for (final anchor in comp.leagueAnchors) {
      for (final fixture in season.rounds[anchor]) {
        if (!fixture.played) continue;
        final home = records[fixture.homeTeamId];
        final away = records[fixture.awayTeamId];
        if (home == null || away == null) continue;
        home.record(fixture.homeGoals, fixture.awayGoals);
        away.record(fixture.awayGoals, fixture.homeGoals);
      }
    }
    final seedOf = {
      for (var i = 0; i < comp.clubIds.length; i++) comp.clubIds[i]: i,
    };
    final sorted = records.entries.toList()
      ..sort((a, b) {
        final byPoints = b.value.points.compareTo(a.value.points);
        if (byPoints != 0) return byPoints;
        final byGd = b.value.goalDifference.compareTo(a.value.goalDifference);
        if (byGd != 0) return byGd;
        final byGoals = b.value.goalsFor.compareTo(a.value.goalsFor);
        if (byGoals != 0) return byGoals;
        return (seedOf[a.key] ?? 0).compareTo(seedOf[b.key] ?? 0);
      });
    return [
      for (var i = 0; i < sorted.length; i++)
        LeagueStanding(
          teamId: sorted[i].key,
          record: sorted[i].value,
          position: i + 1,
        ),
    ];
  }

  static int _rankOf(List<LeagueStanding> table, String teamId) {
    for (final row in table) {
      if (row.teamId == teamId) return row.position;
    }
    return 999;
  }

  /// The winner of the competition, or null while the final is unfinished.
  static String? winnerOf(SeasonState season, ContinentalState comp) {
    if (comp.knockoutAnchors.length < 9) return null;
    final finalRound = season.rounds[comp.knockoutAnchors[8]];
    if (finalRound.isEmpty || finalRound.any((f) => !f.played)) return null;
    return _decideOne(season, comp, finalRound.first);
  }

  /// How far [teamId] got: 'Winners', 'Runners-up', the stage it lost in, or
  /// null while its run is still alive.
  static String? clubExitLabel(
    SeasonState season,
    ContinentalState comp,
    String teamId,
  ) {
    if (!comp.clubIds.contains(teamId)) return null;
    if (winnerOf(season, comp) == teamId) return 'Winners';
    for (var stage = 4; stage >= 0; stage--) {
      final firstIndex = stage * 2;
      if (firstIndex >= comp.knockoutAnchors.length) continue;
      final leg1 = season.rounds[comp.knockoutAnchors[firstIndex]];
      final fixture = leg1.where((f) => f.involves(teamId)).firstOrNull;
      if (fixture == null) continue;
      if (stage == 4) {
        if (leg1.isNotEmpty && leg1.every((f) => f.played)) {
          return 'Runners-up';
        }
        return null;
      }
      final leg2 = season.rounds[comp.knockoutAnchors[firstIndex + 1]];
      if (leg1.any((f) => !f.played) ||
          leg2.isEmpty ||
          leg2.any((f) => !f.played)) {
        return null;
      }
      if (tieWinner(season, comp, fixture) != teamId) {
        return 'Out in the ${_stageNames[stage]}';
      }
      return null;
    }
    return null;
  }

  /// True while [teamId] can still win [comp].
  static bool isAlive(
    SeasonState season,
    ContinentalState comp,
    String teamId,
  ) {
    if (!comp.clubIds.contains(teamId)) return false;
    if (winnerOf(season, comp) != null) return false;
    return clubExitLabel(season, comp, teamId) == null;
  }

  /// The stage name, with the leg when the round is only half of a tie.
  static String stageLabel(int stage, int leg) {
    final name = stageName(stage);
    if (stage < 0 || stage >= _stageNames.length || stage >= 4) return name;
    return '$name · ${leg == 1 ? '1st leg' : '2nd leg'}';
  }

  /// The full-time note for a continental leg: the aggregate after a second
  /// leg, or a first-leg reminder that the tie is still live.
  static ({String text, bool advanced})? legNote({
    required SeasonState season,
    required ContinentalState comp,
    required Fixture fixture,
    required String teamId,
    required int homeGoals,
    required int awayGoals,
  }) {
    final index = comp.knockoutAnchors.indexOf(fixture.round);
    if (index < 0) return null;
    final userHome = fixture.homeTeamId == teamId;
    final userGoals = userHome ? homeGoals : awayGoals;
    final oppGoals = userHome ? awayGoals : homeGoals;
    String winnerOf(int a, int b) => a != b
        ? (a > b ? fixture.homeTeamId : fixture.awayTeamId)
        : _penalties(season, comp, fixture);

    if (index == 8) {
      // The final is a one-off: the note only matters when penalties decided
      // it, because the scoreline already says everything else.
      if (homeGoals != awayGoals) return null;
      final winner = winnerOf(homeGoals, awayGoals);
      return (
        text: winner == teamId
            ? 'Penalties! The ${comp.name} is yours.'
            : 'Beaten on penalties in the ${comp.name} final.',
        advanced: winner == teamId,
      );
    }

    final stage = index ~/ 2;
    final otherAnchor =
        comp.knockoutAnchors[stage * 2 + (index.isEven ? 1 : 0)];
    final other = season.rounds[otherAnchor]
        .where((f) =>
            f.homeTeamId == fixture.awayTeamId &&
            f.awayTeamId == fixture.homeTeamId)
        .firstOrNull;
    if (other == null || !other.played) {
      return (
        text: 'First leg: $userGoals–$oppGoals. The tie is still live.',
        advanced: false,
      );
    }
    final home = fixture.homeTeamId; // aggregate is a club-level total
    final homeAggregate = homeGoals + other.awayGoals;
    final awayAggregate = awayGoals + other.homeGoals;
    final userAggregate = home == teamId ? homeAggregate : awayAggregate;
    final oppAggregate = home == teamId ? awayAggregate : homeAggregate;
    final winner = winnerOf(homeAggregate, awayAggregate);
    final next = stage + 1;
    final where = next >= 4 ? 'the final' : 'the ${stageName(next)}';
    if (winner == teamId) {
      return (
        text: 'Aggregate $userAggregate–$oppAggregate — through to $where.',
        advanced: true,
      );
    }
    if (homeAggregate == awayAggregate) {
      return (
        text: 'Aggregate $userAggregate–$oppAggregate — '
            'beaten on penalties.',
        advanced: false,
      );
    }
    return (
      text: 'Aggregate $userAggregate–$oppAggregate — out of the '
          '${comp.name}.',
      advanced: false,
    );
  }

  /// The aggregate scoreline of the tie whose leg is [fixture], from that
  /// fixture's home/away point of view. A final, or a tie whose other leg is
  /// not drawn yet, reads back as the leg's own score.
  static ({int home, int away, bool penalties}) aggregateOf(
    SeasonState season,
    ContinentalState comp,
    Fixture fixture,
  ) {
    final index = comp.knockoutAnchors.indexOf(fixture.round);
    if (index < 0 || index >= 8) {
      return (
        home: fixture.homeGoals,
        away: fixture.awayGoals,
        penalties: fixture.played && fixture.homeGoals == fixture.awayGoals,
      );
    }
    final stage = index ~/ 2;
    final otherAnchor =
        comp.knockoutAnchors[stage * 2 + (index.isEven ? 1 : 0)];
    final other = season.rounds[otherAnchor]
        .where((f) =>
            f.homeTeamId == fixture.awayTeamId &&
            f.awayTeamId == fixture.homeTeamId)
        .firstOrNull;
    if (other == null) {
      return (
        home: fixture.homeGoals,
        away: fixture.awayGoals,
        penalties: false,
      );
    }
    final home = fixture.homeGoals + other.awayGoals;
    final away = fixture.awayGoals + other.homeGoals;
    return (home: home, away: away, penalties: home == away);
  }

  /// The stage name alone ('Quarter-finals'…).
  static String stageName(int stage) => stage >= 0 && stage < _stageNames.length
      ? _stageNames[stage]
      : 'Knockout round';

  /// The continental round at the absolute [round] position, with its label.
  static (ContinentalState, String)? labelAt(SeasonState season, int round) {
    for (final comp in season.continental) {
      final knockout = comp.knockoutAnchors.indexOf(round);
      if (knockout >= 0) {
        final stage = knockout ~/ 2;
        final leg = stage == 4 ? 1 : (knockout.isEven ? 1 : 2);
        return (comp, stageLabel(stage, leg));
      }
      final league = comp.leagueAnchors.indexOf(round);
      if (league >= 0) {
        return (comp, 'League phase · Matchday ${league + 1}');
      }
    }
    return null;
  }
}
