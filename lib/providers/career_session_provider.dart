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
import '../core/models/transfer.dart';
import '../core/models/youth_player.dart';
import '../core/constants/game_constants.dart';
import '../core/services/cup_service.dart';
import '../core/services/development_service.dart';
import '../core/services/financial_service.dart';
import '../core/services/match_simulator_service.dart';
import '../core/services/rival_market_service.dart';
import '../core/services/transfer_market_service.dart';
import '../core/services/save_service.dart';
import 'data_providers.dart';
import 'settings_providers.dart';

/// The world's rival market clock, exposed as a provider so tests can swap a
/// scripted service for the real one without leaning on random rolls.
final rivalTransferServiceProvider =
    Provider<RivalTransferService>((ref) => RivalTransferService());

/// A complete active career: manager, club, season, and tactics.
class CareerSession {
  CareerSession({
    required this.manager,
    required this.team,
    required this.season,
    this.tactic = const Tactic(),
    List<int>? startXI,
    List<int>? userResults,
    List<YouthPlayer>? youthPlayers,
    this.boardNote = '',
    TransferDesk? transferDesk,
    List<String>? trophies,
    Map<int, int>? worldGrowth,
  })  : startXI = startXI ?? [],
        userResults = userResults ?? [],
        youthPlayers = youthPlayers ?? [],
        transferDesk = transferDesk ?? TransferDesk(),
        trophies = trophies ?? [],
        worldGrowth = worldGrowth ?? <int, int>{};

  final Manager manager;
  final Team team;
  final SeasonState season;
  Tactic tactic;

  /// Player ids of the manager's chosen starting XI (tactics screen).
  List<int> startXI;

  /// The user's club results this season (last 10), used for the form guide.
  final List<int> userResults;

  /// Youth academy prospects (separate from Team.squad, which is first-team).
  final List<YouthPlayer> youthPlayers;

  /// The board's last stated verdict, shown on the Home screen.
  ///
  /// The risk gauge moves on every matchday and reaches 100 after roughly six
  /// straight defeats, so without the reason on screen the manager only learns
  /// why the bar was climbing at the moment it is too late.
  String boardNote;

  /// Live transfer negotiations, incoming bids and the news feed. Carried on
  /// the session so the existing save blob persists it with everything else.
  TransferDesk transferDesk;

  /// Cups and honours won, one entry per trophy (e.g. "National Cup 2026").
  /// Feed lines disappear; a cabinet does not — this is also why a cup
  /// victory settles the board down for a while.
  final List<String> trophies;

  /// Net OVR change per rival player id, accumulated at season rollovers.
  ///
  /// Rival squads are rebuilt from the CSV every session, so their season
  /// development cannot live on the players themselves; it is recorded here
  /// (one entry per player, replaced as seasons pass) and layered back on top
  /// of the fresh ratings at restore.
  final Map<int, int> worldGrowth;

  /// `Map<String, int>` get standings -> see [season].
  Map<String, int> get standings => season.standings;

  /// A new session object that shares every piece of career state with this
  /// one (same [team], [season] and academy list instances).
  ///
  /// [careerSessionProvider] is a `StateProvider`, and Riverpod only notifies
  /// listeners when the emitted value is a *different instance*. Almost every
  /// career mutation (transfer listing, squad role, youth intake) edits the
  /// existing models in place, so re-emitting the same object was silently
  /// swallowed and the UI never rebuilt. Emitting this shallow copy is what
  /// makes those in-place changes visible without cloning the whole career.
  CareerSession shallowCopy() => CareerSession(
        manager: manager,
        team: team,
        season: season,
        tactic: tactic,
        startXI: startXI,
        userResults: userResults,
        youthPlayers: youthPlayers,
        boardNote: boardNote,
        transferDesk: transferDesk,
        trophies: trophies,
        worldGrowth: worldGrowth,
      );
}

/// null = no active career.
final careerSessionProvider = StateProvider<CareerSession?>((ref) => null);

/// Outcome of the most recent played match, for the Home screen.
final lastMatchResultProvider = StateProvider<MatchResult?>((ref) => null);

/// Shortlisted market player ids (persisted in the career blob).
final shortlistProvider = StateProvider<Set<int>>((ref) => {});

