import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/models/fixture.dart';
import '../core/models/manager.dart';
import '../core/models/match.dart';
import '../core/models/player.dart';
import '../core/models/season.dart';
import '../core/models/team.dart';
import '../core/models/tactics.dart';
import '../core/models/youth_player.dart';
import '../core/services/financial_service.dart';
import '../core/services/match_simulator_service.dart';
import '../core/services/save_service.dart';
import 'data_providers.dart';

/// A complete active career: manager, club, season, and tactics.
class CareerSession {
  CareerSession({
    required this.manager,
    required this.team,
    required this.season,
    this.tactic = const Tactic(),
    List<int>? startXI,
  }) : startXI = startXI ?? [];

  final Manager manager;
  final Team team;
  final SeasonState season;
  Tactic tactic;

  /// Player ids of the manager's chosen starting XI (tactics screen).
  List<int> startXI;

  /// The user's club results this season (last 10), used for the form guide.
  final List<int> userResults = [];

  /// Youth academy prospects (separate from Team.squad, which is first-team).
  final List<YouthPlayer> youthPlayers = [];

  /// `Map<String, int>` get standings -> see [season].
  Map<String, int> get standings => season.standings;
}

/// null = no active career.
final careerSessionProvider = StateProvider<CareerSession?>((ref) => null);

/// Outcome of the most recent played match, for the Home screen.
final lastMatchResultProvider = StateProvider<MatchResult?>((ref) => null);

/// Shortlisted market player ids (persisted in the career blob).
final shortlistProvider = StateProvider<Set<int>>((ref) => {});

/// Outgoing offers made by the user (persisted in the career blob).
/// Each entry: playerId, playerName, fee, wage, askingFee, status, date.
final transferOffersProvider =
    StateProvider<List<Map<String, dynamic>>>((ref) => []);

/// Named saved tactics: [{'name': String, 'tactic': Tactic-as-json}].
final savedTacticsProvider =
    StateProvider<List<Map<String, dynamic>>>((ref) => []);

/// Key under which career-only data (no dedicated Hive adapter) is stored in
/// the save meta box: youth academy, form history, starting XI, shortlist,
/// transfer offers and saved tactics.
const String _careerMetaKey = 'career_blob';

/// Creates a new career from the selected team and manager identity.
void startNewCareer(
  WidgetRef ref, {
  required Manager manager,
  required Team team,
}) {
  final db = ref.read(playerDatabaseProvider).valueOrNull;
  final leagueRivals = db == null
      ? <Team>[]
      : db.teams.where((t) => t.leagueId == team.leagueId).toList();
  // A real double round-robin: one round list per matchday, so a 20-club
  // league plays 38 matchdays instead of the N-1 the old flat list implied.
  final rounds = buildRounds(
    [for (final t in leagueRivals) t.id],
    rng: Random(),
  );

  final season = SeasonState(
    leagueId: team.leagueId,
    currentMatchday: 0,
    currentYear: DateTime.now().year,
    isPreSeason: false,
    isWinterBreak: false,
    records: {for (final t in leagueRivals) t.id: LeagueRecord()},
    rounds: rounds,
  );
  final session = CareerSession(manager: manager, team: team, season: season);
  ref.read(careerSessionProvider.notifier).state = session;
  // Reset career-only state for the fresh save.
  ref.read(shortlistProvider.notifier).state = {};
  ref.read(transferOffersProvider.notifier).state = [];
  ref.read(savedTacticsProvider.notifier).state = [];
  _persist(ref, session);
}

/// Persists the current session through the existing SaveService.
///
/// Fire-and-forget on the hot path (match results, squad changes); failures
/// are logged instead of silently swallowed so save problems are diagnosable.
void _persist(WidgetRef ref, CareerSession session) {
  unawaited(saveCareerNow(ref));
}

