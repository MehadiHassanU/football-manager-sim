import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/models/manager.dart';
import '../core/models/match.dart';
import '../core/models/player.dart';
import '../core/models/season.dart';
import '../core/models/team.dart';
import '../core/models/tactics.dart';
import '../core/models/youth_player.dart';
import '../core/services/financial_service.dart';
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
final transferOffersProvider = StateProvider<List<Map<String, dynamic>>>(
    (ref) => []);

/// Named saved tactics: [{'name': String, 'tactic': Tactic-as-json}].
final savedTacticsProvider = StateProvider<List<Map<String, dynamic>>>(
    (ref) => []);

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
  final fixtures =
      leagueRivals.length >= 2 ? buildFixtures(leagueRivals) : <String>[];

  final season = SeasonState(
    leagueId: team.leagueId,
    currentMatchday: 0,
    totalMatchdays: fixtures.isNotEmpty ? fixtures.length ~/ leagueRivals.length : 38,
    currentYear: DateTime.now().year,
    isPreSeason: false,
    isWinterBreak: false,
    standings: {
      for (final t in leagueRivals) t.id: 0,
    },
    matchdayFixtures: fixtures,
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
    final season = await SaveService().loadSeason();
    if (manager == null || team == null || season == null) return false;

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

/// Applies a match result to the career session: standings, form, budget.
void applyMatchResult(WidgetRef ref, MatchResult result, {required bool userIsHome}) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return;

  final userGoals = userIsHome ? result.homeGoals : result.awayGoals;
  final oppGoals = userIsHome ? result.awayGoals : result.homeGoals;
  final points = userGoals > oppGoals ? 3 : (userGoals == oppGoals ? 1 : 0);
  final opponentId = _opponentId(session, userIsHome);

  session.userResults.add(points);
  if (session.userResults.length > 10) session.userResults.removeAt(0);

  session.season.standings[session.team.id] =
      (session.season.standings[session.team.id] ?? 0) + points;
  if (opponentId != null) {
    session.season.standings[opponentId] =
        (session.season.standings[opponentId] ?? 0) + (3 - points);
  }

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
  session.team.points =
      session.team.wins * 3 + session.team.draws;
  session.team.leaguePosition = _leaguePosition(session);

  // Season progression is tracked on the copy stored in the provider.
  final updatedSeason = SeasonState(
    leagueId: session.season.leagueId,
    currentMatchday: session.season.currentMatchday + 1,
    totalMatchdays: session.season.totalMatchdays,
    currentYear: session.season.currentYear,
    isPreSeason: false,
    isWinterBreak: session.season.isWinterBreak,
    standings: session.season.standings,
    matchdayFixtures: session.season.matchdayFixtures,
  );
  final updated = CareerSession(
    manager: session.manager,
    team: session.team,
    season: updatedSeason,
    startXI: session.startXI,
  );
  updated.tactic = session.tactic;
  updated.userResults.addAll(session.userResults);

  // Gate receipts for home matches.
  if (userIsHome) {
    final gate = FinancialService().estimateGateReceipts(session.team);
    session.team.revenue += gate;
    session.team.budget += gate.round();
  }

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
  const first = ['Lucas', 'Marco', 'Diego', 'Pablo', 'Ivan', 'Kai', 'Noah',
    'Adam', 'Luka', 'Daniel', 'Mateo', 'Sven', 'Tomas', 'Andre'];
  const last = ['Vega', 'Moreno', 'Silva', 'Costa', 'Ivanov', 'Berg', 'Okafor',
    'Mitchell', 'Petrovic', 'Novak', 'Herrera', 'Lindgren', 'Diallo', 'Rossi'];
  const positions = ['ST', 'CM', 'CB', 'LB', 'RB', 'GK', 'LW', 'RW', 'DM', 'AM'];

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
    pac: attrs, sho: attrs,
    pas: attrs, dri: attrs,
    def: attrs, phy: attrs,
    acceleration: attrs, sprintSpeed: attrs,
    positioning: attrs, finishing: attrs,
    shotPower: attrs, longShots: attrs,
    volleys: attrs, penalties: attrs,
    vision: attrs, crossing: attrs,
    freeKickAccuracy: attrs, shortPassing: attrs,
    longPassing: attrs, curve: attrs,
    agility: attrs, balance: attrs,
    reactions: attrs, ballControl: attrs,
    composure: attrs, interceptions: attrs,
    headingAccuracy: attrs, defAwareness: attrs,
    standingTackle: attrs, slidingTackle: attrs,
    jumping: attrs, staminaStat: attrs,
    strength: attrs, aggression: attrs,
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
  player.hiddenAttributes['leadership'] =
      youth.hiddenAttributes['leadership'];
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
    player.hiddenAttributes..remove('transferListed')..remove('askingPrice');
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

String? _opponentId(CareerSession session, bool userIsHome) {
  // The opponent is derived from the fixture list when present.
  if (session.season.matchdayFixtures.isEmpty) return null;
  final fixture =
      session.season.matchdayFixtures[session.season.currentMatchday];
  final parts = fixture.split('|');
  if (parts.length != 2) return null;
  return userIsHome ? parts[1] : parts[0];
}

int _leaguePosition(CareerSession session) {
  final standings = session.season.standings;
  final sorted = standings.values.toList()..sort((a, b) => b.compareTo(a));
  final myPoints = standings[session.team.id] ?? 0;
  return sorted.indexOf(myPoints) + 1;
}

/// Builds a fixtures list for a league (round-robin, one leg for simplicity).
List<String> buildFixtures(List<Team> leagueTeams) {
  final fixtures = <String>[];
  for (var i = 0; i < leagueTeams.length; i++) {
    for (var j = i + 1; j < leagueTeams.length; j++) {
      fixtures.add('${leagueTeams[i].id}|${leagueTeams[j].id}');
      fixtures.add('${leagueTeams[j].id}|${leagueTeams[i].id}');
    }
  }
  fixtures.shuffle();
  return fixtures;
}