/// Why the most recent transfer was refused, so the screen can say what
/// actually stopped it instead of a generic "constraints" message.
final transferBlockReasonProvider = StateProvider<String?>((ref) => null);

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

  // A knockout cup rides the same calendar: its rounds get spliced between
  // league matchdays deterministically, and the drawn fixtures land right
  // away so matchday 1's opponent is already on screen.
  final cup = CupService.attachCup(
    rounds: rounds,
    teamIds: [for (final t in leagueRivals) t.id],
    leagueId: team.leagueId,
    currentYear: DateTime.now().year,
  );

  final season = SeasonState(
    leagueId: team.leagueId,
    currentMatchday: 0,
    currentYear: DateTime.now().year,
    isPreSeason: false,
    isWinterBreak: false,
    records: {for (final t in leagueRivals) t.id: LeagueRecord()},
    rounds: rounds,
    cup: cup,
  );
  final session = CareerSession(manager: manager, team: team, season: season);
  ref.read(careerSessionProvider.notifier).state = session;
  // Seed the board's risk gauge from the persisted setting, so the Home screen
  // starts where the player configured it rather than at the model default.
  session.manager.sackablePercent = ref.read(sackablePercentProvider);
  // Transfers need contract data and a window calendar from the first day,
  // so the whole loaded player pool gets derived contracts and every club a
  // reputation (CSV clubs previously all sat at the default of 70).
  TransferMarketService().backfillTransferData(
    db?.teams ?? [team],
    season.currentYear,
  );
  session.transferDesk = TransferDesk();
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
      'trophies': List<String>.from(session.trophies),
      'worldGrowth': {
        for (final entry in session.worldGrowth.entries)
          '${entry.key}': entry.value,
      },
      'startXI': List<int>.from(session.startXI),
      'shortlist': ref.read(shortlistProvider).toList(),
      'transferOffers': ref.read(transferOffersProvider),
      'savedTactics': ref.read(savedTacticsProvider),
      'transferDesk': session.transferDesk.toJson(),
      // The active tactic used to live only in memory, so every restart
      // silently reset the formation and instructions.
      'tactic': session.tactic.toJson(),
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

    // Await the database rather than reading `.valueOrNull`: restore repairs
    // contracts, reputation and the transfer ledger against it, and a still
    // loading database silently skipped all of that.
    final db = await ref.read(playerDatabaseProvider.future);
    final season = migrateSeasonSchedule(savedSeason, team, db);

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
      final trophies = blob['trophies'];
      if (trophies is List) {
        session.trophies.addAll(trophies.whereType<String>());
      }
      final growth = blob['worldGrowth'];
      if (growth is Map) {
        for (final entry in growth.entries) {
          final id = int.tryParse('${entry.key}');
          final delta = (entry.value as num?)?.toInt();
          if (id != null && delta != null && delta != 0) {
            session.worldGrowth[id] = delta;
          }
        }
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

    // Older saves predate contracts, reputation and windows: repair them on
    // load instead of refusing to continue the career. The session's team is a
    // separate instance from the database's copy of the same club, so it has
    // to be repaired explicitly or the manager's own squad keeps null deals.
    TransferMarketService().backfillTransferData(
      [...db.teams, team],
      season.currentYear,
    );
    final tacticJson = blob?['tactic'];
    if (tacticJson is Map) {
      session.tactic = Tactic.fromJson(Map<String, dynamic>.from(tacticJson));
    }
    final deskJson = blob?['transferDesk'];
    session.transferDesk = deskJson is Map
        ? TransferDesk.fromJson(Map<String, dynamic>.from(deskJson))
        : ref.read(transferOffersProvider).isEmpty
            ? TransferDesk()
            : TransferDesk.fromLegacyOffers(ref.read(transferOffersProvider));

    // Rebuild the world from the move list: buys, sales, hijacks and loans
    // all survive the CSV reload that resets every other squad.
    TransferMarketService().applyTransferLedger(
      players: db.players,
      teams: db.teams,
      moves: session.transferDesk.ledger,
      userClub: team.name,
    );

    // Season development is replayed the same way: recorded OVR deltas go on
    // top of the fresh CSV ratings so a rival who grew over past seasons
    // stays grown.
    DevelopmentService.applyWorldGrowth(db.players, session.worldGrowth);

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
BoardVerdict? applyMatchResult(WidgetRef ref, MatchResult result) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return null;

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

  // Appearances are only folded in on the first application of a fixture, so
  // replaying a matchday after a crash cannot inflate games played.
  final firstRun = !(fixture?.played ?? false);

  if (fixture != null && !fixture.played) {
    fixture.record(result.homeGoals, result.awayGoals);
    // Cup ties feed the bracket, not the table: league records only take
    // league fixtures, so cup results never distort the standings.
    if (fixture.competition == 'league') {
      _applyResultToRecords(season, fixture);
    }
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

  if (firstRun) {
    _recordAppearances(session.team, result, userIsHome: userIsHome);
    // A played match is also a training week: minutes on the pitch decide how
    // much of the week's work actually counts towards development.
    _developTrainingWeek(
      session,
      minutes: _minutesByName(result, userIsHome: userIsHome),
    );
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
    cup: season.cup,
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

  // The board reacts to the result, so the sack-risk gauge the Home screen
  // shows actually responds to how the manager is doing.
  final verdict = evaluateBoard(ref, updated);
  // Playing time is the squad's mood: ignored players become unsettled and
  // eventually hand in a transfer request, which is what the market reacts to.
  assessSquadHappiness(ref, updated);
  // The market has its own clock: rivals move in, bids arrive, deals die
  // when the window shuts.
  advanceTransferDesk(ref, updated);
  // The cup bracket advances when a round fills, and the manager's cup fate
  // becomes board news — after the desk, so the note is not overwritten by
  // (rarer) deadline-day board reactions.
  _settleCupAfterRound(updated);

  ref.read(careerSessionProvider.notifier).state = updated;
  _persist(ref, updated);
  return verdict;
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
  updated.trophies.addAll(session.trophies);
  updated.worldGrowth.addAll(session.worldGrowth);
  updated.youthPlayers.addAll(session.youthPlayers);
  updated.boardNote = session.boardNote;
  updated.transferDesk = session.transferDesk;
  return updated;
}

/// Minutes per player from the manager's side of the match report; the
/// simulator returns home ratings first and away ratings second.
Map<String, int> _minutesByName(
  MatchResult result, {
  required bool userIsHome,
}) {
  final ratings = userIsHome
      ? result.playerRatings.take(11)
      : result.playerRatings.skip(11);
  return {for (final rating in ratings) rating.playerName: rating.minutes};
}

/// One week of training: the squad creeps towards (or away from) its
/// potential with [minutes] deciding how much the week is worth, and the
/// academy prospects tick along on the same clock.
///
/// Rival squads develop at the rollover instead, because only the manager's
/// matches produce minute-by-minute reports.
void _developTrainingWeek(
  CareerSession session, {
  Map<String, int> minutes = const {},
}) {
  final season = session.season;
  for (final player in session.team.squad) {
    DevelopmentService.developWeek(
      player,
      minutes: minutes[player.name] ?? 0,
      leagueId: season.leagueId,
      year: season.currentYear,
      matchday: season.currentMatchday,
    );
  }
  for (final prospect in session.youthPlayers) {
    DevelopmentService.developYouth(
      prospect,
      leagueId: season.leagueId,
      year: season.currentYear,
      matchday: season.currentMatchday,
    );
  }
}

/// Folds the match's rating list into the squad's appearance totals.
///
/// The simulator returns home ratings first and away ratings second, so the
/// manager's own eleven is sliced by which side he was on. Minutes were never
/// recorded at all before this, which is why games played sat at zero for a
/// whole career and the squad's mood had nothing to react to.
void _recordAppearances(
  Team team,
  MatchResult result, {
  required bool userIsHome,
}) {
  final ratings = userIsHome
      ? result.playerRatings.take(11)
      : result.playerRatings.skip(11);
  final byName = {for (final p in team.squad) p.name: p};
  for (final rating in ratings) {
    if (rating.minutes <= 0) continue;
    final player = byName[rating.playerName];
    if (player == null) continue;
    player.gamesPlayed += 1;
    player.minutesPlayed += rating.minutes;
    player.matchRating = rating.rating;
    // Form is the rolling match rating; morale drifts with how he played, and
    // a bad individual display hurts regardless of the result.
    player.form = ((player.form * 2 + rating.rating) / 3).round().clamp(1, 10);
    final moraleShift =
        rating.rating >= 7 ? 4 : (rating.rating <= 5 ? -5 : 0);
    player.morale = (player.morale + moraleShift).clamp(0, 100);
  }
}

/// How many matchdays an ignored player waits before asking to leave.
const int unsettledPatience = 2;

/// Turns playing time into transfer drama.
///
/// A player ranked highly in the squad who is not getting the minutes his
/// standing implies becomes unsettled; if that persists he hands in a transfer
/// request, and [advanceTransferDesk] then attracts real offers for him.
/// Minutes settle him again, and a withdrawn request follows a spell of games,
/// so the squad reacts to what the manager actually does rather than to a
/// one-way timer. Everything here is derived from stored counters, so it also
/// survives a reload.
void assessSquadHappiness(WidgetRef ref, CareerSession session) {
  final team = session.team;
  if (team.matchesPlayed < 4 || team.squad.isEmpty) return;
  final squad = team.squad;
  final matchday = session.season.currentMatchday;
  final desk = session.transferDesk;
  final order = [...squad]..sort((a, b) => b.ovr.compareTo(a.ovr));

  for (final player in squad) {
    if (player.isInjured) continue;
    final rank = order.indexWhere((p) => p.id == player.id);
    if (rank < 0) continue;
    // Prospects are expected to wait; everyone else is measured against what
    // a player of their standing should be playing.
    if (rank >= 14 && player.age < 23) continue;
    final expectedShare =
        rank < 3 ? 0.75 : (rank < 8 ? 0.55 : (rank < 14 ? 0.35 : 0.15));
    final expectedMinutes = team.matchesPlayed * 90 * expectedShare;
    final short = player.minutesPlayed < expectedMinutes * 0.6;

    final since = player.hiddenAttributes['unsettled'];
    final promise = player.hiddenAttributes['minutesPromise'];
    final promisedAt = promise is int ? promise : null;

    if (!short) {
      // He is playing again: the complaint clears, and a request is withdrawn
      // once the minutes have actually followed.
      if (player.hiddenAttributes.remove('unsettled') != null) {
        player.hiddenAttributes.remove('minutesPromise');
        desk.addNews(TransferNewsItem(
          type: 'settled',
          title: '${player.name} is settled again',
          body: 'Minutes have done the talking. He has stopped asking for a '
              'move.',
          matchday: matchday,
        ));
      }
      final requestedAt = player.hiddenAttributes['transferRequestMatchday'];
      if (player.requestedTransfer &&
          requestedAt is int &&
          matchday - requestedAt >= 2) {
        player.requestedTransfer = false;
        player.hiddenAttributes.remove('transferRequestMatchday');
        player.morale = (player.morale + 6).clamp(0, 100);
        desk.addNews(TransferNewsItem(
          type: 'settled',
          title: '${player.name} withdraws his transfer request',
          body: 'He has had the run of games he wanted and is staying.',
          matchday: matchday,
        ));
      }
      continue;
    }

    if (since is! int) {
      player.hiddenAttributes['unsettled'] = matchday;
      player.morale = (player.morale - 12).clamp(0, 100);
      desk.addNews(TransferNewsItem(
        type: 'unsettled',
        title: '${player.name} is unhappy with his playing time',
        body: 'He is ranked among your best players but is not getting '
            'minutes. Talk to him from his profile before he asks to leave.',
        matchday: matchday,
      ));
      continue;
    }

    if (player.requestedTransfer) continue;
    // A promise buys patience, but only until the next few fixtures.
    final from = promisedAt != null && promisedAt > since ? promisedAt : since;
    final patience = promisedAt != null ? 3 : unsettledPatience;
    if (matchday - from < patience) continue;

    player.requestedTransfer = true;
    player.hiddenAttributes['transferRequestMatchday'] = matchday;
    player.morale = (player.morale - 10).clamp(0, 100);
    desk.addNews(TransferNewsItem(
      type: 'request',
      title: '${player.name} hands in a transfer request',
      body: 'He has waited long enough for minutes. Offers will follow.',
      matchday: matchday,
    ));
  }
}

/// Talks an unsettled player round without promising anything concrete.
///
/// He stays — but only if the minutes follow within three matchdays, which is
/// what keeps the promise meaningful instead of a free "calm him down" button.
void promisePlayingTime(WidgetRef ref, Player player) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return;
  final matchday = session.season.currentMatchday;
  player.hiddenAttributes['minutesPromise'] = matchday;
  player.hiddenAttributes['unsettled'] = matchday;
  player.morale = (player.morale + 8).clamp(0, 100);
  session.transferDesk.addNews(TransferNewsItem(
    type: 'unsettled',
    title: 'You promise ${player.name} minutes',
    body: 'He will give you three more matchdays. Break that promise and he '
        'will ask to leave.',
    matchday: matchday,
  ));
  _bumpState(ref);
  _persist(ref, session);
}

/// True when the player has complained about his playing time.
bool unsettledOf(Player player) =>
    player.hiddenAttributes['unsettled'] is int;

/// Runs the transfer market's own clock after a matchday.
///
/// Rivals sign players the manager left hanging, transfer-listed players
/// attract bids, unfinished deals collapse when the window shuts, and deadline
/// day is announced once. Everything is seeded from the player id and the
/// matchday, so reloading a save cannot reroll a hijack.
void advanceTransferDesk(WidgetRef ref, CareerSession session) {
  final desk = session.transferDesk;
  final season = session.season;
  const service = TransferMarketService();
  final window = TransferWindow.of(season);
  final matchday = season.currentMatchday;

  for (final negotiation in [...desk.negotiations]) {
    if (!negotiation.isActive) continue;
    final rival = negotiation.rivalClub;
    if (rival == null) continue;
    if (negotiation.rivalDeadlineMatchday < 0 ||
        matchday < negotiation.rivalDeadlineMatchday) {
      continue;
    }
    desk.replace(negotiation.copyWith(
      stage: DealStage.hijacked,
      counterOffer: 0,
      clearCounter: true,
      message: '$rival have moved first and agreed a deal for '
          '${negotiation.playerName}.',
    ));
    // The rival actually signs him, so the story is true: he leaves the
    // seller, joins the rival and stops being available.
    final db = ref.read(playerDatabaseProvider).valueOrNull;
    final player =
        db?.players.where((p) => p.id == negotiation.playerId).firstOrNull;
    if (db != null && player != null) {
      for (final team in db.teams) {
        team.squad.removeWhere((p) => p.id == negotiation.playerId);
      }
      final buyer = db.teams.where((t) => t.name == rival).firstOrNull;
      if (buyer != null) {
        player.currentTeam = rival;
        buyer.squad.add(player);
      }
      desk.recordMove(TransferMove(
        playerId: player.id,
        playerName: player.name,
        fromClub: negotiation.sellerClub,
        toClub: rival,
        kind: 'permanent',
        fee: negotiation.askingPrice,
        wage: negotiation.wageDemand,
        year: season.currentYear,
        matchday: matchday,
      ));
    }
    desk.addNews(TransferNewsItem(
      type: 'hijack',
      title: '$rival hijack ${negotiation.playerName}',
      body: 'You stalled on the asking price from '
          '${negotiation.sellerClub} and '
          '$rival pounced. The player is gone.',
      matchday: matchday,
    ));
  }

  if (!window.isOpen) {
    for (final negotiation in [...desk.negotiations]) {
      if (!negotiation.isActive) continue;
      desk.replace(negotiation.copyWith(
        stage: DealStage.collapsed,
        counterOffer: 0,
        clearCounter: true,
        message: 'The window shut before the deal was completed.',
      ));
    }
  }

  if (window.isOpen) {
    final db = ref.read(playerDatabaseProvider).valueOrNull;
    // Rival clubs do their own business before the desk looks at yours: the
    // news they generate plus the replacements they hunt when the manager
    // buys from them are what make the league feel alive every matchday.
    _advanceRivalMarket(ref, session, window);
    // At the 16-player minimum every offer would be a dead end: accepting one
    // is refused, so the desk stops generating them and says why once.
    final atMinimum = session.team.squad.length <= 16;
    final listedCount = session.team.squad
        .where((p) =>
            p.hiddenAttributes['transferListed'] == true ||
            p.requestedTransfer ||
            p.hiddenAttributes['loanListed'] == true)
        .length;
    if (atMinimum && listedCount > 0) {
      final alreadyTold = desk.news.any(
          (n) => n.type == 'minimum' && n.matchday == matchday);
      if (!alreadyTold) {
        desk.addNews(TransferNewsItem(
          type: 'minimum',
          title: 'No offers while the squad sits at 16',
          body: 'Clubs will not bid for players you cannot sell: the squad '
              'must keep 16. Sign or promote someone first.',
          matchday: matchday,
        ));
      }
    }
    for (final player in atMinimum ? <Player>[] : session.team.squad) {
      final loanListed = player.hiddenAttributes['loanListed'] == true;
      final listed = player.hiddenAttributes['transferListed'] == true ||
          player.requestedTransfer ||
          loanListed;
      if (!listed) continue;
      if (desk.incomingBids.any((b) => b.playerId == player.id)) continue;
      final rng = Random(player.id * 7919 + matchday * 17 + season.currentYear);
      if (rng.nextDouble() > 0.5) continue;
      final club = service.incomingClubFor(
        player,
        db?.teams ?? const [],
        session.team,
        seasonYear: season.currentYear,
        matchday: matchday,
      );
      if (club == null) continue;

      // A squad-size shortcut: clubs loan rather than buy when the player is
      // only loan-listed, or when he is young and needs games.
      final loanOnly = loanListed &&
          player.hiddenAttributes['transferListed'] != true &&
          !player.requestedTransfer;
      if (loanOnly) {
        final share = service.loanWageShare(player, session.team);
        desk.incomingBids.add(IncomingBid(
          playerId: player.id,
          playerName: player.name,
          club: club,
          fee: 0,
          matchday: matchday,
          kind: 'loan',
          wageSharePercent: share,
        ));
        desk.addNews(TransferNewsItem(
          type: 'sale',
          title: '$club want ${player.name} on loan',
          body: 'They would cover $share% of his wage and he would return at '
              'the end of the season.',
          matchday: matchday,
        ));
        continue;
      }

      final fee = service.incomingFee(
        player,
        seasonYear: season.currentYear,
        matchday: matchday,
      );
      desk.incomingBids.add(IncomingBid(
        playerId: player.id,
        playerName: player.name,
        club: club,
        fee: fee,
        matchday: matchday,
      ));
      desk.addNews(TransferNewsItem(
        type: 'sale',
        title: '$club bid for ${player.name}',
        body: '${TransferMarketService.money(fee)} on the table. '
            'Accept it or turn it down from the Offers tab.',
        matchday: matchday,
      ));
    }
  }

  if (window.isDeadlineDay &&
      !desk.news.any((n) => n.type == 'deadline' && n.matchday == matchday)) {
    desk.addNews(TransferNewsItem(
      type: 'deadline',
      title: 'Deadline day',
      body: 'The ${window.label.toLowerCase()} shuts at the end of this '
          'matchday. Unfinished deals collapse when it does.',
      matchday: matchday,
    ));
  }

  // The morning after deadline day, the desk reports what the window actually
  // did. Computed from the ledger, so the numbers are the moves the world
  // really made rather than a claim the feed invented.
  final shut = TransferWindow.on(season, matchday - 1);
  final summarised = desk.news.any(
      (n) => n.type == 'summary' && n.matchday == matchday);
  if (shut.isOpen &&
      shut.isDeadlineDay &&
      matchday > 0 &&
      season.currentMatchday - 1 == shut.closesAtMatchday &&
      !summarised) {
    desk.addNews(_windowSummary(session, shut));
    _boardJudgesTheWindow(session, shut);
  }
}

/// The board reacts to the window that just shut.
///
/// A heavyweight club that closed the window with zero arrivals gets a
/// visible nudge on the sack-risk gauge and a note the Home screen shows.
/// The board is demanding because recruitment was its one expectation when
/// it handed the budget over. Smaller clubs are exempt — a lean squad on a
/// lean budget is a plan, not neglect.
///
/// Runs inside `advanceTransferDesk`, which the matchday calls *after*
/// [evaluateBoard], so this note survives this matchday's board evaluation
/// and is what the Home screen reads.
void _boardJudgesTheWindow(CareerSession session, TransferWindow shut) {
  if (session.team.reputation < 65) return;
  final business = _windowBusiness(session, shut);
  if (business.arrivals > 0 || business.loansIn > 0) return;

  session.manager.sackablePercent =
      (session.manager.sackablePercent + _windowInactivityPenalty)
          .clamp(0.0, 100.0);
  session.boardNote =
      'The window shut without a single arrival. The board expected '
      'ambition with the money it handed over.';
}

/// Sack-risk added the first day after a deadline for a heavyweight club
/// that made zero signings or loan arrivals.
const double _windowInactivityPenalty = 10.0;

/// The user's window business, counted straight from the ledger.
({int arrivals, int loansIn, int departures, int loansOut, int spent, int received})
    _windowBusiness(CareerSession session, TransferWindow shut) {
  final windowMoves = session.transferDesk.ledger.where((m) =>
      m.kind != 'loanReturn' &&
      m.year == session.season.currentYear &&
      m.matchday >= shut.opensAtMatchday &&
      m.matchday <= shut.closesAtMatchday);
  var arrivals = 0;
  var loansIn = 0;
  var departures = 0;
  var loansOut = 0;
  var spent = 0;
  var received = 0;
  for (final move in windowMoves) {
    if (move.toClub == session.team.name) {
      if (move.kind == 'loan') {
        loansIn++;
      } else {
        arrivals++;
        spent += move.fee;
      }
    } else if (move.fromClub == session.team.name) {
      if (move.kind == 'loan') {
        loansOut++;
      } else {
        departures++;
        received += move.fee;
      }
    }
  }
  return (
    arrivals: arrivals,
    loansIn: loansIn,
    departures: departures,
    loansOut: loansOut,
    spent: spent,
    received: received,
  );
}

/// Spontaneous rival transfer activity once the desk has handled the user's
/// business.
///
/// Runs only while the window is open. Every move the rivals agree lands in
/// the desk ledger (replayed on restore, so sold players stay sold) and in
/// the news feed. Clubs that the manager bought from this window roll with a
/// much higher chance to replace the player they lost, which turns the
/// market into a reaction to the user's own business.
void _advanceRivalMarket(
  WidgetRef ref,
  CareerSession session,
  TransferWindow window,
) {
  final db = ref.read(playerDatabaseProvider).valueOrNull;
  if (db == null || db.teams.isEmpty) return;
  final season = session.season;
  final desk = session.transferDesk;
  final matchday = season.currentMatchday;

  final priorityBuyers = <String>{
    for (final move in desk.ledger)
      if (move.year == season.currentYear &&
          move.matchday >= window.opensAtMatchday &&
          move.matchday <= matchday &&
          move.toClub == session.team.name &&
          (move.kind == 'permanent' || move.kind == 'free'))
        move.fromClub,
  };

  final busyPlayers = <int>{
    for (final negotiation in desk.negotiations)
      if (negotiation.isActive) negotiation.playerId,
  };

  final deals = ref.read(rivalTransferServiceProvider).generateMoves(
    teams: db.teams,
    userClub: session.team.name,
    seedKey: season.leagueId,
    seasonYear: season.currentYear,
    matchday: matchday,
    priorityBuyers: priorityBuyers,
    busyPlayers: busyPlayers,
    activityMultiplier:
        difficultyStrengthMultiplier(ref.read(difficultyProvider)),
  );

  for (final deal in deals) {
    // Defensive: the manager's squad is never sellable by the rival clock,
    // regardless of what a generation path hands back. His squad is the
    // saved, authoritative state.
    final targetInUserSquad =
        session.team.squad.any((p) => p.id == deal.player.id);
    if (targetInUserSquad) continue;
    _applyRivalDeal(ref, session, db, deal);
  }
}

/// Applies a generated rival deal to the world state.
///
/// Mirrors the hijack application: the player leaves every club he might
/// still sit in, joins the buyer with the move's wage, and a durable
/// `TransferMove` is recorded so a restored save rebuilds the same world.
void _applyRivalDeal(
  WidgetRef ref,
  CareerSession session,
  PlayerDatabase db,
  RivalDeal deal,
) {
  final desk = session.transferDesk;
  final season = session.season;
  final player = deal.player;

  // The saved user squad is the authority for the manager's club; every
  // other squad (including the seller) updates in place.
  for (final team in db.teams) {
    if (team.name == session.team.name) continue;
    team.squad.removeWhere((p) => p.id == player.id);
  }
  player.currentTeam = deal.buyer.name;
  if (deal.wage > 0) player.weeklyWage = deal.wage.toDouble();
  deal.buyer.squad.add(player);

  desk.recordMove(TransferMove(
    playerId: player.id,
    playerName: player.name,
    fromClub: deal.seller.name,
    toClub: deal.buyer.name,
    kind: deal.fee > 0 ? 'permanent' : 'free',
    fee: deal.fee,
    wage: deal.wage,
    year: season.currentYear,
    matchday: season.currentMatchday,
  ));

  desk.addNews(TransferNewsItem(
    type: 'rival',
    title: '${deal.buyer.name} sign ${player.name}',
    body: deal.fee > 0
        ? '${TransferMarketService.money(deal.fee)} from '
            '${deal.seller.name}, on ${TransferMarketService.money(deal.wage)} '
            'a week. The league is not waiting for you.'
        : 'A free transfer from ${deal.seller.name}. Their contract had run '
            'out and the league moved first.',
    matchday: season.currentMatchday,
  ));
}

/// One line summarising a window that has just shut.
///
/// Counts the user's own business from the ledger and reports the money both
/// ways, so the feed answers "did the window actually do anything?" instead of
/// letting the deadline slide past with a single headline.
TransferNewsItem _windowSummary(CareerSession session, TransferWindow shut) {
  final business = _windowBusiness(session, shut);
  final arrivals = business.arrivals;
  final loansIn = business.loansIn;
  final departures = business.departures;
  final loansOut = business.loansOut;
  final spent = business.spent;
  final received = business.received;

  final inText = [
    if (arrivals > 0) '$arrivals signing${arrivals == 1 ? '' : 's'}',
    if (loansIn > 0) '$loansIn loan${loansIn == 1 ? '' : 's'} in',
  ];
  final outText = [
    if (departures > 0) '$departures sale${departures == 1 ? '' : 's'}',
    if (loansOut > 0) '$loansOut loan${loansOut == 1 ? '' : 's'} out',
  ];
  final closed = TransferMarketService.money(spent);
  final banked = TransferMarketService.money(received);
  final body = inText.isEmpty && outText.isEmpty
      ? 'You did no business in it. The squad is exactly as it was.'
      : '${inText.isEmpty ? 'No arrivals' : inText.join(' and ')}'
          '${outText.isEmpty ? ', nobody left' : ', ${outText.join(' and ')}'}. '
          '$closed spent, $banked banked.';

  return TransferNewsItem(
    type: 'summary',
    title: 'The ${shut.label.toLowerCase()} has shut',
    body: body,
    matchday: session.season.currentMatchday,
  );
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
    // Cup results decide a bracket, never the table.
    if (fixture.competition == 'league') {
      _applyResultToRecords(season, fixture);
    }
  }
}

