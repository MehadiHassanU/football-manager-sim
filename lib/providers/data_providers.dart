import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/player.dart';
import '../core/models/team.dart';
import '../core/services/csv_loader_service.dart';

/// Asset path of the bundled player database.
const String kPlayerCsvAsset = 'lib/data/csv/EAFC26-Men.csv';

/// Minimum squad size for a club to be selectable in a new career.
const int kMinSquadPlayers = 16;

class PlayerDatabase {
  const PlayerDatabase({
    required this.players,
    required this.teams,
    required this.leagues,
    required this.playersByTeam,
  });

  final List<Player> players;
  final List<Team> teams;
  final List<LeagueInfo> leagues;
  final Map<String, List<Player>> playersByTeam;
}

/// A league derived from the player database.
class LeagueInfo {
  const LeagueInfo({
    required this.id,
    required this.name,
    required this.country,
    required this.teamCount,
  });

  final String id;
  final String name;
  final String country;
  final int teamCount;
}

/// Loads the bundled CSV and derives the league/team directory from it.
///
/// NOT autoDispose: the parse is expensive and every screen (startup, new
/// career, transfer market) reads it. Keeping it alive for the app's
/// lifetime means the CSV is parsed exactly once per run — this is what makes
/// both the startup and the New Career screen instant on repeat visits.
///
/// States: null = loading; a [PlayerDatabase] with empty players = failed;
/// non-empty = ready.
final playerDatabaseProvider =
    FutureProvider<PlayerDatabase>((ref) async {
  final loader = CsvLoaderService(
    assetSource: (path) async {
      try {
        return await rootBundle.loadString(path);
      } catch (_) {
        return null;
      }
    },
  );

  final ok = await loader.loadFromAsset(kPlayerCsvAsset);
  if (!ok || loader.players.isEmpty) {
    return const PlayerDatabase(
      players: [],
      teams: [],
      leagues: [],
      playersByTeam: {},
    );
  }

  final players = loader.players;
  final byTeam = <String, List<Player>>{};
  for (final p in players) {
    byTeam.putIfAbsent(p.currentTeam, () => []).add(p);
  }

  // Build selectable teams: clubs with enough players for a playable squad.
  final teams = <Team>[];
  final teamPlayerIds = <String, List<int>>{};
  byTeam.forEach((teamName, squad) {
    if (squad.length < kMinSquadPlayers) return;
    final league = squad.first.currentLeague;
    final id = _slugify(teamName);
    // Sort by OVR so the best 25 form the initial squad.
    squad.sort((a, b) => b.ovr.compareTo(a.ovr));
    final squadPlayers = squad.take(25).toList();
    teamPlayerIds[id] = [for (final p in squadPlayers) p.id];
    final avgOvr =
        squadPlayers.map((p) => p.ovr).reduce((a, b) => a + b) /
            squadPlayers.length;
    teams.add(Team(
      id: id,
      name: teamName,
      shortName: _shortName(teamName),
      leagueId: _slugify(league),
      country: _majorityNationality(
          squadPlayers.map((p) => p.nationality)),
      stadiumName: '$teamName Stadium',
      stadiumCapacity: 30000 + (avgOvr.round() * 400),
      budget: _budgetForTier(avgOvr.round()).round(),
      color: _colorForTeam(id),
      badgeUrl: '',
      squad: squadPlayers,
    ));
  });

  // Derive leagues from the teams that survived the filter.
  final leagueStats = <String, Set<String>>{};
  for (final t in teams) {
    leagueStats.putIfAbsent(t.leagueId, () => {}).add(t.id);
  }
  final leagues = [
    for (final entry in leagueStats.entries)
      LeagueInfo(
        id: entry.key,
        name: _prettify(entry.key),
        country: _countryFor(entry.key, teams),
        teamCount: entry.value.length,
      ),
  ]..sort((a, b) => b.teamCount.compareTo(a.teamCount));

  return PlayerDatabase(
    players: players,
    teams: teams,
    leagues: leagues,
    playersByTeam: {
      for (final t in teams)
        t.id: [for (final id in teamPlayerIds[t.id]!) players.firstWhere((p) => p.id == id)],
    },
  );
});

/// The player list as a plain provider for consumers that just read players.
final loadedPlayersProvider = Provider<List<Player>>((ref) {
  final db = ref.watch(playerDatabaseProvider).valueOrNull;
  return db?.players ?? const [];
});

