import '../models/cup.dart';

/// One knockout competition a country runs.
///
/// The bracket itself is built from the country's clubs by [CupService]; the
/// template only says what the competition is called, what kind of cup it is
/// and — for a secondary cup — how small its field is.
class CupTemplate {
  const CupTemplate({
    required this.id,
    required this.name,
    required this.kind,
    this.fieldSize,
    this.roundNames,
  });

  /// Stable id, also written to `Fixture.competition` ('fa_cup'…).
  final String id;

  /// The real competition name ('FA Cup', 'DFB-Pokal', 'Copa del Rey'…).
  final String name;

  final CupKind kind;

  /// Secondary cups take only the best [fieldSize] clubs by reputation
  /// (a Taça da Liga final phase, a Scottish League Cup last eight). Null
  /// means every club in the country enters.
  final int? fieldSize;

  /// Optional stage-name override; when null the engine names each round by
  /// the number of clubs in it ('Round of 64', 'Quarter-finals', 'Final').
  final List<String>? roundNames;

  bool get isSuperCup => kind == CupKind.superCup;
}

/// The competitions and divisions of one football country.
class CountryCompetitions {
  const CountryCompetitions({
    required this.country,
    required this.topLeague,
    required this.leagues,
    required this.cups,
  });

  final String country;

  /// The division whose champion lifts the league title — used to seed the
  /// super cup when no previous season exists.
  final String topLeague;

  /// Every division in the country that feeds the cup pool.
  final List<String> leagues;

  final List<CupTemplate> cups;
}

/// The real knockout competitions of the leagues in the shipped data.
///
/// Cup pools are country-wide: an FA Cup draw includes every Premier League,
/// Championship, League One and League Two club, not just the user's division.
/// Where the real competition has a second cup, it is modelled too — the EFL
/// Cup, the Taça da Liga, the Scottish League Cup — and where a super cup
/// exists, it opens the season as a one-match curtain-raiser.
class CompetitionCatalog {
  CompetitionCatalog._();

  /// The catalog for [leagueId], or null for leagues without a domestic cup
  /// in the data (continental pseudo-leagues and divisions too small to run
  /// a bracket).
  static CountryCompetitions? forLeague(String leagueId) {
    for (final catalog in all) {
      if (catalog.leagues.contains(leagueId)) return catalog;
    }
    return null;
  }

  /// The country a league belongs to, or null when it is not in the catalog.
  static String? countryOf(String leagueId) => forLeague(leagueId)?.country;

  /// Every division of the country [leagueId] belongs to.
  static List<String> leaguesOf(String leagueId) =>
      forLeague(leagueId)?.leagues ?? const <String>[];