/// Simulates the rest of the current round using real squad strengths.
void _simulateRemainingFixtures(
  WidgetRef ref,
  CareerSession session,
  int round,
) {
  final db = ref.read(playerDatabaseProvider).valueOrNull;
  // The difficulty setting scales the opposition, never the user's own club —
  // "Hard" has to mean the rivals are tougher, not that the manager is handed a
  // stronger squad. "Normal" is a neutral 1.0, so default careers are
  // bit-for-bit unchanged.
  final boost = difficultyStrengthMultiplier(ref.read(difficultyProvider));
  final strengths = <String, double>{
    if (db != null)
      for (final t in db.teams)
        t.id: t.id == session.team.id
            ? _squadStrength(t)
            : _squadStrength(t) * boost,
  };
  simulateRound(session.season, round, strengths: strengths);
}

/// The board's verdict on the manager after a matchday.
class BoardVerdict {  const BoardVerdict({
    required this.sacked,
    required this.risk,
    required this.reason,
  });

  final bool sacked;
  final double risk;
  final String reason;
}

/// Points per game the board expects, by the club's standing.
///
/// Reputation 40 (bottom half) reads ~0.95 PPG — staying in the division is
/// the job — while reputation 100 (an institution) reads ~1.90. A flat
/// 1.35 expectation made every club equally pressureless: Bayern and a
/// relegation candidate were judged by the same ruler, which was exactly why
/// the gauge never hurt.
double boardExpectedPoints(int reputation) {
  const floorRep = 40.0;
  const floorPpg = 0.95;
  const span = 0.95;
  final t = (reputation.clamp(40, 100) - floorRep) / 60.0;
  return floorPpg + t * span;
}