String _slugify(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

/// Words that are acronyms in competition/league names and must stay
/// uppercase when rendering a slugified league name back to the user.
const Set<String> _leagueAcronyms = {
  'mls', 'efl', 'ucl', 'uel', 'uefa', 'fifa', 'caf', 'afc', 'conmebol',
  'concacaf', 'ofc', 'csl', 'usl', 'nwsl', 'psl', 'safl', 'j1', 'j2', 'j3',
  'k1', 'k2', 'kl', 'mlsnextpro', 'fl', 'dfb', 'rfef', 'figc',
};

String _prettify(String slug) => slug
    .split('_')
    .map((w) {
      if (w.isEmpty) return w;
      if (_leagueAcronyms.contains(w)) return w.toUpperCase();
      return '${w[0].toUpperCase()}${w.substring(1)}';
    })
    .join(' ');

/// Turns a slugified league id into a display name, keeping competition
/// acronyms uppercase ("efl_championship" -> "EFL Championship").
///
/// Shared by the database builder and every screen that renders a league id
/// directly from a [Team], so the name is formatted identically everywhere.
String prettifyLeagueId(String leagueId) => _prettify(leagueId);

String _shortName(String name) {
  final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.length == 1) return words.first.substring(0, words.first.length.clamp(1, 3));
  return words.map((w) => w[0]).take(3).join().toUpperCase();
}

/// Budget tiers by average squad OVR.
double _budgetForTier(int avgOvr) {
  if (avgOvr >= 82) return 200000000;
  if (avgOvr >= 78) return 100000000;
  if (avgOvr >= 74) return 45000000;
  if (avgOvr >= 70) return 20000000;
  return 8000000;
}

/// Deterministic pseudo-brand color from the team id.
String _colorForTeam(String id) {
  const palette = [
    '#E53935', '#1E88E5', '#43A047', '#FB8C00', '#8E24AA',
    '#00ACC1', '#F4511E', '#3949AB', '#7CB342', '#D81B60',
  ];
  var hash = 0;
  for (final code in id.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}

/// Home countries of competition-branded leagues where a player-nationality
/// majority can be misleading (global diaspora squads).
const Map<String, String> _leagueHomeCountries = {
  'mls': 'United States',
  'efl_championship': 'England',
  'efl_league_one': 'England',
  'efl_league_two': 'England',
  'premier_league': 'England',
  'laliga': 'Spain',
  'laliga_2': 'Spain',
  'segunda_division': 'Spain',
  'serie_a': 'Italy',
  'serie_b': 'Italy',
  'bundesliga': 'Germany',
  '2_bundesliga': 'Germany',
  'ligue_1': 'France',
  'ligue_2': 'France',
  'eredivisie': 'Netherlands',
  'primeira_liga': 'Portugal',
  'brasileirao': 'Brazil',
  'a_league': 'Australia',
  'roshn_saudi_league': 'Saudi Arabia',
  'j1_league': 'Japan',
  'k_league_1': 'South Korea',
  'chinese_super_league': 'China',
  'scottish_premiership': 'Scotland',
  'super_league': 'Switzerland',
  'super_lig': 'Turkey',
  'jupiler_pro_league': 'Belgium',
  'austrian_bundesliga': 'Austria',
  'allsvenskan': 'Sweden',
  'eliteserien': 'Norway',
  'superliga': 'Denmark',
};

/// The league's country: a curated home country for competition-branded
/// leagues, otherwise the majority nationality across all squad players of
/// the league's teams (fixes e.g. EFL Championship showing a random nation).
String _countryFor(String leagueId, List<Team> teams) {
  final curated = _leagueHomeCountries[leagueId];
  if (curated != null) return curated;

  final nationalities = <String>[];
  for (final t in teams) {
    if (t.leagueId != leagueId) continue;
    for (final p in t.squad) {
      nationalities.add(p.nationality);
    }
  }
  if (nationalities.isEmpty) return 'Unknown';
  return _majorityNationality(nationalities);
}

/// Most common nationality in [nationalities] (ties broken deterministically
/// by count, then name, so builds stay reproducible).
String _majorityNationality(Iterable<String> nationalities) {
  final tally = <String, int>{};
  for (final n in nationalities) {
    tally[n] = (tally[n] ?? 0) + 1;
  }
  if (tally.isEmpty) return 'Unknown';
  String best = tally.keys.first;
  for (final entry in tally.entries) {
    if (entry.value > tally[best]! ||
        (entry.value == tally[best]! &&
            entry.key.compareTo(best) < 0)) {
      best = entry.key;
    }
  }
  return best;
}