  static const List<CountryCompetitions> all = [
    CountryCompetitions(
      country: 'England',
      topLeague: 'premier_league',
      leagues: [
        'premier_league',
        'efl_championship',
        'efl_league_one',
        'efl_league_two',
      ],
      cups: [
        CupTemplate(id: 'fa_cup', name: 'FA Cup', kind: CupKind.national),
        CupTemplate(id: 'efl_cup', name: 'EFL Cup', kind: CupKind.leagueCup),
        CupTemplate(
          id: 'community_shield',
          name: 'FA Community Shield',
          kind: CupKind.superCup,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'Germany',
      topLeague: 'bundesliga',
      leagues: ['bundesliga', 'bundesliga_2', '3_liga'],
      cups: [
        CupTemplate(id: 'dfb_pokal', name: 'DFB-Pokal', kind: CupKind.national),
        CupTemplate(
          id: 'dfl_supercup',
          name: 'DFL-Supercup',
          kind: CupKind.superCup,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'Spain',
      topLeague: 'laliga_ea_sports',
      leagues: ['laliga_ea_sports', 'laliga_hypermotion'],
      cups: [
        CupTemplate(
          id: 'copa_del_rey',
          name: 'Copa del Rey',
          kind: CupKind.national,
        ),
        CupTemplate(
          id: 'supercopa_de_espana',
          name: 'Supercopa de España',
          kind: CupKind.superCup,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'Italy',
      topLeague: 'serie_a_enilive',
      leagues: ['serie_a_enilive', 'serie_bkt'],
      cups: [
        CupTemplate(
          id: 'coppa_italia',
          name: 'Coppa Italia',
          kind: CupKind.national,
        ),
        CupTemplate(
          id: 'supercoppa_italiana',
          name: 'Supercoppa Italiana',
          kind: CupKind.superCup,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'France',
      topLeague: 'ligue_1_mcdonald_s',
      leagues: ['ligue_1_mcdonald_s', 'ligue_2_bkt'],
      cups: [
        CupTemplate(
          id: 'coupe_de_france',
          name: 'Coupe de France',
          kind: CupKind.national,
        ),
        CupTemplate(
          id: 'trophee_des_champions',
          name: 'Trophée des Champions',
          kind: CupKind.superCup,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'Portugal',
      topLeague: 'liga_portugal',
      leagues: ['liga_portugal'],
      cups: [
        CupTemplate(
          id: 'taca_de_portugal',
          name: 'Taça de Portugal',
          kind: CupKind.national,
        ),
        CupTemplate(
          id: 'taca_da_liga',
          name: 'Taça da Liga',
          kind: CupKind.leagueCup,
          fieldSize: 8,
        ),
        CupTemplate(
          id: 'supertaca',
          name: 'Supertaça Cândido de Oliveira',
          kind: CupKind.superCup,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'Scotland',
      topLeague: 'scottish_prem',
      leagues: ['scottish_prem'],
      cups: [
        CupTemplate(
          id: 'scottish_cup',
          name: 'Scottish Cup',
          kind: CupKind.national,
        ),
        CupTemplate(
          id: 'scottish_league_cup',
          name: 'Scottish League Cup',
          kind: CupKind.leagueCup,
          fieldSize: 8,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'Netherlands',
      topLeague: 'eredivisie',
      leagues: ['eredivisie'],
      cups: [
        CupTemplate(id: 'knvb_cup', name: 'KNVB Cup', kind: CupKind.national),
        CupTemplate(
          id: 'johan_cruyff_shield',
          name: 'Johan Cruyff Shield',
          kind: CupKind.superCup,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'Belgium',
      topLeague: '1a_pro_league',
      leagues: ['1a_pro_league'],
      cups: [
        CupTemplate(
          id: 'belgian_cup',
          name: 'Belgian Cup',
          kind: CupKind.national,
        ),
        CupTemplate(
          id: 'belgian_super_cup',
          name: 'Belgian Super Cup',
          kind: CupKind.superCup,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'Turkey',
      topLeague: 'trendyol_s_per_lig',
      leagues: ['trendyol_s_per_lig'],
      cups: [
        CupTemplate(
          id: 'turkish_cup',
          name: 'Turkish Cup',
          kind: CupKind.national,
        ),
        CupTemplate(
          id: 'turkish_super_cup',
          name: 'Turkish Super Cup',
          kind: CupKind.superCup,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'Poland',
      topLeague: 'pko_bp_ekstraklasa',
      leagues: ['pko_bp_ekstraklasa'],
      cups: [
        CupTemplate(
          id: 'polish_cup',
          name: 'Polish Cup',
          kind: CupKind.national,
        ),
        CupTemplate(
          id: 'polish_super_cup',
          name: 'Polish Super Cup',
          kind: CupKind.superCup,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'Switzerland',
      topLeague: 'brack_super_league',
      leagues: ['brack_super_league'],
      cups: [
        CupTemplate(id: 'swiss_cup', name: 'Swiss Cup', kind: CupKind.national),
      ],
    ),
    CountryCompetitions(
      country: 'Austria',
      topLeague: '_bundesliga',
      leagues: ['_bundesliga'],
      cups: [
        CupTemplate(
          id: 'austrian_cup',
          name: 'Austrian Cup',
          kind: CupKind.national,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'Denmark',
      topLeague: '3f_superliga',
      leagues: ['3f_superliga'],
      cups: [
        CupTemplate(
          id: 'danish_cup',
          name: 'Danish Cup',
          kind: CupKind.national,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'Norway',
      topLeague: 'eliteserien',
      leagues: ['eliteserien'],
      cups: [
        CupTemplate(
          id: 'norwegian_cup',
          name: 'Norwegian Cup',
          kind: CupKind.national,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'Sweden',
      topLeague: 'allsvenskan',
      leagues: ['allsvenskan'],
      cups: [
        CupTemplate(
          id: 'svenska_cupen',
          name: 'Svenska Cupen',
          kind: CupKind.national,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'Greece',
      topLeague: 'hellas_liga',
      leagues: ['hellas_liga'],
      cups: [
        CupTemplate(id: 'greek_cup', name: 'Greek Cup', kind: CupKind.national),
      ],
    ),
    CountryCompetitions(
      country: 'Argentina',
      topLeague: 'lpf',
      leagues: ['lpf'],
      cups: [
        CupTemplate(
          id: 'copa_argentina',
          name: 'Copa Argentina',
          kind: CupKind.national,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'United States',
      topLeague: 'mls',
      leagues: ['mls'],
      cups: [
        CupTemplate(
          id: 'us_open_cup',
          name: 'US Open Cup',
          kind: CupKind.national,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'China',
      topLeague: 'csl',
      leagues: ['csl'],
      cups: [
        CupTemplate(
          id: 'chinese_fa_cup',
          name: 'Chinese FA Cup',
          kind: CupKind.national,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'South Korea',
      topLeague: 'k_league_1',
      leagues: ['k_league_1'],
      cups: [
        CupTemplate(
          id: 'korean_fa_cup',
          name: 'Korean FA Cup',
          kind: CupKind.national,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'Saudi Arabia',
      topLeague: 'roshn_saudi_league',
      leagues: ['roshn_saudi_league'],
      cups: [
        CupTemplate(id: 'king_cup', name: 'King Cup', kind: CupKind.national),
      ],
    ),
    CountryCompetitions(
      country: 'Australia',
      topLeague: 'a_league',
      leagues: ['a_league'],
      cups: [
        CupTemplate(
          id: 'australia_cup',
          name: 'Australia Cup',
          kind: CupKind.national,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'India',
      topLeague: 'isl',
      leagues: ['isl'],
      cups: [
        CupTemplate(
          id: 'indian_super_cup',
          name: 'Indian Super Cup',
          kind: CupKind.national,
        ),
      ],
    ),
    CountryCompetitions(
      country: 'Ireland',
      topLeague: 'sse_airtricity_pd',
      leagues: ['sse_airtricity_pd'],
      cups: [
        CupTemplate(id: 'fai_cup', name: 'FAI Cup', kind: CupKind.national),
      ],
    ),
    CountryCompetitions(
      country: 'Romania',
      topLeague: 'superliga',
      leagues: ['superliga'],
      cups: [
        CupTemplate(
          id: 'cupa_romaniei',
          name: 'Cupa României',
          kind: CupKind.national,
        ),
      ],
    ),
  ];
}