/// How hard a matchday's form moves the sack gauge, by club standing.
///
/// Bigger clubs get a sharper ruler: their budgets demand results. Small
/// clubs amortize a bad month more forgivingly.
double boardSensitivity(int reputation) =>
    (8.0 + (reputation.clamp(40, 100) - 40) * 0.08).clamp(8.0, 14.0);

/// How many matchdays of form the board weighs.
const int _boardFormWindow = 5;

/// Sacking risk at or above this ends the career.
const double _boardSackThreshold = 100.0;

/// Evaluates the board after a matchday and moves the sack-risk gauge.
///
/// Returns the verdict so the match screen can tell the manager what the
/// board decided. Risk is derived from recent form, which makes it move in
/// both directions: a winning run buys the manager room, a losing one closes
/// it. Deterministic — the same results always produce the same verdict.
BoardVerdict? evaluateBoard(WidgetRef ref, CareerSession session) {
  final results = session.userResults;
  if (results.isEmpty) {
    const note = 'The board is still settling in.';
    session.boardNote = note;
    return BoardVerdict(
      sacked: false,
      risk: session.manager.sackablePercent,
      reason: note,
    );
  }

  final recent = results.length <= _boardFormWindow
      ? results
      : results.sublist(results.length - _boardFormWindow);
  final avgPoints = recent.reduce((a, b) => a + b) / recent.length;
  final expected = boardExpectedPoints(session.team.reputation);
  final delta = (expected - avgPoints) * boardSensitivity(session.team.reputation);
  var risk = (session.manager.sackablePercent + delta).clamp(0.0, 100.0);

  final sacked =
      risk >= _boardSackThreshold && ref.read(isSackingEnabledProvider);
  final reason = sacked
      ? 'Sacked after ${recent.length} matchdays without results the board '
          'would accept.'
      : delta > 0.5
          ? 'The board is watching closely after ${recent.length} poor '
              'matchdays. It expects about ${expected.toStringAsFixed(2)} '
              'points a game.${_standingRemark(session.team.reputation)}'
          : delta < -0.5
              ? 'The board is happy with recent results.'
              : 'The board is watching.';
  if (sacked) risk = 100.0;

  session.manager.sackablePercent = risk;
  session.boardNote = reason;
  return BoardVerdict(sacked: sacked, risk: risk, reason: reason);
}

