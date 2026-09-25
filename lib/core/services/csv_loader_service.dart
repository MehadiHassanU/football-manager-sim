import 'package:flutter/services.dart' show rootBundle;

import '../models/player.dart';
import '../utils/csv_parser.dart';
import 'csv_file_reader_stub.dart'
    if (dart.library.io) 'csv_file_reader_io.dart';

class CsvLoaderService {
  List<Player> players = [];
  Map<int, Player> playersById = {};
  List<String> teams = [];

  Future<bool> loadFromAsset(String assetPath) async {
    try {
      final csvString = await rootBundle.loadString(assetPath);
      return _parse(csvString);
    } catch (_) {
      return false;
    }
  }

  /// Reads a CSV from disk on platforms that expose a file system.
  ///
  /// Returns `false` when the platform is web or the file cannot be read.
  Future<bool> loadFromFile(String filePath) async {
    final content = await readCsvFile(filePath);
    if (content == null) return false;
    return _parse(content);
  }

  bool _parse(String csvContent) {
    if (csvContent.isEmpty) return false;
    try {
      final parser = CSVParser(csvContent);
      players = parser.parsePlayers();
      playersById = {for (final p in players) p.id: p};
      teams = _extractTeams(players);
      return players.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  List<String> _extractTeams(List<Player> players) {
    return players.map((p) => p.currentTeam).toSet().toList();
  }
}
