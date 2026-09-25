import 'package:hive/hive.dart';
import '../models/manager.dart';

class ManagerAdapter implements TypeAdapter<Manager> {
  @override
  final int typeId = 2;

  @override
  Manager read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return Manager(
      name: fields[0] as String,
      age: fields[1] as int,
      nationality: fields[2] as String,
      teamId: fields[3] == null ? null : fields[3] as String,
      legacyScore: fields[4] as int,
      achievements: List<String>.from(fields[5] as List),
      sackablePercent: fields[6] as double,
      fanTrust: fields[7] as double,
      rival: fields[8] == null ? null : Rival(
        rivalName: fields[8]['rivalName'] as String,
        rivalTeam: fields[8]['rivalTeam'] as String,
        rivalryScore: fields[8]['rivalryScore'] as int,
        yourWins: fields[8]['yourWins'] as int,
        rivalWins: fields[8]['rivalWins'] as int,
      ),
    );
  }

  @override
  void write(BinaryWriter writer, Manager obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)..write(obj.name)
      ..writeByte(1)..write(obj.age)
      ..writeByte(2)..write(obj.nationality)
      ..writeByte(3)..write(obj.teamId)
      ..writeByte(4)..write(obj.legacyScore)
      ..writeByte(5)..write(obj.achievements)
      ..writeByte(6)..write(obj.sackablePercent)
      ..writeByte(7)..write(obj.fanTrust)
      ..writeByte(8)..write(obj.rival == null
          ? null
          : {'rivalName': obj.rival!.rivalName, 'rivalTeam': obj.rival!.rivalTeam, 'rivalryScore': obj.rival!.rivalryScore, 'yourWins': obj.rival!.yourWins, 'rivalWins': obj.rival!.rivalWins});
  }
}