/// One sentence of standing context the board adds to a poor-run note —
/// why the expectation is what it is at this club's level.
String _standingRemark(int reputation) {
  if (reputation >= 85) return ' A club your size is measured in silverware.';
  if (reputation >= 70) return ' The recruitment was supposed to deliver.';
  return ' Staying up is the minimum this board will accept.';
}

/// Ends the current career because the board sacked the manager.
///
/// Clears the in-memory session and erases the save, so the main menu cannot
/// offer to "Continue" a career that no longer exists. Returns false when
/// there was no career to sack.
Future<bool> sackManager(WidgetRef ref) async {
  final session = ref.read(careerSessionProvider);
  if (session == null) return false;
  ref.read(careerSessionProvider.notifier).state = null;
  ref.read(lastMatchResultProvider.notifier).state = null;
  ref.read(shortlistProvider.notifier).state = {};
  ref.read(transferOffersProvider.notifier).state = [];
  ref.read(savedTacticsProvider.notifier).state = [];
  await SaveService().deleteCareer();
  // A save no longer exists, so the main menu must stop offering Continue.
  ref.invalidate(hasSaveProvider);
  return true;
}

/// Copies the persisted sack-risk setting onto the active manager.
///
/// The setting seeds a new career and is the single place the value is
/// edited; [Manager.sackablePercent] is the only thing gameplay reads, so
/// this keeps the two from drifting apart. Deliberately does not persist:
/// callers driving it from a slider persist once on release instead of on
/// every frame of the drag.
void syncSackRiskToManager(WidgetRef ref) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return;
  session.manager.sackablePercent = ref.read(sackablePercentProvider);
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

  // No fixture, but not a week off: the training ground still runs, at the
  // reduced rate a week without a match is worth.
  _developTrainingWeek(session);

  final advanced = round + 1;
  final season = SeasonState(
    leagueId: session.season.leagueId,
    currentMatchday: advanced,
    currentYear: session.season.currentYear,
    isPreSeason: false,
    isWinterBreak: advanced == session.season.winterBreakRound,
    records: session.season.records,
    rounds: session.season.rounds,
    cup: session.season.cup,
  );
  final updated = _rebuildSession(session, season);
  updated.team.leaguePosition = season.positionOf(session.team.id);
  advanceTransferDesk(ref, updated);
  // Cup rounds finish on the club's off-days too: without settling here a
  // knockout round where the club is already out would never progress.
  _settleCupAfterRound(updated);
  ref.read(careerSessionProvider.notifier).state = updated;
  _persist(ref, updated);
}