/// Explicit, awaitable save of the entire career.
///
/// Returns `true` when everything (manager, team, season and the career blob)
/// reached disk. Used by the manual "Save career" action in Settings and by
/// the automatic persistence hooks.
Future<bool> saveCareerNow(WidgetRef ref) async {
  final session = ref.read(careerSessionProvider);
  if (session == null) return false;
  try {
    final save = SaveService();
    await save.saveManager(session.manager);
    await save.saveTeam(session.team);
    await save.saveSeason(session.season);
    await save.saveJson(_careerMetaKey, {
      'youthPlayers': [for (final y in session.youthPlayers) y.toJson()],
      'userResults': List<int>.from(session.userResults),
      'startXI': List<int>.from(session.startXI),
      'shortlist': ref.read(shortlistProvider).toList(),
      'transferOffers': ref.read(transferOffersProvider),
      'savedTactics': ref.read(savedTacticsProvider),
    });
    // A save now exists: the main menu must show "Continue Career".
    ref.invalidate(hasSaveProvider);
    return true;
  } catch (e, st) {
    debugPrint('[SAVE] Career save failed: $e');
    debugPrintStack(stackTrace: st, maxFrames: 12);
    return false;
  }
}

/// Attempts to restore a saved career at startup.
/// Returns true when a career was restored.
Future<bool> tryRestoreCareer(WidgetRef ref) async {
  try {
    final manager = await SaveService().loadManager();
    final team = await SaveService().loadTeam(manager?.teamId ?? '');
    final savedSeason = await SaveService().loadSeason();
    if (manager == null || team == null || savedSeason == null) return false;

    final season = migrateSeasonSchedule(
      savedSeason,
      team,
      ref.read(playerDatabaseProvider).valueOrNull,
    );

    final session = CareerSession(manager: manager, team: team, season: season);

    final blob = await SaveService().loadJson(_careerMetaKey);
    if (blob != null) {
      final youth = blob['youthPlayers'];
      if (youth is List) {
        for (final raw in youth) {
          if (raw is Map) {
            session.youthPlayers
                .add(YouthPlayer.fromJson(Map<String, dynamic>.from(raw)));
          }
        }
      }
      final results = blob['userResults'];
      if (results is List) {
        session.userResults.addAll(results.whereType<int>());
      }
      final xi = blob['startXI'];
      if (xi is List) {
        session.startXI.addAll(xi.whereType<int>());
      }
      final shortlist = blob['shortlist'];
      if (shortlist is List) {
        ref.read(shortlistProvider.notifier).state =
            shortlist.whereType<int>().toSet();
      }
      final offers = blob['transferOffers'];
      if (offers is List) {
        ref.read(transferOffersProvider.notifier).state = [
          for (final o in offers)
            if (o is Map) Map<String, dynamic>.from(o),
        ];
      }
      final tactics = blob['savedTactics'];
      if (tactics is List) {
        ref.read(savedTacticsProvider.notifier).state = [
          for (final t in tactics)
            if (t is Map) Map<String, dynamic>.from(t),
        ];
      }
    }

    ref.read(careerSessionProvider.notifier).state = session;
    return true;
  } catch (e, st) {
    debugPrint('[SAVE] Career restore failed: $e');
    debugPrintStack(stackTrace: st, maxFrames: 12);
    return false;
  }
}

