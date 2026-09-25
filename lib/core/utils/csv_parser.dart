import 'package:csv/csv.dart';
import '../models/player.dart';

class CSVParser {
  final String csvContent;

  CSVParser(this.csvContent);

  List<Player> parsePlayers() {
    final rows = CsvToListConverter().convert(csvContent);
    if (rows.isEmpty) return [];

    final header = rows[0].map((value) => value.toString()).toList();
    final players = <Player>[];

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.length < 2 || row[1] == null) continue;

      try {
        final player = _parseRow(header, row);
        if (player != null) players.add(player);
      } catch (e) {
        // Skip malformed rows
      }
    }

    return players;
  }

  Player? _parseRow(List<String> header, List<dynamic> row) {
    String? getValue(String key) {
      final idx = header.indexOf(key);
      if (idx >= 0 && idx < row.length) return row[idx]?.toString();
      return null;
    }

    final name = getValue('Name') ?? 'Unknown';
    final id = int.tryParse(getValue('ID') ?? '0') ?? 0;
    final age = int.tryParse(getValue('Age') ?? '25') ?? 25;
    final nationality = getValue('Nation') ?? 'Unknown';
    final team = getValue('Team') ?? '';
    final league = getValue('League') ?? '';
    final position = getValue('Position') ?? 'CM';

    // Alternative positions
    List<String> altPositions = [];
    var altRaw = getValue('Alternative positions');
    if (altRaw != null && altRaw.isNotEmpty) {
      altRaw = altRaw.replaceAll(RegExp(r"[\[\]']"), '');
      altPositions = altRaw.split(',').map((s) => s.trim()).toList();
    }

    // Play traits
    List<String> traits = [];
    var traitsRaw = getValue('play style');
    if (traitsRaw != null && traitsRaw.isNotEmpty) {
      traitsRaw = traitsRaw.replaceAll(RegExp(r"[\[\]']"), '');
      traits = traitsRaw.split(',').map((s) => s.trim()).toList();
    }

    // Parse stats
    int parseStat(String key) {
      final val = getValue(key);
      if (val == null) return 50;
      return int.tryParse(val) ?? 50;
    }

    final primary = position;
    final height = getValue('Height') ?? '180cm / 5\'11"';
    final weight = getValue('Weight') ?? '75kg / 165lb';
    final preferredFoot = getValue('Preferred foot') ?? 'Right';
    final weakFoot = int.tryParse(getValue('Weak foot') ?? '3') ?? 3;
    final skillMoves = int.tryParse(getValue('Skill moves') ?? '3') ?? 3;

    // Map CSV column names to model field names
    final pac = parseStat('PAC');
    final sho = parseStat('SHO');
    final pas = parseStat('PAS');
    final dri = parseStat('DRI');
    final def = parseStat('DEF');
    final phy = parseStat('PHY');
    final acceleration = parseStat('Acceleration');
    final sprintSpeed = parseStat('Sprint Speed');
    final positioning = parseStat('Positioning');
    final finishing = parseStat('Finishing');
    final shotPower = parseStat('Shot Power');
    final longShots = parseStat('Long Shots');
    final volleys = parseStat('Volleys');
    final penalties = parseStat('Penalties');
    final vision = parseStat('Vision');
    final crossing = parseStat('Crossing');
    final freeKickAccuracy = parseStat('Free Kick Accuracy');
    final shortPassing = parseStat('Short Passing');
    final longPassing = parseStat('Long Passing');
    final curve = parseStat('Curve');
    final agility = parseStat('Agility');
    final balance = parseStat('Balance');
    final reactions = parseStat('Reactions');
    final ballControl = parseStat('Ball Control');
    final composure = parseStat('Composure');
    final interceptions = parseStat('Interceptions');
    final headingAccuracy = parseStat('Heading Accuracy');
    final defAwareness = parseStat('Def Awareness');
    final standingTackle = parseStat('Standing Tackle');
    final slidingTackle = parseStat('Sliding Tackle');
    final jumping = parseStat('Jumping');
    final staminaStat = parseStat('Stamina');
    final strength = parseStat('Strength');
    final aggression = parseStat('Aggression');

    // GK stats
    int? gkDiving, gkHandling, gkKicking, gkPositioning, gkReflexes;
    final ovr = int.tryParse(getValue('OVR') ?? '75') ?? 75;

    if (primary == 'GK') {
      gkDiving = parseStat('GK Diving');
      gkHandling = parseStat('GK Handling');
      gkKicking = parseStat('GK Kicking');
      gkPositioning = parseStat('GK Positioning');
      gkReflexes = parseStat('GK Reflexes');
    }

    return Player(
      name: name,
      id: id,
      nationality: nationality,
      age: age,
      ovr: ovr,
      pac: pac, sho: sho, pas: pas, dri: dri, def: def, phy: phy,
      acceleration: acceleration, sprintSpeed: sprintSpeed,
      positioning: positioning, finishing: finishing,
      shotPower: shotPower, longShots: longShots, volleys: volleys,
      penalties: penalties, vision: vision, crossing: crossing,
      freeKickAccuracy: freeKickAccuracy, shortPassing: shortPassing,
      longPassing: longPassing, curve: curve, agility: agility,
      balance: balance, reactions: reactions, ballControl: ballControl,
      composure: composure, interceptions: interceptions,
      headingAccuracy: headingAccuracy, defAwareness: defAwareness,
      standingTackle: standingTackle, slidingTackle: slidingTackle,
      jumping: jumping, staminaStat: staminaStat, strength: strength,
      aggression: aggression,
      gkDiving: gkDiving, gkHandling: gkHandling,
      gkKicking: gkKicking, gkPositioning: gkPositioning,
      gkReflexes: gkReflexes,
      primaryPosition: primary,
      alternativePositions: altPositions,
      preferredFoot: preferredFoot,
      weakFootQuality: weakFoot,
      skillMoves: skillMoves,
      height: height, weight: weight,
      playTraits: traits,
      currentTeam: team,
      currentLeague: league,
    );
  }
}
