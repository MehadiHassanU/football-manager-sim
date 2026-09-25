import 'dart:math';

class Player {
  // Identity
  final String name;
  final int id;
  final String nationality;
  int age;

  // Core Stats (from CSV)
  int ovr;
  int pac;
  int sho;
  int pas;
  int dri;
  int def;
  int phy;

  // Sub-Stats
  int acceleration;
  int sprintSpeed;
  int positioning;
  int finishing;
  int shotPower;
  int longShots;
  int volleys;
  int penalties;
  int vision;
  int crossing;
  int freeKickAccuracy;
  int shortPassing;
  int longPassing;
  int curve;
  int agility;
  int balance;
  int reactions;
  int ballControl;
  int composure;
  int interceptions;
  int headingAccuracy;
  int defAwareness;
  int standingTackle;
  int slidingTackle;
  int jumping;
  int staminaStat;
  int strength;
  int aggression;

  // GK Stats
  int? gkDiving;
  int? gkHandling;
  int? gkKicking;
  int? gkPositioning;
  int? gkReflexes;

  // Position Info
  String primaryPosition;
  List<String> alternativePositions;

  // Meta
  String preferredFoot;
  int weakFootQuality;
  int skillMoves;
  final String height;
  final String weight;
  List<String> playTraits;
  String currentTeam;
  String currentLeague;

  // Runtime
  int fitness;
  int form;
  int morale;
  int matchRating;
  int minutesPlayed;
  int gamesPlayed;
  bool isInjured;
  String? injuryType;
  DateTime? injuryReturnDate;
  DateTime? contractExpiry;
  double weeklyWage;
  int transferValue;
  bool requestedTransfer;
  Map<String, dynamic> hiddenAttributes;

  Player({
    required this.name,
    required this.id,
    required this.nationality,
    required this.age,
    required this.ovr,
    required this.pac,
    required this.sho,
    required this.pas,
    required this.dri,
    required this.def,
    required this.phy,
    required this.acceleration,
    required this.sprintSpeed,
    required this.positioning,
    required this.finishing,
    required this.shotPower,
    required this.longShots,
    required this.volleys,
    required this.penalties,
    required this.vision,
    required this.crossing,
    required this.freeKickAccuracy,
    required this.shortPassing,
    required this.longPassing,
    required this.curve,
    required this.agility,
    required this.balance,
    required this.reactions,
    required this.ballControl,
    required this.composure,
    required this.interceptions,
    required this.headingAccuracy,
    required this.defAwareness,
    required this.standingTackle,
    required this.slidingTackle,
    required this.jumping,
    required this.staminaStat,
    required this.strength,
    required this.aggression,
    this.gkDiving,
    this.gkHandling,
    this.gkKicking,
    this.gkPositioning,
    this.gkReflexes,
    required this.primaryPosition,
    required this.alternativePositions,
    required this.preferredFoot,
    required this.weakFootQuality,
    required this.skillMoves,
    required this.height,
    required this.weight,
    required this.playTraits,
    required this.currentTeam,
    required this.currentLeague,
    this.fitness = 100,
    this.form = 5,
    this.morale = 75,
    this.matchRating = 0,
    this.minutesPlayed = 0,
    this.gamesPlayed = 0,
    this.isInjured = false,
    this.weeklyWage = 0,
    this.transferValue = 0,
    this.requestedTransfer = false,
    this.injuryType,
    this.injuryReturnDate,
    this.contractExpiry,
    Map<String, dynamic>? hiddenAttributes,
  }) : hiddenAttributes = hiddenAttributes ?? {
          'potential': ovr + Random().nextInt(5),
          'personality': ['Stable', 'Driven', 'Charismatic', 'Temperamental']
              [Random().nextInt(4)],
          'leadership': Random().nextInt(100),
          'adaptability': Random().nextInt(100),
        };

