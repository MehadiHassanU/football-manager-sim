/// One continental competition: a league phase followed by a knockout bracket.
class ContinentalTemplate {
  const ContinentalTemplate({
    required this.id,
    required this.name,
    required this.region,
    required this.clubCount,
    required this.leagueGames,
  });

  /// Stable id, also written to `Fixture.competition` ('ucl'…).
  final String id;

  /// The real competition name.
  final String name;

  final String region;

  /// Clubs in the league phase.
  final int clubCount;

  /// League-phase games each club plays.
  final int leagueGames;
}

/// The continental competitions of the leagues in the shipped data.
///
/// Qualification is reputation-based for the rest of the field and by league
/// finish for the manager's own club: the game only simulates one domestic
/// league, so the foreign entrants are the strongest clubs of the region.
/// Where the real competition name differs by continent the real name is used,
/// but the shape is shared — a league phase, then two-legged knockouts and a
/// single-leg final — so one engine covers the Champions League and the Copa
/// Libertadores alike.
class ContinentalCatalog {
  ContinentalCatalog._();

  static const String europe = 'europe';
  static const String southAmerica = 'south_america';
  static const String northAmerica = 'north_america';
  static const String asia = 'asia';

  /// The region a domestic league feeds, or null when it feeds none.
  static String? regionOf(String leagueId) => _regionOfLeague[leagueId];

  /// The competitions of [region], most prestigious first.
  static List<ContinentalTemplate> competitionsOf(String region) =>
      _competitions[region] ?? const <ContinentalTemplate>[];

  /// Whether [leagueId] is a league any continental entry could come from.
  static bool hasContinental(String leagueId) =>
      _regionOfLeague.containsKey(leagueId);

  /// Whether a career in [leagueId] can qualify for a continental competition.
  ///
  /// The shipped data files some South American clubs only under the
  /// Libertadores/Sudamericana labels rather than a domestic league. Those
  /// clubs belong in the field, but there is no domestic season behind those
  /// labels, so a career cannot be based on one.
  static bool qualifiesFrom(String leagueId) =>
      _regionOfLeague.containsKey(leagueId) &&
      !_continentalOnlyLeagues.contains(leagueId);

  /// The human name of a region, used in copy.
  static String regionName(String region) => switch (region) {
        europe => 'Europe',
        southAmerica => 'South America',
        northAmerica => 'North America',
        asia => 'Asia',
        _ => region,
      };

  static const Map<String, List<ContinentalTemplate>> _competitions = {
    europe: [
      ContinentalTemplate(
        id: 'ucl',
        name: 'UEFA Champions League',
        region: europe,
        clubCount: 36,
        leagueGames: 8,
      ),
      ContinentalTemplate(
        id: 'uel',
        name: 'UEFA Europa League',
        region: europe,
        clubCount: 36,
        leagueGames: 8,
      ),
      ContinentalTemplate(
        id: 'uecl',
        name: 'UEFA Conference League',
        region: europe,
        clubCount: 36,
        leagueGames: 6,
      ),
    ],
    southAmerica: [
      ContinentalTemplate(
        id: 'libertadores',
        name: 'Copa Libertadores',
        region: southAmerica,
        clubCount: 32,
        leagueGames: 6,
      ),
      ContinentalTemplate(
        id: 'sudamericana',
        name: 'Copa Sudamericana',
        region: southAmerica,
        clubCount: 32,
        leagueGames: 6,
      ),
    ],
    northAmerica: [
      ContinentalTemplate(
        id: 'concacaf',
        name: 'CONCACAF Champions Cup',
        region: northAmerica,
        clubCount: 32,
        leagueGames: 6,
      ),
    ],
    asia: [
      ContinentalTemplate(
        id: 'afc_elite',
        name: 'AFC Champions League Elite',
        region: asia,
        clubCount: 32,
        leagueGames: 6,
      ),
    ],
  };

  /// The labels that only exist to carry continental entrants, never a season.
  static const Set<String> _continentalOnlyLeagues = {
    'libertadores',
    'sudamericana',
  };

  /// Every league that feeds a continental competition, keyed to its region.
  /// The keys are the real CSV slugs, matching [CompetitionCatalog].
  static const Map<String, String> _regionOfLeague = {
    // Europe
    'premier_league': europe,
    'efl_championship': europe,
    'efl_league_one': europe,
    'efl_league_two': europe,
    'bundesliga': europe,
    'bundesliga_2': europe,
    '3_liga': europe,
    'laliga_ea_sports': europe,
    'laliga_hypermotion': europe,
    'serie_a_enilive': europe,
    'serie_bkt': europe,
    'ligue_1_mcdonald_s': europe,
    'ligue_2_bkt': europe,
    'liga_portugal': europe,
    'eredivisie': europe,
    '1a_pro_league': europe,
    'trendyol_s_per_lig': europe,
    'pko_bp_ekstraklasa': europe,
    'scottish_prem': europe,
    'brack_super_league': europe,
    '_bundesliga': europe,
    '3f_superliga': europe,
    'eliteserien': europe,
    'allsvenskan': europe,
    'hellas_liga': europe,
    '_esk_liga': europe,
    'liga_hrvatska': europe,
    'ukrayina_liha': europe,
    'magyar_liga': europe,
    'liga_cyprus': europe,
    'superliga': europe,
    'sse_airtricity_pd': europe,
    'finnliiga': europe,
    'liga_azerbaijan': europe,
    // South America
    'lpf': southAmerica,
    'liga_chile': southAmerica,
    // The data lists many South American clubs only for the two continental
    // competitions, so these labels feed the field even though no career can
    // be based on them.
    'libertadores': southAmerica,
    'sudamericana': southAmerica,
    // North America
    'mls': northAmerica,
    // Asia
    'csl': asia,
    'k_league_1': asia,
    'roshn_saudi_league': asia,
    'united_emirates_league': asia,
    'isl': asia,
    'a_league': asia,
  };
}
