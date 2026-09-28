import 'player.dart';

class Team {
  final String id;
  final String name;
  final String shortName;
  final String leagueId;
  final String country;
  final String stadiumName;
  final int stadiumCapacity;
  int budget;
  double transferBudget;
  String color;
  String badgeUrl;
  int reputation; // 0-100
  int fanTrust; // 0-100

  // Squad
  List<Player> squad;
  List<Player> youthAcademy;

  // Season stats
  int leaguePosition;
  int points;
  int matchesPlayed;
  int wins;
  int draws;
  int losses;
  int goalsFor;
  int goalsAgainst;

  // Finance
  double totalWages = 0;
  double revenue = 0;

  // Manager
  double sackablePercent;
  double fanLoyalty;

  Team({
    required this.id,
    required this.name,
    required this.shortName,
    required this.leagueId,
    required this.country,
    required this.stadiumName,
    required this.stadiumCapacity,
    required this.budget,
    required this.color,
    required this.badgeUrl,
    List<Player>? squad,
    List<Player>? youthAcademy,
    this.reputation = 70,
    this.fanTrust = 75,
    this.leaguePosition = 10,
    this.points = 0,
    this.matchesPlayed = 0,
    this.wins = 0,
    this.draws = 0,
    this.losses = 0,
    this.goalsFor = 0,
    this.goalsAgainst = 0,
    double? transferBudget,
    this.totalWages = 0,
    this.revenue = 0,
    double? sackablePercent,
    double? fanLoyalty,
  })  : squad = squad ?? [],
        youthAcademy = youthAcademy ?? [],
        transferBudget = transferBudget ?? budget * 0.3,
        sackablePercent = sackablePercent ?? 5.0,
        fanLoyalty = fanLoyalty ?? 75.0;

  int get squadSize => squad.length;

  bool get hasSquadSpace => squadSize < 25;

  List<Player> get starters => squad.where((p) => p.fitness > 45).toList();

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'shortName': shortName,
    'leagueId': leagueId, 'country': country,
    'stadiumName': stadiumName, 'stadiumCapacity': stadiumCapacity,
    'budget': budget, 'transferBudget': transferBudget,
    'color': color, 'badgeUrl': badgeUrl,
    'reputation': reputation, 'fanTrust': fanTrust,
    'squad': squad.map((p) => p.toJson()).toList(),
    'youthAcademy': youthAcademy.map((p) => p.toJson()).toList(),
    'leaguePosition': leaguePosition, 'points': points,
    'matchesPlayed': matchesPlayed, 'wins': wins,
    'draws': draws, 'losses': losses,
    'goalsFor': goalsFor, 'goalsAgainst': goalsAgainst,
    'totalWages': totalWages, 'revenue': revenue,
    'sackablePercent': sackablePercent, 'fanLoyalty': fanLoyalty,
  };

  factory Team.fromJson(Map<String, dynamic> json) => Team(
    id: json['id'], name: json['name'], shortName: json['shortName'],
    leagueId: json['leagueId'], country: json['country'],
    stadiumName: json['stadiumName'], stadiumCapacity: json['stadiumCapacity'],
    budget: json['budget'], transferBudget: json['transferBudget'],
    color: json['color'], badgeUrl: json['badgeUrl'],
    reputation: json['reputation'], fanTrust: json['fanTrust'],
    squad: (json['squad'] as List).map((d) => Player.fromJson(d)).toList(),
    youthAcademy: (json['youthAcademy'] as List)
        .map((d) => Player.fromJson(d))
        .toList(),
    leaguePosition: json['leaguePosition'], points: json['points'],
    matchesPlayed: json['matchesPlayed'], wins: json['wins'],
    draws: json['draws'], losses: json['losses'],
    goalsFor: json['goalsFor'], goalsAgainst: json['goalsAgainst'],
    totalWages: json['totalWages'], revenue: json['revenue'],
    sackablePercent: json['sackablePercent'],
    fanLoyalty: json['fanLoyalty'],
  );
}