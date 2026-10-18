import 'dart:math';

import '../constants/game_constants.dart';
import '../models/player.dart';
import '../models/youth_player.dart';

/// Training and long-term development: the engine behind the Development tab.
///
/// Growth is fractional. Every week adds a slice of progress — scaled by age,
/// game time and the player's training focus — and when the slice tips past
/// 1.0 the player gains an OVR point with the attributes around his focus
/// leaning forward alongside it. `hiddenAttributes['potential']` is the
/// ceiling; from thirty-one onwards the body starts taking points back.
///
/// Everything is seeded from league, year, matchday and player id, so the
/// same week replays identically after a restore and tests can pin outcomes
/// without mocking randomness.
class DevelopmentService {
  /// Attribute groups the training focuses sharpen, matching the focuses
  /// offered on the player sheet (`kTrainingFocuses`).
  static const Map<String, List<String>> _focusAttributes = {
    'Finishing': ['sho', 'finishing', 'positioning', 'shotPower', 'volleys'],
    'Passing': ['pas', 'vision', 'shortPassing', 'longPassing', 'crossing'],
    'Pace': ['pac', 'acceleration', 'sprintSpeed', 'agility'],
    'Defending': [
      'def',
      'interceptions',
      'defAwareness',
      'standingTackle',
      'slidingTackle',
    ],
    'Physical': ['phy', 'staminaStat', 'strength', 'jumping', 'aggression'],
  };

  /// Goalkeeping is its own group: the focus raises the GK-only attributes.
  static const List<String> _goalkeepingAttributes = [
    'gkDiving',
    'gkHandling',
    'gkKicking',
    'gkPositioning',
    'gkReflexes',
  ];

  /// Where the fractional accumulation lives on the player.
  static const String progressKey = 'growthProgress';

  /// The academy trains most days of the week.
  static const double _youthWeeklyChance = youthGrowthMultiplier * 3;

  /// One week of development for a senior player.
  ///
  /// [minutes] is how long he actually played this week: a full match counts
  /// in full, a cameo or a seat on the bench only partially, and an injured
  /// player is in the treatment room rather than on the grass.
  ///
  /// Pass a shared [rng] when replaying many weeks in one go (rival squads at
  /// the rollover); otherwise the week seeds itself from the identifiers.
  ///
  /// Returns true when the player's OVR changed.
  static bool developWeek(
    Player player, {
    required int minutes,
    required String leagueId,
    required int year,
    required int matchday,
    Random? rng,
  }) {
    if (player.isInjured) return false;
    final random = rng ??
        Random('$leagueId:$year:$matchday:dev:${player.id}'.hashCode.abs());

    // Past thirty the body goes first: points come off rather than on, and
    // the decline accelerates in the mid-thirties.
    if (player.age >= 31) {
      final declineChance = player.age >= 34 ? 0.045 : 0.02;
      if (random.nextDouble() < declineChance * _activityFactor(minutes)) {
        _applyDecline(player);
        return true;
      }
      return false;
    }

    final potential =
        (player.hiddenAttributes['potential'] as num?)?.toInt() ?? player.ovr;
    if (player.ovr >= potential) return false;

    final focus = player.hiddenAttributes['trainingFocus'] as String?;
    final gain = _weeklyRate(player.age) *
        _activityFactor(minutes) *
        (focus == null ? 1.0 : 1.15);
    final progress =
        ((player.hiddenAttributes[progressKey] as num?)?.toDouble() ?? 0.0) +
            gain;
    if (progress < 1.0) {
      player.hiddenAttributes[progressKey] = progress;
      return false;
    }
    player.hiddenAttributes[progressKey] = progress - 1.0;
    _applyGrowth(player, focus);
    return true;
  }

  /// A whole season of development for a rival player.
  ///
  /// Rivals have no minute-by-minute record — only the manager's matches
  /// produce ratings — so their season is replayed here week by week with a
  /// rotation-shaped minutes roll. Returns the net OVR change applied, which
  /// the caller records so the growth can be replayed on the next restore.
  static int developSeason(
    Player player, {
    required String leagueId,
    required int year,
    int weeks = 38,
  }) {
    final before = player.ovr;
    final random =
        Random('$leagueId:$year:rival-season:${player.id}'.hashCode.abs());
    for (var week = 0; week < weeks; week++) {
      // Starters, rotation and bench warmers in one honest spread.
      final minutes =
          random.nextBool() ? 50 + random.nextInt(41) : random.nextInt(50);
      developWeek(
        player,
        minutes: minutes,
        leagueId: leagueId,
        year: year,
        matchday: week,
        rng: random,
      );
    }
    return player.ovr - before;
  }

  /// Re-applies recorded season growth on top of a freshly rebuilt world.
  ///
  /// Rival squads come back from the CSV every session, so their growth is
  /// stored as a net OVR delta per player id and layered back on here — the
  /// same trick [TransferMarketService.applyTransferLedger] plays for
  /// ownership.
  static void applyWorldGrowth(
    Iterable<Player> players,
    Map<int, int> growth,
  ) {
    if (growth.isEmpty) return;
    for (final player in players) {
      final delta = growth[player.id];
      if (delta == null || delta == 0) continue;
      player.ovr = (player.ovr + delta).clamp(40, 99);
    }
  }

