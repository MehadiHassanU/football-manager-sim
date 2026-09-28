import '../models/player.dart';
import '../utils/csv_parser.dart';
import 'csv_file_reader_stub.dart'
    if (dart.library.io) 'csv_file_reader_io.dart';

/// Supplies raw CSV text for a logical path.
///
/// Declared here so `core/` stays pure Dart and runs on the Dart VM without a
/// Flutter binding. The application layer injects a `rootBundle.loadString`
/// backed implementation; tests can inject an in-memory one.
typedef CsvSource = Future<String?> Function(String path);

class CsvLoaderService {
  /// [assetSource] is intentionally optional: with no source injected, asset
  /// loading degrades to `false` instead of pulling Flutter into the domain.
  CsvLoaderService({CsvSource? assetSource}) : _assetSource = assetSource;

  final CsvSource? _assetSource;

  List<Player> players = [];
  Map<int, Player> playersById = {};
  List<String> teams = [];

  /// Loads CSV through the injected [CsvSource].
  ///
  /// Returns `false` when no source was injected, when the source yields no
  /// content, or when parsing fails.
  Future<bool> loadFromAsset(String assetPath) async {
    final source = _assetSource;
    if (source == null) return false;
    try {
      final csvString = await source(assetPath);
      if (csvString == null) return false;
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
