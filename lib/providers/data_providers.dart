import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/player.dart';
import '../core/models/team.dart';
import '../core/services/financial_service.dart';
import '../core/services/transfer_market_service.dart';
import '../core/utils/csv_parser.dart' show parseCsvPlayers;

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

/// Parses the CSV rows on a worker isolate so the ~750 ms conversion
/// (16k players) never freezes the UI thread. Signature is isolate-safe:
/// `parseCsvPlayers` is a top-level function with no captured state.
///
/// Returns false when the isolate path fails — the provider treats that the
/// same way a parse error was treated before (empty failure database so the
/// startup screen can offer a retry).
Future<bool> _parsePlayers(String csvString, List<Player> out) async {
  try {
    final parsed = await compute(parseCsvPlayers, csvString);
    out.addAll(parsed);
    return parsed.isNotEmpty;
  } catch (_) {
    return false;
  }
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
  Future<String?> readAsset() async {
    try {
      return await rootBundle.loadString(kPlayerCsvAsset);
    } catch (_) {
      return null;
    }
  }

  final csvString = await readAsset();
  if (csvString == null || csvString.isEmpty) {
    return const PlayerDatabase(
      players: [],
      teams: [],
      leagues: [],
      playersByTeam: {},
    );
  }

  final players = <Player>[];
  final ok = await _parsePlayers(csvString, players);
  if (!ok || players.isEmpty) {
    return const PlayerDatabase(
      players: [],
      teams: [],
      leagues: [],
      playersByTeam: {},
    );
  }
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
    // Reputation used to default to 70 for every club, which made prestige
    // meaningless in the transfer market. Deriving it from squad strength
    // makes Real Madrid a genuinely bigger draw than Espanyol — and the
    // ground is sized the same way, so capacity stops being a near-constant.
    final reputation = _reputationFor(avgOvr.round());
    teams.add(Team(
      id: id,
      name: teamName,
      shortName: _shortName(teamName),
      leagueId: _slugify(league),
      country: _majorityNationality(
          squadPlayers.map((p) => p.nationality)),
      stadiumName: '$teamName Stadium',
      stadiumCapacity: FinancialService().realisticCapacity(reputation, id),
      budget: _budgetForTier(avgOvr.round()).round(),
      color: _colorForTeam(id),
      badgeUrl: '',
      reputation: reputation,
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

  // Contracts, wages and valuations are derived once at load, so the market
  // can price a player and know when his deal expires.
  TransferMarketService().backfillTransferData(teams, DateTime.now().year);

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

/// Every nationality present in the loaded dataset, sorted.
///
/// Derived here rather than recomputed inside the New Career screen: the CSV
/// holds over 16,000 players, and building the set inline meant walking and
/// sorting all of them on every search keystroke and every slider tick. This
/// runs once per database load. Built from the real data, so it can only ever
/// offer a country that actually has players in it.
final nationalitiesProvider = Provider<List<String>>((ref) {
  final players = ref.watch(loadedPlayersProvider);
  final seen = <String>{};
  for (final p in players) {
    final n = p.nationality.trim();
    if (n.isNotEmpty) seen.add(n);
  }
  if (seen.isEmpty) return const ['Unknown'];
  return seen.toList()..sort();
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
/// Club prestige on the same 0-100 scale the transfer market reads.
int _reputationFor(int avgOvr) => (40 + avgOvr * 0.55).round().clamp(40, 95);

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
/// Curated home countries for competition-branded leagues.
///
/// Keys are the real slugs the CSV produces (see [PlayerDatabase.leagues]),
/// not pretty labels: a miss here silently fell back to the squad's majority
/// nationality, which is why an English second tier could read as "Jamaica".
/// Continental pools are labelled by continent rather than a single country.
const Map<String, String> _leagueHomeCountries = {
  'premier_league': 'England',
  'efl_championship': 'England',
  'efl_league_one': 'England',
  'efl_league_two': 'England',
  'bundesliga': 'Germany',
  'bundesliga_2': 'Germany',
  '3_liga': 'Germany',
  'laliga_ea_sports': 'Spain',
  'laliga_hypermotion': 'Spain',
  'serie_a_enilive': 'Italy',
  'serie_bkt': 'Italy',
  'ligue_1_mcdonald_s': 'France',
  'ligue_2_bkt': 'France',
  'liga_portugal': 'Portugal',
  'eredivisie': 'Netherlands',
  '1a_pro_league': 'Belgium',
  'trendyol_s_per_lig': 'Turkey',
  'pko_bp_ekstraklasa': 'Poland',
  'scottish_prem': 'Scotland',
  'brack_super_league': 'Switzerland',
  '_bundesliga': 'Austria',
  '3f_superliga': 'Denmark',
  'eliteserien': 'Norway',
  'allsvenskan': 'Sweden',
  'hellas_liga': 'Greece',
  '_esk_liga': 'Czechia',
  'liga_hrvatska': 'Croatia',
  'ukrayina_liha': 'Ukraine',
  'magyar_liga': 'Hungary',
  'liga_cyprus': 'Cyprus',
  'superliga': 'Romania',
  'lpf': 'Argentina',
  'mls': 'United States',
  'csl': 'China',
  'k_league_1': 'South Korea',
  'roshn_saudi_league': 'Saudi Arabia',
  'a_league': 'Australia',
  'isl': 'India',
  'sse_airtricity_pd': 'Ireland',
  'liga_chile': 'Chile',
  'liga_azerbaijan': 'Azerbaijan',
  'united_emirates_league': 'United Arab Emirates',
  'finnliiga': 'Finland',
  'libertadores': 'South America',
  'sudamericana': 'South America',
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
