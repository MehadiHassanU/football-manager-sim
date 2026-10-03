import 'package:hive/hive.dart';
import '../models/fixture.dart';
import '../models/season.dart';

/// Schema v2.
///
/// Fields 0-6 are unchanged from v1 so older saves still read. Field 7 is the
/// v1 flat "home|away" pair list, kept only so a v1 save can be detected and
/// migrated. Fields 8 and 9 are the real schedule and the league records that
/// replace it.
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
    final legacyPairs = fields[7] is List
        ? (fields[7] as List).map((e) => e.toString()).toList()
        : const <String>[];

    final rounds = <List<Fixture>>[];
    final rawRounds = fields[8];
    if (rawRounds is List) {
      for (final rawRound in rawRounds) {
        if (rawRound is! List) continue;
        rounds.add([
          for (final f in rawRound)
            if (f is Map) Fixture.fromJson(f),
        ]);
      }
    }

    final records = <String, LeagueRecord>{};
    final rawRecords = fields[9];
    if (rawRecords is Map) {
      rawRecords.forEach((key, value) {
        if (value is Map) {
          records[key.toString()] = LeagueRecord.fromJson(value);
        }
      });
    }

    return SeasonState(
      leagueId: fields[0] as String,
      currentMatchday: fields[1] as int,
      totalMatchdays: fields[2] as int,
      currentYear: fields[3] as int,
      isPreSeason: fields[4] as bool,
      isWinterBreak: fields[5] as bool,
      records:
          records.isNotEmpty ? records : _recordsFromLegacyPoints(fields[6]),
      rounds: rounds,
      legacyFixturePairs: legacyPairs,
    );
  }

  /// A v1 save stored only points per club, never wins, draws or goals. The
  /// club set is preserved so the table still lists the same clubs after a
  /// migration rather than coming back empty.
  Map<String, LeagueRecord> _recordsFromLegacyPoints(dynamic raw) {
    if (raw is! Map) return {};
    return {
      for (final entry in raw.entries) entry.key.toString(): LeagueRecord(),
    };
  }

  @override
  void write(BinaryWriter writer, SeasonState obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.leagueId)
      ..writeByte(1)
      ..write(obj.currentMatchday)
      ..writeByte(2)
      ..write(obj.totalMatchdays)
      ..writeByte(3)
      ..write(obj.currentYear)
      ..writeByte(4)
      ..write(obj.isPreSeason)
      ..writeByte(5)
      ..write(obj.isWinterBreak)
      ..writeByte(6)
      ..write(obj.standings)
      ..writeByte(7)
      ..write(obj.legacyFixturePairs)
      ..writeByte(8)
      ..write([
        for (final round in obj.rounds) [for (final f in round) f.toJson()],
      ])
      ..writeByte(9)
      ..write({
        for (final entry in obj.records.entries)
          entry.key: entry.value.toJson(),
      });
  }
}