  /// One week of academy training for a prospect.
  ///
  /// Returns true when his current ability ticked up.
  static bool developYouth(
    YouthPlayer prospect, {
    required String leagueId,
    required int year,
    required int matchday,
  }) {
    if (prospect.currentStats >= prospect.potential) return false;
    final random = Random('$leagueId:$year:$matchday:youth:'
            '${prospect.name}:${prospect.age}'
        .hashCode
        .abs());
    if (random.nextDouble() >= _youthWeeklyChance) return false;
    prospect.currentStats += 1;
    return true;
  }

  /// Weekly growth slices. Youth grow fastest, the peak years slower, and
  /// the thirties are the decline path in [developWeek].
  static double _weeklyRate(int age) => age <= 21
      ? youngPlayerGrowthRate
      : age <= 28
          ? peakPlayerGrowthRate
          : oldPlayerGrowthRate;

  /// How much of a week's work actually counts: a full match in his legs is
  /// worth the most; a bench week is still training, just a smaller one.
  static double _activityFactor(int minutes) {
    if (minutes >= 60) return 1.0;
    if (minutes >= 15) return 0.7;
    return 0.45;
  }

  /// Applies an OVR point: every core takes a small step and the training
  /// focus group — the one the manager chose on the player sheet — takes a
  /// bigger one, so what a player works on shows up where it counts.
  static void _applyGrowth(Player player, String? focus) {
    player.ovr = min(99, player.ovr + 1);
    final group = _focusAttributes[focus] ?? const <String>[];
    for (final core in const ['pac', 'sho', 'pas', 'dri', 'def', 'phy']) {
      if (!group.contains(core)) _bump(player, core, 1);
    }
    for (final key in group) {
      _bump(player, key, 2);
    }
    if (focus == 'Goalkeeping') {
      for (final key in _goalkeepingAttributes) {
        _bump(player, key, 2);
      }
    }
  }

  /// A step lost to father time: OVR down one and the physical side goes
  /// faster than the technical one, which is how ageing squads get slow.
  static void _applyDecline(Player player) {
    player.ovr = max(40, player.ovr - 1);
    _bump(player, 'phy', -2);
    _bump(player, 'pac', -1);
    _bump(player, 'dri', -1);
    _bump(player, 'sho', -1);
    _bump(player, 'staminaStat', -1);
  }

  /// Moves one named attribute by [amount], clamped to a sane band. A null
  /// GK attribute stays null (the player is not a goalkeeper).
  static void _bump(Player player, String key, int amount) {
    int grow(int? value) => ((value ?? 50) + amount).clamp(30, 99);
    switch (key) {
      case 'pac':
        player.pac = grow(player.pac);
      case 'sho':
        player.sho = grow(player.sho);
      case 'pas':
        player.pas = grow(player.pas);
      case 'dri':
        player.dri = grow(player.dri);
      case 'def':
        player.def = grow(player.def);
      case 'phy':
        player.phy = grow(player.phy);
      case 'acceleration':
        player.acceleration = grow(player.acceleration);
      case 'sprintSpeed':
        player.sprintSpeed = grow(player.sprintSpeed);
      case 'positioning':
        player.positioning = grow(player.positioning);
      case 'finishing':
        player.finishing = grow(player.finishing);
      case 'shotPower':
        player.shotPower = grow(player.shotPower);
      case 'longShots':
        player.longShots = grow(player.longShots);
      case 'volleys':
        player.volleys = grow(player.volleys);
      case 'penalties':
        player.penalties = grow(player.penalties);
      case 'vision':
        player.vision = grow(player.vision);
      case 'crossing':
        player.crossing = grow(player.crossing);
      case 'freeKickAccuracy':
        player.freeKickAccuracy = grow(player.freeKickAccuracy);
      case 'shortPassing':
        player.shortPassing = grow(player.shortPassing);
      case 'longPassing':
        player.longPassing = grow(player.longPassing);
      case 'curve':
        player.curve = grow(player.curve);
      case 'agility':
        player.agility = grow(player.agility);
      case 'balance':
        player.balance = grow(player.balance);
      case 'reactions':
        player.reactions = grow(player.reactions);
      case 'ballControl':
        player.ballControl = grow(player.ballControl);
      case 'composure':
        player.composure = grow(player.composure);
      case 'interceptions':
        player.interceptions = grow(player.interceptions);
      case 'headingAccuracy':
        player.headingAccuracy = grow(player.headingAccuracy);
      case 'defAwareness':
        player.defAwareness = grow(player.defAwareness);
      case 'standingTackle':
        player.standingTackle = grow(player.standingTackle);
      case 'slidingTackle':
        player.slidingTackle = grow(player.slidingTackle);
      case 'jumping':
        player.jumping = grow(player.jumping);
      case 'staminaStat':
        player.staminaStat = grow(player.staminaStat);
      case 'strength':
        player.strength = grow(player.strength);
      case 'aggression':
        player.aggression = grow(player.aggression);
      case 'gkDiving':
        if (player.gkDiving != null) player.gkDiving = grow(player.gkDiving);
      case 'gkHandling':
        if (player.gkHandling != null) {
          player.gkHandling = grow(player.gkHandling);
        }
      case 'gkKicking':
        if (player.gkKicking != null) player.gkKicking = grow(player.gkKicking);
      case 'gkPositioning':
        if (player.gkPositioning != null) {
          player.gkPositioning = grow(player.gkPositioning);
        }
      case 'gkReflexes':
        if (player.gkReflexes != null) {
          player.gkReflexes = grow(player.gkReflexes);
        }
    }
  }
}