  Map<String, dynamic> toJson() => {
    'name': name, 'id': id, 'nationality': nationality,
    'age': age, 'ovr': ovr, 'pac': pac, 'sho': sho,
    'pas': pas, 'dri': dri, 'def': def, 'phy': phy,
    'acceleration': acceleration, 'sprintSpeed': sprintSpeed,
    'positioning': positioning, 'finishing': finishing,
    'shotPower': shotPower, 'longShots': longShots,
    'volleys': volleys, 'penalties': penalties,
    'vision': vision, 'crossing': crossing,
    'freeKickAccuracy': freeKickAccuracy, 'shortPassing': shortPassing,
    'longPassing': longPassing, 'curve': curve,
    'agility': agility, 'balance': balance,
    'reactions': reactions, 'ballControl': ballControl,
    'composure': composure, 'interceptions': interceptions,
    'headingAccuracy': headingAccuracy, 'defAwareness': defAwareness,
    'standingTackle': standingTackle, 'slidingTackle': slidingTackle,
    'jumping': jumping, 'staminaStat': staminaStat,
    'strength': strength, 'aggression': aggression,
    if (gkDiving != null) 'gkDiving': gkDiving!,
    if (gkHandling != null) 'gkHandling': gkHandling!,
    if (gkKicking != null) 'gkKicking': gkKicking!,
    if (gkPositioning != null) 'gkPositioning': gkPositioning!,
    if (gkReflexes != null) 'gkReflexes': gkReflexes!,
    'primaryPosition': primaryPosition,
    'alternativePositions': alternativePositions,
    'preferredFoot': preferredFoot,
    'weakFootQuality': weakFootQuality,
    'skillMoves': skillMoves,
    'height': height, 'weight': weight,
    'playTraits': playTraits,
    'currentTeam': currentTeam,
    'currentLeague': currentLeague,
    'fitness': fitness, 'form': form, 'morale': morale,
    'matchRating': matchRating, 'minutesPlayed': minutesPlayed,
    'gamesPlayed': gamesPlayed, 'isInjured': isInjured,
    'weeklyWage': weeklyWage, 'transferValue': transferValue,
    'requestedTransfer': requestedTransfer,
    'injuryType': injuryType,
    'injuryReturnDate': injuryReturnDate?.millisecondsSinceEpoch,
    'contractExpiry': contractExpiry?.millisecondsSinceEpoch,
    'hiddenAttributes': hiddenAttributes,
  };

  factory Player.fromJson(Map<String, dynamic> json) => Player(
    name: json['name'], id: json['id'],
    nationality: json['nationality'], age: json['age'],
    ovr: json['ovr'], pac: json['pac'], sho: json['sho'],
    pas: json['pas'], dri: json['dri'], def: json['def'],
    phy: json['phy'], acceleration: json['acceleration'],
    sprintSpeed: json['sprintSpeed'], positioning: json['positioning'],
    finishing: json['finishing'], shotPower: json['shotPower'],
    longShots: json['longShots'], volleys: json['volleys'],
    penalties: json['penalties'], vision: json['vision'],
    crossing: json['crossing'], freeKickAccuracy: json['freeKickAccuracy'],
    shortPassing: json['shortPassing'], longPassing: json['longPassing'],
    curve: json['curve'], agility: json['agility'],
    balance: json['balance'], reactions: json['reactions'],
    ballControl: json['ballControl'], composure: json['composure'],
    interceptions: json['interceptions'],
    headingAccuracy: json['headingAccuracy'],
    defAwareness: json['defAwareness'],
    standingTackle: json['standingTackle'],
    slidingTackle: json['slidingTackle'],
    jumping: json['jumping'], staminaStat: json['staminaStat'],
    strength: json['strength'], aggression: json['aggression'],
    gkDiving: json['gkDiving'], gkHandling: json['gkHandling'],
    gkKicking: json['gkKicking'], gkPositioning: json['gkPositioning'],
    gkReflexes: json['gkReflexes'],
    primaryPosition: json['primaryPosition'],
    alternativePositions: List<String>.from(json['alternativePositions']),
    preferredFoot: json['preferredFoot'],
    weakFootQuality: json['weakFootQuality'],
    skillMoves: json['skillMoves'],
    height: json['height'], weight: json['weight'],
    playTraits: List<String>.from(json['playTraits']),
    currentTeam: json['currentTeam'],
    currentLeague: json['currentLeague'],
    fitness: json['fitness'], form: json['form'],
    morale: json['morale'], matchRating: json['matchRating'],
    minutesPlayed: json['minutesPlayed'],
    gamesPlayed: json['gamesPlayed'],
    isInjured: json['isInjured'],
    weeklyWage: json['weeklyWage'] ?? 0,
    transferValue: json['transferValue'],
    requestedTransfer: json['requestedTransfer'] ?? false,
    injuryType: json['injuryType'],
    injuryReturnDate: json['injuryReturnDate'] != null ? DateTime.fromMillisecondsSinceEpoch(json['injuryReturnDate']) : null,
    contractExpiry: json['contractExpiry'] != null ? DateTime.fromMillisecondsSinceEpoch(json['contractExpiry']) : null,
    hiddenAttributes: Map<String, dynamic>.from(json['hiddenAttributes']),
  );
}