/// Rebuilds a real schedule for a schema v1 save.
///
/// v1 stored a flat, shuffled list of "home|away" strings with no round
/// structure, so it cannot say who the user was playing in any given matchday.
/// Rather than resurrect a schedule that produces arbitrary opponents, a new
/// round-robin is generated. Results already banked in [SeasonState.records]
/// are kept; the old points map is only used to recover the club set.
///
/// Public so the migration can be exercised without a widget tree.
SeasonState migrateSeasonSchedule(
  SeasonState season,
  Team team,
  PlayerDatabase? db,
) {
  if (season.rounds.isNotEmpty) return season;

  final rivals = db == null
      ? <Team>[]
      : db.teams.where((t) => t.leagueId == team.leagueId).toList();
  if (rivals.length < 2) return season;

  final rounds = buildRounds([for (final t in rivals) t.id], rng: Random(7));
  debugPrint('[SAVE] Migrated a schema v1 save: rebuilt ${rounds.length} '
      'matchdays for ${rivals.length} clubs (had '
      '${season.legacyFixturePairs.length} ungrouped pairs).');

  return SeasonState(
    leagueId: season.leagueId,
    // A v1 counter could exceed the new schedule length; clamp so the season
    // is not born already finished.
    currentMatchday: season.currentMatchday.clamp(0, rounds.length),
    currentYear: season.currentYear,
    isPreSeason: season.isPreSeason,
    isWinterBreak: false,
    records: season.records.isEmpty
        ? {for (final t in rivals) t.id: LeagueRecord()}
        : season.records,
    rounds: rounds,
  );
}

/// True when a save file exists (used by Main Menu's Continue button).
///
/// Invalidated after every successful [saveCareerNow] so a freshly created
/// career immediately shows the Continue option.
final hasSaveProvider = FutureProvider<bool>((ref) async {
  try {
    final manager = await SaveService().loadManager();
    return manager != null;
  } catch (e) {
    debugPrint('[SAVE] hasSave check failed: $e');
    return false;
  }
});

/// Applies a played match to the season.
///
/// Home and away now come from the fixture rather than from the caller, which
/// is what stops gate receipts being credited on away matches. Every other
/// fixture in the same round is then simulated, so the league table actually
/// moves instead of only the user's club and its opponent gaining points.
void applyMatchResult(WidgetRef ref, MatchResult result) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return;

  final season = session.season;
  final round = season.currentMatchday;
  final fixture = season.userFixtureForRound(round, session.team.id);

  // An away fixture (or a restored save with no schedule) falls back to home,
  // which only affects the label: the scoreline is attributed by the fixture.
  final userIsHome = fixture?.isHomeFor(session.team.id) ?? true;
  final userGoals = userIsHome ? result.homeGoals : result.awayGoals;
  final oppGoals = userIsHome ? result.awayGoals : result.homeGoals;
  final points = userGoals > oppGoals ? 3 : (userGoals == oppGoals ? 1 : 0);

  session.userResults.add(points);
  if (session.userResults.length > 10) session.userResults.removeAt(0);

  if (fixture != null && !fixture.played) {
    fixture.record(result.homeGoals, result.awayGoals);
    _applyResultToRecords(season, fixture);
  }

  // Everything else in the round, so rivals move too.
  _simulateRemainingFixtures(ref, session, round);

  session.team.matchesPlayed += 1;
  session.team.goalsFor += userGoals;
  session.team.goalsAgainst += oppGoals;
  if (points == 3) {
    session.team.wins += 1;
  } else if (points == 1) {
    session.team.draws += 1;
  } else {
    session.team.losses += 1;
  }

  final advanced = round + 1;
  final updatedSeason = SeasonState(
    leagueId: season.leagueId,
    currentMatchday: advanced,
    currentYear: season.currentYear,
    isPreSeason: false,
    // The league pauses at the midpoint; the manager resumes from Home.
    isWinterBreak: advanced == season.winterBreakRound,
    records: season.records,
    rounds: season.rounds,
  );

  final updated = _rebuildSession(session, updatedSeason);
  updated.team.points = season.records[session.team.id]?.points ?? 0;
  // Position comes from the ordered table, which ranks the club itself
  // rather than a points value, so tied clubs no longer alias.
  updated.team.leaguePosition = updatedSeason.positionOf(session.team.id);

  // Gate receipts are credited on home games only.
  if (userIsHome) {
    final gate = FinancialService().estimateGateReceipts(session.team);
    session.team.revenue += gate;
    session.team.budget += gate.round();
  }

  ref.read(careerSessionProvider.notifier).state = updated;
  _persist(ref, updated);
}