/// Cup bookkeeping for the matchday that just wrapped.
///
/// A cup round completes exactly like a league round: the manager's tie is
/// recorded first, then every other pending fixture in the same round is
/// simulated. When all ties of a cup round are played the bracket advances;
/// the manager's own fate — knocked out at some stage, or lifting the cup —
/// becomes the board's note and, for a final win, a trophy that permanently
/// lives on the session.
///
/// Idempotent: re-applying a matchday after a crash re-derives everything
/// from played fixtures, and the trophy is set-guarded.
void _settleCupAfterRound(CareerSession session) {
  final season = session.season;
  final cup = season.cup;
  if (cup == null) return;
  CupService.progressCup(season);

  // The highest cup round that is drawn AND fully played decides what story
  // the board hears right now.
  var settled = -1;
  List<Fixture>? settledRound;
  for (var k = 0; k < cup.anchors.length; k++) {
    final round = season.rounds[cup.anchors[k]];
    if (round.isEmpty || round.any((f) => !f.played)) break;
    settled = k;
    settledRound = round;
  }
  if (settledRound == null) return;

  final user = session.team;
  final tie = settledRound.where((f) => f.involves(user.id)).firstOrNull;
  if (tie == null) return; // the club sat this stage out already

  if (settled == cup.anchors.length - 1) {
    // The final: a trophy or heartbreak, one way or the other.
    final label = '${cup.name} ${season.currentYear}';
    final winner = CupService.cupWinnerOf(season);
    if (winner == null) return; // still undecided (impossible here, but safe)
    if (winner == user.id) {
      if (!session.trophies.contains(label)) {
        session.trophies.add(label);
      }
      // A cup run settles the board down: silverware is currency.
      session.manager.sackablePercent =
          (session.manager.sackablePercent + _cupWinRelief).clamp(0.0, 100.0);
      session.boardNote =
          'Champions! The $label is in the cabinet. Even the board '
          'said something nice for once.';
    } else {
      session.boardNote =
          'Beaten in the $label final. Hillsborough knows what that feels '
          'like, and so does the board.';
    }
    return;
  }

  // Mid-bracket eliminations read through the next round's draw: alive
  // clubs find their name in it, gone clubs do not.
  final next = settled + 1;
  if (next >= cup.anchors.length) return;
  final nextFixtures = season.rounds[cup.anchors[next]];
  if (nextFixtures.isEmpty) return; // nothing drawn (guarded upstream)
  if (nextFixtures.any((f) => f.involves(user.id))) return;
  if (cup.byes[next] == user.id) return; // drew a bye, not a knockout

  session.boardNote =
      'Out of the ${cup.name} at the '
      '${CupService.roundNameOf(season, settled)}. The board wanted a cup '
      'run to go with the budget.';
}

