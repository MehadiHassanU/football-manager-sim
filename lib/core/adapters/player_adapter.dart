import 'package:hive/hive.dart';
import '../models/player.dart';

class PlayerAdapter implements TypeAdapter<Player> {
  @override
  final int typeId = 0;

  @override
  Player read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return Player(
      name: fields[0] as String, id: fields[1] as int,
      nationality: fields[2] as String, age: fields[3] as int,
      ovr: fields[4] as int, pac: fields[5] as int, sho: fields[6] as int,
      pas: fields[7] as int, dri: fields[8] as int, def: fields[9] as int,
      phy: fields[10] as int, acceleration: fields[11] as int,
      sprintSpeed: fields[12] as int, positioning: fields[13] as int,
      finishing: fields[14] as int, shotPower: fields[15] as int,
      longShots: fields[16] as int, volleys: fields[17] as int,
      penalties: fields[18] as int, vision: fields[19] as int,
      crossing: fields[20] as int, freeKickAccuracy: fields[21] as int,
      shortPassing: fields[22] as int, longPassing: fields[23] as int,
      curve: fields[24] as int, agility: fields[25] as int,
      balance: fields[26] as int, reactions: fields[27] as int,
      ballControl: fields[28] as int, composure: fields[29] as int,
      interceptions: fields[30] as int, headingAccuracy: fields[31] as int,
      defAwareness: fields[32] as int, standingTackle: fields[33] as int,
      slidingTackle: fields[34] as int, jumping: fields[35] as int,
      staminaStat: fields[36] as int, strength: fields[37] as int,
      aggression: fields[38] as int,
      gkDiving: fields[39] == null ? null : fields[39] as int,
      gkHandling: fields[40] == null ? null : fields[40] as int,
      gkKicking: fields[41] == null ? null : fields[41] as int,
      gkPositioning: fields[42] == null ? null : fields[42] as int,
      gkReflexes: fields[43] == null ? null : fields[43] as int,
      primaryPosition: fields[44] as String,
      alternativePositions: List<String>.from(fields[45] as List),
      preferredFoot: fields[46] as String,
      weakFootQuality: fields[47] as int,
      skillMoves: fields[48] as int,
      height: fields[49] as String, weight: fields[50] as String,
      playTraits: List<String>.from(fields[51] as List),
      currentTeam: fields[52] as String, currentLeague: fields[53] as String,
      fitness: fields[54] as int, form: fields[55] as int,
      morale: fields[56] as int, matchRating: fields[57] as int,
      minutesPlayed: fields[58] as int, gamesPlayed: fields[59] as int,
      isInjured: fields[60] as bool,
      injuryType: fields[61] == null ? null : fields[61] as String,
      injuryReturnDate: fields[62] == null ? null : DateTime.fromMillisecondsSinceEpoch(fields[62] as int),
      contractExpiry: fields[63] == null ? null : DateTime.fromMillisecondsSinceEpoch(fields[63] as int),
      weeklyWage: fields[64] as double, transferValue: fields[65] as int,
      requestedTransfer: fields[66] as bool,
      hiddenAttributes: Map<String, dynamic>.from(fields[67] as Map),
    );
  }

  @override
  void write(BinaryWriter writer, Player obj) {
    writer
      ..writeByte(68)
      ..writeByte(0)..write(obj.name)
      ..writeByte(1)..write(obj.id)
      ..writeByte(2)..write(obj.nationality)
      ..writeByte(3)..write(obj.age)
      ..writeByte(4)..write(obj.ovr)
      ..writeByte(5)..write(obj.pac)
      ..writeByte(6)..write(obj.sho)
      ..writeByte(7)..write(obj.pas)
      ..writeByte(8)..write(obj.dri)
      ..writeByte(9)..write(obj.def)
      ..writeByte(10)..write(obj.phy)
      ..writeByte(11)..write(obj.acceleration)
      ..writeByte(12)..write(obj.sprintSpeed)
      ..writeByte(13)..write(obj.positioning)
      ..writeByte(14)..write(obj.finishing)
      ..writeByte(15)..write(obj.shotPower)
      ..writeByte(16)..write(obj.longShots)
      ..writeByte(17)..write(obj.volleys)
      ..writeByte(18)..write(obj.penalties)
      ..writeByte(19)..write(obj.vision)
      ..writeByte(20)..write(obj.crossing)
      ..writeByte(21)..write(obj.freeKickAccuracy)
      ..writeByte(22)..write(obj.shortPassing)
      ..writeByte(23)..write(obj.longPassing)
      ..writeByte(24)..write(obj.curve)
      ..writeByte(25)..write(obj.agility)
      ..writeByte(26)..write(obj.balance)
      ..writeByte(27)..write(obj.reactions)
      ..writeByte(28)..write(obj.ballControl)
      ..writeByte(29)..write(obj.composure)
      ..writeByte(30)..write(obj.interceptions)
      ..writeByte(31)..write(obj.headingAccuracy)
      ..writeByte(32)..write(obj.defAwareness)
      ..writeByte(33)..write(obj.standingTackle)
      ..writeByte(34)..write(obj.slidingTackle)
      ..writeByte(35)..write(obj.jumping)
      ..writeByte(36)..write(obj.staminaStat)
      ..writeByte(37)..write(obj.strength)
      ..writeByte(38)..write(obj.aggression)
      ..writeByte(39)..write(obj.gkDiving)
      ..writeByte(40)..write(obj.gkHandling)
      ..writeByte(41)..write(obj.gkKicking)
      ..writeByte(42)..write(obj.gkPositioning)
      ..writeByte(43)..write(obj.gkReflexes)
      ..writeByte(44)..write(obj.primaryPosition)
      ..writeByte(45)..write(obj.alternativePositions)
      ..writeByte(46)..write(obj.preferredFoot)
      ..writeByte(47)..write(obj.weakFootQuality)
      ..writeByte(48)..write(obj.skillMoves)
      ..writeByte(49)..write(obj.height)
      ..writeByte(50)..write(obj.weight)
      ..writeByte(51)..write(obj.playTraits)
      ..writeByte(52)..write(obj.currentTeam)
      ..writeByte(53)..write(obj.currentLeague)
      ..writeByte(54)..write(obj.fitness)
      ..writeByte(55)..write(obj.form)
      ..writeByte(56)..write(obj.morale)
      ..writeByte(57)..write(obj.matchRating)
      ..writeByte(58)..write(obj.minutesPlayed)
      ..writeByte(59)..write(obj.gamesPlayed)
      ..writeByte(60)..write(obj.isInjured)
      ..writeByte(61)..write(obj.injuryType)
      ..writeByte(62)..write(obj.injuryReturnDate?.millisecondsSinceEpoch)
      ..writeByte(63)..write(obj.contractExpiry?.millisecondsSinceEpoch)
      ..writeByte(64)..write(obj.weeklyWage)
      ..writeByte(65)..write(obj.transferValue)
      ..writeByte(66)..write(obj.requestedTransfer)
      ..writeByte(67)..write(obj.hiddenAttributes);
  }
}