/// Rebuilds the immutable session around a new [SeasonState], carrying every
/// piece of career state across.
///
/// The academy list used to be dropped here, which silently emptied the youth
/// academy after every single match.
CareerSession _rebuildSession(CareerSession session, SeasonState season) {
  final updated = CareerSession(
    manager: session.manager,
    team: session.team,
    season: season,
    tactic: session.tactic,
    startXI: session.startXI,
  );
  updated.userResults.addAll(session.userResults);
  updated.youthPlayers.addAll(session.youthPlayers);
  return updated;
}

/// Folds a played fixture into both clubs' league records.
void _applyResultToRecords(SeasonState season, Fixture fixture) {
  final records = season.records;
  final home = records.putIfAbsent(fixture.homeTeamId, LeagueRecord.new);
  final away = records.putIfAbsent(fixture.awayTeamId, LeagueRecord.new);
  home.record(fixture.homeGoals, fixture.awayGoals);
  away.record(fixture.awayGoals, fixture.homeGoals);
}

/// Simulates every fixture in [round] that has not been played yet.
///
/// This is what makes the table move: without it only the user's club and its
/// opponent ever gained points, and every other club sat on zero.
///
/// The RNG is seeded from the league, year and round rather than left
/// wall-clock random, so a save restored mid-round produces the same rival
/// results it would have produced had it never been closed.
void simulateRound(
  SeasonState season,
  int round, {
  Map<String, double> strengths = const {},
}) {
  final pending =
      season.fixturesForRound(round).where((f) => !f.played).toList();
  if (pending.isEmpty) return;

  final seed = '${season.leagueId}:${season.currentYear}:$round'.hashCode.abs();
  final rng = Random(seed);
  final sim = MatchSimulatorService(rng: rng);

  for (final fixture in pending) {
    final (homeGoals, awayGoals) = sim.simulateScore(
      homeStrength: strengths[fixture.homeTeamId] ?? 60.0,
      awayStrength: strengths[fixture.awayTeamId] ?? 60.0,
      rng: rng,
    );
    fixture.record(homeGoals, awayGoals);
    _applyResultToRecords(season, fixture);
  }
}

/// Simulates the rest of the current round using real squad strengths.
void _simulateRemainingFixtures(
  WidgetRef ref,
  CareerSession session,
  int round,
) {
  final db = ref.read(playerDatabaseProvider).valueOrNull;
  final strengths = <String, double>{
    if (db != null)
      for (final t in db.teams) t.id: _squadStrength(t),
  };
  simulateRound(session.season, round, strengths: strengths);
}

/// Average squad rating, used as the strength input for rival fixtures.
double _squadStrength(Team team) {
  if (team.squad.isEmpty) return 60.0;
  final total = team.squad.fold<int>(0, (sum, p) => sum + p.ovr);
  return total / team.squad.length;
}

/// Advances a matchday the club has no fixture for, which happens when the
/// league has an odd number of clubs.
///
/// The other clubs in the round still play, so their records advance and the
/// table keeps moving instead of stalling on the user's bye.
void advancePastBye(WidgetRef ref) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return;
  final round = session.season.currentMatchday;
  if (session.season.userFixtureForRound(round, session.team.id) != null) {
    return;
  }

  _simulateRemainingFixtures(ref, session, round);

  final advanced = round + 1;
  final season = SeasonState(
    leagueId: session.season.leagueId,
    currentMatchday: advanced,
    currentYear: session.season.currentYear,
    isPreSeason: false,
    isWinterBreak: advanced == session.season.winterBreakRound,
    records: session.season.records,
    rounds: session.season.rounds,
  );
  final updated = _rebuildSession(session, season);
  updated.team.leaguePosition = season.positionOf(session.team.id);
  ref.read(careerSessionProvider.notifier).state = updated;
  _persist(ref, updated);
}

