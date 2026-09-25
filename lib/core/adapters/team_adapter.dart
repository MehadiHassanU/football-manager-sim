import 'package:hive/hive.dart';
import '../models/team.dart';
import '../models/player.dart';

class TeamAdapter implements TypeAdapter<Team> {
  @override
  final int typeId = 1;

  @override
  Team read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return Team(
      id: fields[0] as String,
      name: fields[1] as String,
      shortName: fields[2] as String,
      leagueId: fields[3] as String,
      country: fields[4] as String,
      stadiumName: fields[5] as String,
      stadiumCapacity: fields[6] as int,
      budget: fields[7] as int,
      color: fields[8] as String,
      badgeUrl: fields[9] as String,
      reputation: fields[10] as int,
      fanTrust: fields[11] as int,
      squad: (fields[12] as List).map((d) => Player.fromJson(d as Map<String, dynamic>)).toList(),
      youthAcademy: (fields[13] as List).map((d) => Player.fromJson(d as Map<String, dynamic>)).toList(),
      leaguePosition: fields[14] as int,
      points: fields[15] as int,
      matchesPlayed: fields[16] as int,
      wins: fields[17] as int,
      draws: fields[18] as int,
      losses: fields[19] as int,
      goalsFor: fields[20] as int,
      goalsAgainst: fields[21] as int,
      totalWages: fields[22] as double,
      revenue: fields[23] as double,
      transferBudget: (fields[24] as num).toDouble(),
      sackablePercent: (fields[25] as num).toDouble(),
      fanLoyalty: (fields[26] as num).toDouble(),
    );
  }

  @override
  void write(BinaryWriter writer, Team obj) {
    writer
      ..writeByte(27)
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.name)
      ..writeByte(2)..write(obj.shortName)
      ..writeByte(3)..write(obj.leagueId)
      ..writeByte(4)..write(obj.country)
      ..writeByte(5)..write(obj.stadiumName)
      ..writeByte(6)..write(obj.stadiumCapacity)
      ..writeByte(7)..write(obj.budget)
      ..writeByte(8)..write(obj.color)
      ..writeByte(9)..write(obj.badgeUrl)
      ..writeByte(10)..write(obj.reputation)
      ..writeByte(11)..write(obj.fanTrust)
      ..writeByte(12)..write(obj.squad.map((p) => p.toJson()).toList())
      ..writeByte(13)..write(obj.youthAcademy.map((p) => p.toJson()).toList())
      ..writeByte(14)..write(obj.leaguePosition)
      ..writeByte(15)..write(obj.points)
      ..writeByte(16)..write(obj.matchesPlayed)
      ..writeByte(17)..write(obj.wins)
      ..writeByte(18)..write(obj.draws)
      ..writeByte(19)..write(obj.losses)
      ..writeByte(20)..write(obj.goalsFor)
      ..writeByte(21)..write(obj.goalsAgainst)
      ..writeByte(22)..write(obj.totalWages)
      ..writeByte(23)..write(obj.revenue)
      ..writeByte(24)..write(obj.transferBudget)
      ..writeByte(25)..write(obj.sackablePercent)
      ..writeByte(26)..write(obj.fanLoyalty);
  }
}