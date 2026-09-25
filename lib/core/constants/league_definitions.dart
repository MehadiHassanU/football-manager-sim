// League and team definitions (parody names)

class LeagueDefinition {
  final String id;
  final String name;
  final String country;
  final String flagEmoji;
  final List<String> teamIds;

  const LeagueDefinition({
    required this.id,
    required this.name,
    required this.country,
    required this.flagEmoji,
    required this.teamIds,
  });
}

class TeamDefinition {
  final String id;
  final String name;
  final String shortName;
  final String leagueId;
  final String country;
  final String stadiumName;
  final int stadiumCapacity;
  final int baseBudget;
  final String color;
  final String badgeUrl;

  const TeamDefinition({
    required this.id,
    required this.name,
    required this.shortName,
    required this.leagueId,
    required this.country,
    required this.stadiumName,
    required this.stadiumCapacity,
    required this.baseBudget,
    required this.color,
    required this.badgeUrl,
  });
}

// La Liga teams (MVP league) — parody names
const laLigaTeams = [
  TeamDefinition(
    id: 'real_madrid',
    name: 'Real Madrid',
    shortName: 'RMA',
    leagueId: 'laliga',
    country: 'Spain',
    stadiumName: 'Santiago Bernabéu',
    stadiumCapacity: 83186,
    baseBudget: 500000000,
    color: '#FFFFFF',
    badgeUrl: 'assets/images/real_madrid.png',
  ),
  TeamDefinition(
    id: 'fc_barcelona',
    name: 'FC Barcelona',
    shortName: 'BAR',
    leagueId: 'laliga',
    country: 'Spain',
    stadiumName: 'Spotify Camp Nou',
    stadiumCapacity: 99354,
    baseBudget: 450000000,
    color: '#004D98',
    badgeUrl: 'assets/images/barcelona.png',
  ),
  TeamDefinition(
    id: 'atletico_madrid',
    name: 'Atlético de Madrid',
    shortName: 'ATM',
    leagueId: 'laliga',
    country: 'Spain',
    stadiumName: 'Cívitas Metropolitano',
    stadiumCapacity: 70460,
    baseBudget: 300000000,
    color: '#272E61',
    badgeUrl: 'assets/images/atletico.png',
  ),
  TeamDefinition(
    id: 'sevilla_fc',
    name: 'Sevilla FC',
    shortName: 'SEV',
    leagueId: 'laliga',
    country: 'Spain',
    stadiumName: 'Ramón Sánchez-Pizjuán',
    stadiumCapacity: 43883,
    baseBudget: 150000000,
    color: '#FFFFFF',
    badgeUrl: 'assets/images/sevilla.png',
  ),
  TeamDefinition(
    id: 'real_sociedad',
    name: 'Real Sociedad',
    shortName: 'RSO',
    leagueId: 'laliga',
    country: 'Spain',
    stadiumName: 'Reale Arena',
    stadiumCapacity: 39500,
    baseBudget: 120000000,
    color: '#004D98',
    badgeUrl: 'assets/images/realsociedad.png',
  ),
  TeamDefinition(
    id: 'villarreal',
    name: 'Villarreal CF',
    shortName: 'VIL',
    leagueId: 'laliga',
    country: 'Spain',
    stadiumName: 'Estadio de la Cerámica',
    stadiumCapacity: 23008,
    baseBudget: 100000000,
    color: '#FFC72C',
    badgeUrl: 'assets/images/villarreal.png',
  ),
  TeamDefinition(
    id: 'real_betis',
    name: 'Real Betis',
    shortName: 'BET',
    leagueId: 'laliga',
    country: 'Spain',
    stadiumName: 'Benito Villamarín',
    stadiumCapacity: 60720,
    baseBudget: 130000000,
    color: '#0063B1',
    badgeUrl: 'assets/images/betis.png',
  ),
  TeamDefinition(
    id: 'athletic_bilbao',
    name: 'Athletic Club',
    shortName: 'ATH',
    leagueId: 'laliga',
    country: 'Spain',
    stadiumName: 'San Mamés',
    stadiumCapacity: 53289,
    baseBudget: 180000000,
    color: '#E30613',
    badgeUrl: 'assets/images/athletic.png',
  ),
  TeamDefinition(
    id: 'valencia_cf',
    name: 'Valencia CF',
    shortName: 'VAL',
    leagueId: 'laliga',
    country: 'Spain',
    stadiumName: 'Mestalla',
    stadiumCapacity: 49430,
    baseBudget: 140000000,
    color: '#FF6600',
    badgeUrl: 'assets/images/valencia.png',
  ),
];

final laLigaLeague = LeagueDefinition(
  id: 'laliga',
  name: 'La Liga EA Sports',
  country: 'Spain',
  flagEmoji: '🇪🇸',
  teamIds: laLigaTeams.map((t) => t.id).toList(),
);

const allAvailableTeams = [
  ...laLigaTeams,
  TeamDefinition(
    id: 'epl_crystal_palace',
    name: 'Crystal Palace',
    shortName: 'CRY',
    leagueId: 'premier_league',
    country: 'England',
    stadiumName: 'Selhurst Park',
    stadiumCapacity: 25486,
    baseBudget: 100000000,
    color: '#1B458F',
    badgeUrl: 'assets/images/crystal_palace.png',
  ),
];