/// Clears the winter break so the paused matchday can be played.
void resumeFromWinterBreak(WidgetRef ref) {
  final session = ref.read(careerSessionProvider);
  if (session == null || !session.season.isWinterBreak) return;
  final season = SeasonState(
    leagueId: session.season.leagueId,
    currentMatchday: session.season.currentMatchday,
    currentYear: session.season.currentYear,
    isPreSeason: false,
    isWinterBreak: false,
    records: session.season.records,
    rounds: session.season.rounds,
  );
  final updated = _rebuildSession(session, season);
  ref.read(careerSessionProvider.notifier).state = updated;
  _persist(ref, updated);
}

/// Generates [count] youth intake prospects for the user's academy.
///
/// Key attributes are rolled once at intake and stored so they stay stable
/// across sessions, and everything is persisted immediately.
void addYouthProspect(WidgetRef ref, {int count = 1}) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return;
  final rng = Random();
  const first = [
    'Lucas',
    'Marco',
    'Diego',
    'Pablo',
    'Ivan',
    'Kai',
    'Noah',
    'Adam',
    'Luka',
    'Daniel',
    'Mateo',
    'Sven',
    'Tomas',
    'Andre'
  ];
  const last = [
    'Vega',
    'Moreno',
    'Silva',
    'Costa',
    'Ivanov',
    'Berg',
    'Okafor',
    'Mitchell',
    'Petrovic',
    'Novak',
    'Herrera',
    'Lindgren',
    'Diallo',
    'Rossi'
  ];
  const positions = [
    'ST',
    'CM',
    'CB',
    'LB',
    'RB',
    'GK',
    'LW',
    'RW',
    'DM',
    'AM'
  ];

  for (var i = 0; i < count; i++) {
    final potential = 68 + rng.nextInt(25); // 68..92
    final currentStats =
        (potential - 10 - rng.nextInt(15)).clamp(40, potential - 2);
    final youth = YouthPlayer(
      name: '${first[rng.nextInt(first.length)]} '
          '${last[rng.nextInt(last.length)]}',
      age: 15 + rng.nextInt(3),
      potential: potential,
      currentStats: currentStats,
      position: positions[rng.nextInt(positions.length)],
      nationality: session.team.country,
    );
    youth.hiddenAttributes['keyAttributes'] = {
      for (final n in youth.keyAttributeNames)
        n: (currentStats + rng.nextInt(11) - 5).clamp(35, 95),
    };
    session.youthPlayers.add(youth);
  }
  _bumpState(ref);
  _persist(ref, session);
}

/// Promotes a youth player into the first-team squad.
void promoteYouthPlayer(WidgetRef ref, YouthPlayer youth) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return;
  final attrs = youth.currentStats;
  final player = Player(
    name: youth.name,
    id: const Uuid().v4().hashCode,
    nationality: youth.nationality,
    age: youth.age,
    ovr: attrs,
    pac: attrs,
    sho: attrs,
    pas: attrs,
    dri: attrs,
    def: attrs,
    phy: attrs,
    acceleration: attrs,
    sprintSpeed: attrs,
    positioning: attrs,
    finishing: attrs,
    shotPower: attrs,
    longShots: attrs,
    volleys: attrs,
    penalties: attrs,
    vision: attrs,
    crossing: attrs,
    freeKickAccuracy: attrs,
    shortPassing: attrs,
    longPassing: attrs,
    curve: attrs,
    agility: attrs,
    balance: attrs,
    reactions: attrs,
    ballControl: attrs,
    composure: attrs,
    interceptions: attrs,
    headingAccuracy: attrs,
    defAwareness: attrs,
    standingTackle: attrs,
    slidingTackle: attrs,
    jumping: attrs,
    staminaStat: attrs,
    strength: attrs,
    aggression: attrs,
    primaryPosition: youth.position,
    alternativePositions: const [],
    preferredFoot: 'Right',
    weakFootQuality: 3,
    skillMoves: 3,
    height: '180cm',
    weight: '74kg',
    playTraits: const [],
    currentTeam: session.team.name,
    currentLeague: session.team.leagueId,
  );
  player.hiddenAttributes['personality'] =
      youth.hiddenAttributes['personality'];
  player.hiddenAttributes['leadership'] = youth.hiddenAttributes['leadership'];
  session.team.squad.add(player);
  session.youthPlayers.remove(youth);
  _bumpState(ref);
  _persist(ref, session);
}

