import 'dart:math';

import '../models/player.dart';

/// A rolled injury: what it is and how long it keeps the player out.
class Injury {
  const Injury(this.type, this.weeks);

  /// The medical name shown on the player sheet (e.g. "Hamstring strain").
  final String type;

  /// Whole weeks out, counted in matchdays from the moment it happened.
  final int weeks;
}

/// The treatment room: turning match scares and training niggles into real
/// absences, and clearing them again when the calendar catches up.
///
/// The match engine already reports every time a player goes down. Most of
/// those scares are run off with a spray; the small remainder becomes an
/// absence with a type and an expected return date, so a squad carries
/// 0-2 players on the physio's table at any time rather than never or always.
///
/// The clock is the matchday counter, not the wall clock: matchday 0 of a
/// season sits at the start of August, so an expected return is a real date
/// ("back around 12 Nov") that keeps its meaning across sessions — and a
/// severe injury picked up in May genuinely eats into the next season.
///
/// Rival squads never roll injuries. Their week-by-week record does not exist
/// (only the manager's matches produce minute-by-minute reports) and their
/// state is rebuilt from the CSV every session, so an injury would have
/// nothing to attach to. The manager's own squad carries them naturally,
/// because an injury lives on the player and survives save and restore.
class InjuryService {
  /// Matchday 0 of a season sits at the start of August.
  static DateTime dateOfMatchday(int year, int matchday) =>
      DateTime(year, 8, 1).add(Duration(days: 7 * matchday));

  /// Whole weeks until [player] is fit again, 0 when he already is.
  static int weeksOut(
    Player player, {
    required int year,
    required int matchday,
  }) {
    final date = player.injuryReturnDate;
    if (!player.isInjured || date == null) return 0;
    final days = date.difference(dateOfMatchday(year, matchday)).inDays;
    return days <= 0 ? 0 : (days / 7).ceil();
  }

  /// The aftermath of every injury scare in a match report.
  ///
  /// [downPlayers] are the names that went down (one entry per event), a
  /// player who went down more than once is treated once, and an already
  /// injured player is not re-injured. Returns the players newly in the
  /// treatment room, so the caller can put them in the news.
  static List<Player> applyMatchInjuries(
    Iterable<Player> squad,
    Iterable<String> downPlayers, {
    required String leagueId,
    required int year,
    required int matchday,
  }) {
    final byName = {for (final player in squad) player.name: player};
    final injured = <Player>[];
    for (final name in downPlayers) {
      final player = byName[name];
      if (player == null || player.isInjured) continue;
      final injury = rollMatchInjury(
        player,
        leagueId: leagueId,
        year: year,
        matchday: matchday,
      );
      if (injury == null) continue;
      _applyInjury(player, injury, year: year, matchday: matchday);
      injured.add(player);
    }
    return injured;
  }

  /// Rolls one scare: almost half become real absences, the rest are run off.
  ///
  /// The bands are deliberately top-heavy — a week or two out is the common
  /// case, half a season is a story worth remembering — which keeps the
  /// treatment room busy without emptying the squad.
  static Injury? rollMatchInjury(
    Player player, {
    required String leagueId,
    required int year,
    required int matchday,
  }) {
    final random =
        Random('$leagueId:$year:$matchday:injury:${player.id}'.hashCode.abs());
    if (random.nextDouble() < _runOffChance) return null;
    final severity = random.nextDouble();
    if (severity < 0.38) return Injury(_pick(random, _knocks), 1);
    if (severity < 0.70) return Injury(_pick(random, _strains), 2);
    if (severity < 0.87) return Injury(_pick(random, _tears), 3);
    if (severity < 0.97) return Injury(_pick(random, _fractures), 5 + random.nextInt(3));
    return Injury(_pick(random, _severe), 11 + random.nextInt(4));
  }

  /// A week on the training ground can still end in the treatment room: a
  /// small per-player chance of a minor knock, so the physio's table is not
  /// only fed by matches.
  static bool rollTrainingKnock(
    Player player, {
    required String leagueId,
    required int year,
    required int matchday,
  }) {
    if (player.isInjured) return false;
    final random =
        Random('$leagueId:$year:$matchday:knock:${player.id}'.hashCode.abs());
    if (random.nextDouble() >= _trainingKnockChance) return false;
    _applyInjury(player, Injury(_pick(random, _knocks), 1),
        year: year, matchday: matchday);
    return true;
  }

  /// Clears everyone whose expected return has arrived. Returns the players
  /// who came back (so callers can react), otherwise schedules are already
  /// consistent: a fit player is simply picked again.
  static List<Player> healDue(
    Iterable<Player> squad, {
    required int year,
    required int matchday,
  }) {
    final now = dateOfMatchday(year, matchday);
    final healed = <Player>[];
    for (final player in squad) {
      if (!player.isInjured) continue;
      final date = player.injuryReturnDate;
      // An injury with no return date is legacy data: clear it rather than
      // leave the player in limbo forever.
      if (date != null && date.isAfter(now)) continue;
      player.isInjured = false;
      player.injuryType = null;
      player.injuryReturnDate = null;
      healed.add(player);
    }
    return healed;
  }

  /// Scares that are run off with the physio's spray.
  static const double _runOffChance = 0.42;

  /// Per-player, per-week chance of a training-ground knock.
  static const double _trainingKnockChance = 0.004;

  static const List<String> _knocks = [
    'Dead leg',
    'Knock',
    'Twisted ankle',
    'Bruised foot',
  ];
  static const List<String> _strains = [
    'Hamstring strain',
    'Groin strain',
    'Calf tightness',
  ];
  static const List<String> _tears = [
    'Hamstring tear',
    'Ankle ligament damage',
    'Shoulder injury',
  ];
  static const List<String> _fractures = [
    'Metatarsal fracture',
    'Cracked rib',
    'Knee ligament damage',
  ];
  static const List<String> _severe = [
    'ACL rupture',
    'Broken leg',
  ];

  static String _pick(Random random, List<String> names) =>
      names[random.nextInt(names.length)];

  static void _applyInjury(
    Player player,
    Injury injury, {
    required int year,
    required int matchday,
  }) {
    player.isInjured = true;
    player.injuryType = injury.type;
    player.injuryReturnDate =
        dateOfMatchday(year, matchday + injury.weeks);
    // The treatment room is a lonely place.
    player.morale = (player.morale - 8).clamp(0, 100);
  }
}
