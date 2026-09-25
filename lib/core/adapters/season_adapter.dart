import 'package:hive/hive.dart';
import '../models/season.dart';

class SeasonStateAdapter implements TypeAdapter<SeasonState> {
  @override
  final int typeId = 3;

  @override
  SeasonState read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (int i = 0; i < numFields; i++) {
      fields[reader.readByte()] = reader.read();
    }
    return SeasonState(
      leagueId: fields[0] as String,
      currentMatchday: fields[1] as int,
      totalMatchdays: fields[2] as int,
      currentYear: fields[3] as int,
      isPreSeason: fields[4] as bool,
      isWinterBreak: fields[5] as bool,
      standings: Map<String, int>.from(fields[6] as Map),
      matchdayFixtures: List<String>.from(fields[7] as List),
    );
  }

  @override
  void write(BinaryWriter writer, SeasonState obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)..write(obj.leagueId)
      ..writeByte(1)..write(obj.currentMatchday)
      ..writeByte(2)..write(obj.totalMatchdays)
      ..writeByte(3)..write(obj.currentYear)
      ..writeByte(4)..write(obj.isPreSeason)
      ..writeByte(5)..write(obj.isWinterBreak)
      ..writeByte(6)..write(obj.standings)
      ..writeByte(7)..write(obj.matchdayFixtures);
  }
}