/// Releases a youth player from the academy (UI confirms first).
void releaseYouthPlayer(WidgetRef ref, YouthPlayer youth) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return;
  session.youthPlayers.remove(youth);
  _bumpState(ref);
  _persist(ref, session);
}

/// Buys a player from the transfer market if the budget allows.
bool buyPlayer(WidgetRef ref, Player player, int fee) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return false;
  if (fee > session.team.transferBudget) return false;

  final fromTeam = player.currentTeam;
  player.currentTeam = session.team.name;
  session.team.squad.add(player);
  session.team.transferBudget -= fee;
  player.weeklyWage = player.ovr * 1200.0;
  player.transferValue = FinancialService().calculateTransferValue(player);

  // Remove from selling team's directory squad if it exists in the DB.
  final db = ref.read(playerDatabaseProvider).valueOrNull;
  final seller = db?.teams.where((t) => t.name == fromTeam).firstOrNull;
  if (seller != null) {
    seller.squad.removeWhere((p) => p.id == player.id);
  }

  _bumpState(ref);
  _persist(ref, session);
  return true;
}

/// Sells a player from the user's squad.
bool sellPlayer(WidgetRef ref, Player player, int fee) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return false;
  if (session.team.squad.length <= 16) return false; // keep a viable squad

  session.team.squad.removeWhere((p) => p.id == player.id);
  session.team.transferBudget += fee;
  _bumpState(ref);
  _persist(ref, session);
  return true;
}

// --- Player management state (stored in hiddenAttributes so it persists
// through the existing Hive PlayerAdapter with no schema migration). ---

/// Transfer-lists (or unlists) a squad player.
void setTransferListing(
  WidgetRef ref,
  Player player, {
  required bool listed,
  int? askingPrice,
}) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return;
  if (listed) {
    player.hiddenAttributes['transferListed'] = true;
    player.hiddenAttributes['askingPrice'] =
        askingPrice ?? FinancialService().calculateTransferValue(player);
  } else {
    player.hiddenAttributes
      ..remove('transferListed')
      ..remove('askingPrice');
  }
  _bumpState(ref);
  _persist(ref, session);
}

/// Loan-lists (or unlists) a squad player.
void setLoanListing(WidgetRef ref, Player player, {required bool listed}) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return;
  if (listed) {
    player.hiddenAttributes['loanListed'] = true;
  } else {
    player.hiddenAttributes.remove('loanListed');
  }
  _bumpState(ref);
  _persist(ref, session);
}

/// Sets a custom squad-role label (Key Player, Rotation, …).
void setSquadRole(WidgetRef ref, Player player, String role) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return;
  player.hiddenAttributes['squadRole'] = role;
  _bumpState(ref);
  _persist(ref, session);
}

/// Sets the individual training focus for a player.
void setTrainingFocus(WidgetRef ref, Player player, String focus) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return;
  player.hiddenAttributes['trainingFocus'] = focus;
  _bumpState(ref);
  _persist(ref, session);
}

/// The player's squad status: a custom label when one was set, otherwise
/// derived deterministically from the OVR rank inside the squad.
String squadStatusOf(Player player, List<Player> squad) {
  final custom = player.hiddenAttributes['squadRole'];
  if (custom is String && custom.isNotEmpty) return custom;
  final sorted = [...squad]..sort((a, b) => b.ovr.compareTo(a.ovr));
  final rank = sorted.indexWhere((p) => p.id == player.id);
  if (rank < 0) return 'Squad Player';
  if (rank < 3) return 'Key Player';
  if (rank < 7) return 'First Team';
  if (rank < 12) return 'Squad Player';
  if (rank < 18) return 'Rotation';
  return 'Prospect';
}