/// Sack-risk credited when the club lifts a cup.
const double _cupWinRelief = -15.0;

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
    cup: session.season.cup,
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
  // A promoted prospect earns a first professional wage rather than nothing,
  // so the wage bill the board sees includes him.
  player.weeklyWage = FinancialService().expectedWeeklyWage(player);
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

/// The club's weekly wage bill, including the wages it is still paying for
/// players out on loan (they are not in [Team.squad], so nothing else counts
/// them).
double weeklyWageBill(Team team) =>
    FinancialService().calculateWageBill(team) + team.loanedOutWages;

/// Headroom left under the club's weekly wage ceiling, or null when no ceiling
/// is configured (older saves and stub clubs).
double? wageHeadroom(Team team) =>
    team.wageBudget <= 0 ? null : team.wageBudget - weeklyWageBill(team);

/// Why a deal would break the wage ceiling, or null when it fits.
///
/// [addedWage] is the weekly cost the deal adds to the bill; a loan where the
/// club only covers part of a wage passes its share. Returns a message ready
/// for [transferBlockReasonProvider] so every caller explains the refusal the
/// same way.
String? wageCeilingRefusal(Team team, double addedWage) {
  if (team.wageBudget <= 0) return null;
  final projected = weeklyWageBill(team) + addedWage;
  if (projected <= team.wageBudget) return null;
  return 'That wage would take the bill to '
      '${TransferMarketService.money(projected)}/wk against a wage budget of '
      '${TransferMarketService.money(team.wageBudget)}/wk. You have '
      '${TransferMarketService.money(wageHeadroom(team)!.clamp(0, double.infinity))}/wk '
      'of room.';
}

/// Gate receipts the club can still expect this season.
///
/// A new career has banked nothing, so FFP has to be judged against projected
/// revenue from the club's remaining home fixtures rather than the cash
/// already in the bank. Without this the 1.0M fallback inside
/// [FinancialService.calculateFFPRatio] would make every signing illegal for
/// the first half of a season.
double _projectedSeasonRevenue(Team team, SeasonState season) {
  var total = team.revenue;
  for (var round = season.currentMatchday;
      round < season.rounds.length;
      round++) {
    final fixture = season.userFixtureForRound(round, team.id);
    if (fixture != null && fixture.isHomeFor(team.id)) {
      total += FinancialService().estimateGateReceipts(team);
    }
  }
  return total;
}