/// Whether the player is transfer-listed, with the asking price.
(bool, int?) transferListingOf(Player player) {
  final listed = player.hiddenAttributes['transferListed'] == true;
  final price = player.hiddenAttributes['askingPrice'];
  return (listed, price is num ? price.toInt() : null);
}

/// Whether the player is loan-listed.
bool loanListingOf(Player player) =>
    player.hiddenAttributes['loanListed'] == true;

/// The player's training focus, or null when none is set.
String? trainingFocusOf(Player player) {
  final focus = player.hiddenAttributes['trainingFocus'];
  return focus is String && focus.isNotEmpty ? focus : null;
}

// --- Shortlist & offers ---

/// Adds/removes a player from the shortlist and persists.
void toggleShortlist(WidgetRef ref, int playerId) {
  final current = {...ref.read(shortlistProvider)};
  if (!current.remove(playerId)) current.add(playerId);
  ref.read(shortlistProvider.notifier).state = current;
  _persistCurrent(ref);
}

/// Records an outgoing transfer offer (status: waiting/accepted/rejected).
void recordTransferOffer(WidgetRef ref, Map<String, dynamic> offer) {
  final offers = [...ref.read(transferOffersProvider)];
  offers.removeWhere((o) => o['playerId'] == offer['playerId']);
  offers.insert(0, offer);
  ref.read(transferOffersProvider.notifier).state = offers;
  _persistCurrent(ref);
}

/// Saves a named tactic ([name]) from [tactic].
void saveNamedTactic(WidgetRef ref, String name, Tactic tactic) {
  final saved = [...ref.read(savedTacticsProvider)];
  saved.removeWhere((t) => t['name'] == name);
  saved.add({'name': name, 'tactic': tactic.toJson()});
  ref.read(savedTacticsProvider.notifier).state = saved;
  _persistCurrent(ref);
}

/// Deletes a named saved tactic.
void deleteNamedTactic(WidgetRef ref, String name) {
  final saved = [...ref.read(savedTacticsProvider)]
    ..removeWhere((t) => t['name'] == name);
  ref.read(savedTacticsProvider.notifier).state = saved;
  _persistCurrent(ref);
}

/// Persists the current session (or clears career-only state when none).
void _persistCurrent(WidgetRef ref) {
  final session = ref.read(careerSessionProvider);
  if (session != null) {
    _persist(ref, session);
  }
}

/// Forces Riverpod listeners to re-evaluate after in-place model mutations.
void _bumpState(WidgetRef ref) {
  final notifier = ref.read(careerSessionProvider.notifier);
  notifier.state = notifier.state;
}

/// What happened when a season rolled over.
class SeasonOutcome {
  const SeasonOutcome({
    required this.year,
    required this.position,
    required this.points,
    required this.movement,
  });

  final int year;
  final int position;
  final int points;

  /// `promoted`, `relegated` or `stayed`.
  final String movement;
}

/// Closes the season and starts the next one.
///
/// Returns null when the season is still in progress. The club moves up or
/// down a division only when the database actually holds a neighbouring
/// league in the same country; leagues are ordered by average squad strength
/// because the shipped data has no explicit tier column.
SeasonOutcome? rollIntoNextSeason(WidgetRef ref) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return null;
  final season = session.season;
  if (!season.isPostSeason) return null;

  final team = session.team;
  final position = season.positionOf(team.id);
  final points = season.records[team.id]?.points ?? team.points;
  final movement = _resolveMovement(ref, session, position);

  if (movement != _movementStayed) {
    final target = _neighbourLeague(ref, session, movement);
    if (target != null) {
      team.leagueId = target;
      // The database derives leagues from the clubs in them, so the shared
      // instance must move too or the market would show a stale league.
      final db = ref.read(playerDatabaseProvider).valueOrNull;
      final mirror = db?.teams.where((t) => t.id == team.id).firstOrNull;
      if (mirror != null && !identical(mirror, team)) {
        mirror.leagueId = target;
      }
    }
  }

  // Reset the season's own numbers; the club's identity and squad carry over.
  team.points = 0;
  team.wins = 0;
  team.draws = 0;
  team.losses = 0;
  team.matchesPlayed = 0;
  team.goalsFor = 0;
  team.goalsAgainst = 0;
  team.leaguePosition = 10;

  final db = ref.read(playerDatabaseProvider).valueOrNull;
  final rivals = db == null
      ? <Team>[]
      : db.teams.where((t) => t.leagueId == team.leagueId).toList();

  final nextSeason = SeasonState(
    leagueId: team.leagueId,
    currentMatchday: 0,
    currentYear: season.currentYear + 1,
    isPreSeason: false,
    isWinterBreak: false,
    records: {for (final t in rivals) t.id: LeagueRecord()},
    rounds: buildRounds([for (final t in rivals) t.id], rng: Random()),
  );

  final updated = _rebuildSession(session, nextSeason);
  updated.userResults.clear();
  ref.read(careerSessionProvider.notifier).state = updated;
  ref.read(lastMatchResultProvider.notifier).state = null;
  _persist(ref, updated);

  return SeasonOutcome(
    year: nextSeason.currentYear,
    position: position,
    points: points,
    movement: movement,
  );
}

const String _movementStayed = 'stayed';
const String _movementPromoted = 'promoted';
const String _movementRelegated = 'relegated';

/// Whether the club earned a place in the promotion or relegation zone.
///
/// Promotion and relegation use the usual four-club band. A club that finishes
/// in the band but has no adjacent division in the shipped database simply
/// stays put rather than being moved somewhere invented.
String _resolveMovement(WidgetRef ref, CareerSession session, int position) {
  final table = session.season.table();
  if (table.length < 4 || position <= 0) return _movementStayed;
  final ladder = _countryLeagueLadder(ref, session);
  if (ladder.length < 2) return _movementStayed;

  final tier = ladder.indexWhere((l) => l == session.team.leagueId);
  if (tier < 0) return _movementStayed;

  final band = table.length ~/ 4;
  if (position <= band && tier > 0) return _movementPromoted;
  if (position > table.length - band && tier < ladder.length - 1) {
    return _movementRelegated;
  }
  return _movementStayed;
}

/// Leagues in the club's country ordered strongest first, by average squad
/// rating. The CSV has no division/tier column, so strength is the only real
/// signal available for ranking them.
List<String> _countryLeagueLadder(WidgetRef ref, CareerSession session) {
  final db = ref.read(playerDatabaseProvider).valueOrNull;
  if (db == null) return [];
  final byLeague = <String, List<Team>>{};
  for (final t in db.teams) {
    if (t.country == session.team.country) {
      byLeague.putIfAbsent(t.leagueId, () => []).add(t);
    }
  }
  final scored = <String, double>{};
  byLeague.forEach((leagueId, clubs) {
    if (clubs.length < 2) return;
    final total = clubs.fold<int>(
      0,
      (sum, t) => sum + t.squad.fold<int>(0, (s, p) => s + p.ovr),
    );
    scored[leagueId] = total / clubs.length;
  });
  final ladder = scored.keys.toList()
    ..sort((a, b) => scored[b]!.compareTo(scored[a]!));
  return ladder;
}

/// The league one step in [movement]'s direction, or null when there is none.
String? _neighbourLeague(
    WidgetRef ref, CareerSession session, String movement) {
  final ladder = _countryLeagueLadder(ref, session);
  final tier = ladder.indexWhere((l) => l == session.team.leagueId);
  if (tier < 0) return null;
  final step = movement == _movementPromoted ? -1 : 1;
  final next = tier + step;
  if (next < 0 || next >= ladder.length) return null;
  return ladder[next];
}