/// Buys a player from the transfer market if the budget allows.
///
/// When FFP enforcement is on, a signing that would push the wage bill past
/// [ffpWageRatioLimit] of projected revenue is refused; the reason is left in
/// [transferBlockReasonProvider] for the screen to surface.
bool buyPlayer(
  WidgetRef ref,
  Player player,
  int fee, {
  int? wage,
  int? contractYears,
}) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return false;
  if (fee > session.team.transferBudget) {
    ref.read(transferBlockReasonProvider.notifier).state =
        'The fee is more than the transfer budget.';
    return false;
  }

  final finance = FinancialService();
  final newWage = wage?.toDouble() ?? player.ovr * 1200.0;
  // The wage ceiling is the board's, not FFP's: it applies whether or not
  // enforcement is switched on, because it is what the club can actually pay.
  final refusal = wageCeilingRefusal(session.team, newWage);
  if (refusal != null) {
    ref.read(transferBlockReasonProvider.notifier).state = refusal;
    return false;
  }
  if (ref.read(ffpEnabledProvider)) {
    final projectedBill = finance.calculateWageBill(session.team) + newWage;
    final revenue = _projectedSeasonRevenue(session.team, session.season);
    if (revenue <= 0 || projectedBill / revenue > ffpWageRatioLimit) {
      ref.read(transferBlockReasonProvider.notifier).state =
          'FFP rules block this: the wage bill would reach '
          '${(projectedBill / (revenue <= 0 ? 1 : revenue) * 100).round()}% '
          'of projected revenue, above the '
          '${(ffpWageRatioLimit * 100).round()}% limit.';
      return false;
    }
  }

  ref.read(transferBlockReasonProvider.notifier).state = null;
  final fromTeam = player.currentTeam;
  player.currentTeam = session.team.name;
  session.team.squad.add(player);
  session.team.transferBudget -= fee;
  player.weeklyWage = newWage;
  if (contractYears != null) {
    player.contractExpiry =
        DateTime(session.season.currentYear + contractYears, 6, 30);
  }
  player.transferValue = finance.calculateTransferValue(
    player,
    seasonYear: session.season.currentYear,
  );

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
///
/// [buyerClub] is who the player joins. Without it he would simply vanish:
/// the selling club stops holding him, nobody gains him, and the news feed
/// would claim a move that the world never saw.
bool sellPlayer(WidgetRef ref, Player player, int fee, {String? buyerClub}) {
  final session = ref.read(careerSessionProvider);
  if (session == null) return false;
  if (session.team.squad.length <= 16) {
    ref.read(transferBlockReasonProvider.notifier).state =
        'Your squad must keep at least 16 players.';
    return false;
  }
  ref.read(transferBlockReasonProvider.notifier).state = null;

  final db = ref.read(playerDatabaseProvider).valueOrNull;
  final buyer = buyerClub == null
      ? null
      : db?.teams.where((t) => t.name == buyerClub).firstOrNull;

  session.team.squad.removeWhere((p) => p.id == player.id);
  session.team.transferBudget += fee;

  if (buyer != null) {
    for (final team in db!.teams) {
      team.squad.removeWhere((p) => p.id == player.id);
    }
    player.currentTeam = buyer.name;
    buyer.squad.add(player);
    session.transferDesk.recordMove(TransferMove(
      playerId: player.id,
      playerName: player.name,
      fromClub: session.team.name,
      toClub: buyer.name,
      kind: 'permanent',
      fee: fee,
      wage: player.weeklyWage.round(),
      year: session.season.currentYear,
      matchday: session.season.currentMatchday,
    ));
  }

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
///
/// [rankIndex] lets list-heavy callers pay the O(n log n) sort once per
/// build instead of once per visible row (see [squadRankIndex]).
String squadStatusOf(Player player, List<Player> squad,
    {Map<int, int>? rankIndex}) {
  final custom = player.hiddenAttributes['squadRole'];
  if (custom is String && custom.isNotEmpty) return custom;
  final ranks = rankIndex ?? squadRankIndex(squad);
  final rank = ranks[player.id] ?? -1;
  if (rank < 0) return 'Squad Player';
  if (rank < 3) return 'Key Player';
  if (rank < 7) return 'First Team';
  if (rank < 12) return 'Squad Player';
  if (rank < 18) return 'Rotation';
  return 'Prospect';
}

/// Squad players ranked by OVR: `id -> rank` (0 is the best).
///
/// Squad lists render one row per player and used to re-copy + re-sort the
/// full squad inside every row builder; the scroll jam showed up as the
/// squad screen stuttering on every frame.
Map<int, int> squadRankIndex(List<Player> squad) {
  final sorted = [...squad]..sort((a, b) => b.ovr.compareTo(a.ovr));
  return {for (var i = 0; i < sorted.length; i++) sorted[i].id: i};
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
///
/// Emits a shallow copy rather than the same instance: `StateProvider` only
/// notifies when the emitted value is a different object, so re-assigning the
/// current session was a no-op. The copy shares the team, season and academy
/// list, so every in-place edit is visible through the new object.
void _bumpState(WidgetRef ref) {
  final notifier = ref.read(careerSessionProvider.notifier);
  final session = notifier.state;
  if (session == null) return;
  notifier.state = session.shallowCopy();
}

/// Public counterpart to [_bumpState] for screens that mutate the session
/// directly (tactics changes, half-time team talks).
void notifySessionChanged(WidgetRef ref) {
  _bumpState(ref);
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

/// Ages the whole world by a year and rolls rival squads' season development.
///
/// Rivals have no week-by-week record — only the manager's matches produce
/// ratings — so their growth (and decline) is applied in one pass over the
/// closed season instead of every matchday. Each player's net OVR change is
/// recorded on [CareerSession.worldGrowth] so the next restore can replay it
/// on top of the rebuilt database, the same way the transfer ledger replays
/// ownership.
///
/// Runs after the loan season-end resolution, so returning players belong to
/// exactly one squad before anyone is aged.
void _closeSeasonDevelopment(CareerSession session, PlayerDatabase? db) {
  final year = session.season.currentYear;
  final league = session.team.leagueId;

  // A player borrowed in this season is on the manager's books right now and
  // must not also roll through his owner's season; ids keep everyone to one
  // birthday per close season.
  final aged = <int>{};
  void ageOne(Player player) {
    if (aged.add(player.id)) player.age = min(45, player.age + 1);
  }

  for (final player in session.team.squad) {
    ageOne(player);
  }
  for (final prospect in session.youthPlayers) {
    prospect.age += 1;
  }

  if (db == null) return;
  final squadIds = {for (final p in session.team.squad) p.id};
  for (final rival in db.teams.where((t) => t.leagueId == league)) {
    if (rival.id == session.team.id) continue;
    for (final player in rival.squad) {
      if (squadIds.contains(player.id)) continue;
      ageOne(player);
      final delta = DevelopmentService.developSeason(
        player,
        leagueId: league,
        year: year,
      );
      if (delta != 0) {
        session.worldGrowth[player.id] =
            (session.worldGrowth[player.id] ?? 0) + delta;
      }
    }
  }
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

  final nextRounds = buildRounds([for (final t in rivals) t.id], rng: Random());
  // Every new season gets a cup, which is also how older saves (schema v2
  // was cupless) come into the fold — at their next rollover, so a restored
  // mid-season save never has its matchday counter re-mapped underneath it.
  final cup = CupService.attachCup(
    rounds: nextRounds,
    teamIds: [for (final t in rivals) t.id],
    leagueId: team.leagueId,
    currentYear: season.currentYear + 1,
  );

  final nextSeason = SeasonState(
    leagueId: team.leagueId,
    currentMatchday: 0,
    currentYear: season.currentYear + 1,
    isPreSeason: false,
    isWinterBreak: false,
    records: {for (final t in rivals) t.id: LeagueRecord()},
    rounds: nextRounds,
    cup: cup,
  );

  // Loans end with the season: borrowed players go home, loaned-out players
  // come back, and everyone's full wage is restored.
  for (final loan in [...session.transferDesk.loans]) {
    final player =
        db?.players.where((p) => p.id == loan.playerId).firstOrNull;
    if (player == null) continue;
    if (loan.toClub == team.name) {
      // Borrowed in: back to the owner.
      team.squad.removeWhere((p) => p.id == loan.playerId);
      player
        ..weeklyWage = loan.wage.toDouble()
        ..hiddenAttributes.remove('onLoanFrom')
        ..hiddenAttributes.remove('loanUntilYear')
        ..currentTeam = loan.fromClub;
      final owner =
          db?.teams.where((t) => t.name == loan.fromClub).firstOrNull;
      if (owner != null && !owner.squad.any((p) => p.id == loan.playerId)) {
        owner.squad.add(player);
      }
    } else {
      // Loaned out: home again, on his full wage.
      player
        ..weeklyWage = loan.wage.toDouble()
        ..currentTeam = team.name;
      if (!team.squad.any((p) => p.id == loan.playerId)) {
        team.squad.add(player);
      }
    }
    session.transferDesk.recordMove(TransferMove(
      playerId: player.id,
      playerName: player.name,
      fromClub: loan.toClub,
      toClub: loan.fromClub,
      kind: 'loanReturn',
      fee: 0,
      wage: loan.wage,
      year: nextSeason.currentYear,
      matchday: 0,
    ));
  }
  session.transferDesk.loans.clear();
  team.loanedOutWages = 0;
  // A new season is a new sanction: the board raises the wage ceiling to at
  // least the bill the club starts the year with, plus headroom. Without this
  // a squad that grew during the window would be over its own limit on day
  // one and unable to sign anyone at all. How much headroom is a difficulty
  // decision — tight sanctions are what "Hard" is about.
  final openingBill = weeklyWageBill(team);
  if (openingBill > 0) {
    team.wageBudget = max(
        team.wageBudget,
        openingBill *
            wageCeilingHeadroomFactor(ref.read(difficultyProvider)));
  }

  // The close of the season is when the world ages: the squad, the academy
  // and every rival roll a year older, and rivals develop a whole season in
  // one pass because only the manager's matches produce weekly records.
  _closeSeasonDevelopment(session, db);

  final updated = _rebuildSession(session, nextSeason);
  updated.userResults.clear();
  // No deal survives the final whistle of a season. Unfinished talks are
  // closed and last season's bids lapse; the new window opens with fresh
  // asking prices and fresh rivals.
  updated.transferDesk.negotiations.removeWhere((n) => n.isActive);
  updated.transferDesk.incomingBids.clear();
  updated.transferDesk.addNews(TransferNewsItem(
    type: 'deadline',
    title: 'A new season begins',
    body: 'The summer window is open. Squad needs, asking prices and rival '
        'interest have all been reset.',
    matchday: 0,
  ));
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
