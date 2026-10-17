import 'package:hive_flutter/hive_flutter.dart';
import '../../core/adapters/player_adapter.dart';
import '../../core/adapters/team_adapter.dart';
import '../../core/adapters/manager_adapter.dart';
import '../../core/adapters/season_adapter.dart';
import '../../core/models/player.dart';
import '../../core/models/team.dart';
import '../../core/models/manager.dart';
import '../../core/models/season.dart';

class SaveService {
  static const String _playersBox = 'players_box';
  static const String _teamsBox = 'teams_box';
  static const String _managerBox = 'manager_box';
  static const String _seasonBox = 'season_box';
  static const String _metaBox = 'save_meta_box';

  /// Schema version of the save format this build writes.
  ///
  /// Hive has no built-in migration path: type adapters read fields by numeric
  /// key, so removing or reinterpreting a field silently corrupts older saves.
  /// Stamping the version is what lets a future build detect a mismatch and run
  /// a migration instead of crashing on a stale adapter. Bump this on every
  /// incompatible change and add a branch to [init]'s compatibility check.
  ///
  /// v2 replaced the flat, shuffled fixture list with real per-round fixtures
  /// and league records. v1 saves still load; `tryRestoreCareer` detects them
  /// by the absent schedule and regenerates it.
  ///
  /// v3 added the knockout cup: a nullable cup block on the season (field 10)
  /// and a `competition` tag inside every persisted fixture. Both read back
  /// with safe defaults on a v2 save — no cup, league fixtures — and that
  /// career's next season attaches a cup at the rollover.
  static const int schemaVersion = 3;

  /// Opens the Hive boxes, registers adapters, and validates the save version.
  ///
  /// [storageDirectory] pins the storage location. Production passes nothing and
  /// defers to `path_provider`, while tests pass a temporary directory so they
  /// never depend on platform channels.
  ///
  /// Throws [StateError] when an existing save was written by a *newer* schema,
  /// because downgrading would lose fields this build cannot understand.
  Future<void> init({String? storageDirectory}) async {
    if (storageDirectory == null) {
      await Hive.initFlutter();
    } else {
      Hive.init(storageDirectory);
    }
    _registerAdapters();

    final stored = await storedSchemaVersion();
    if (stored != null && stored > schemaVersion) {
      throw StateError(
        'Save uses schema version $stored but this build only understands '
        'up to $schemaVersion. Refusing to open it to avoid data loss.',
      );
    }
    await _stampSchemaVersion();
  }

  /// The schema version recorded in an existing save, or `null` when the save
  /// has never been written by a version-aware build.
  Future<int?> storedSchemaVersion() async {
    final box = await Hive.openBox<dynamic>(_metaBox);
    return box.get('schemaVersion') as int?;
  }

  Future<void> _stampSchemaVersion() async {
    final box = await Hive.openBox<dynamic>(_metaBox);
    await box.put('schemaVersion', schemaVersion);
  }

  void _registerAdapters() {
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(PlayerAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(TeamAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ManagerAdapter());
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(SeasonStateAdapter());
    }
  }

  Future<void> savePlayers(List<Player> players) async {
    final box = await Hive.openBox<Player>(_playersBox);
    await box.clear();
    for (final p in players) {
      await box.put(p.id, p);
    }
  }

  Future<List<Player>> loadPlayers() async {
    final box = await Hive.openBox<Player>(_playersBox);
    return box.values.toList();
  }

  Future<void> saveTeam(Team team) async {
    final box = await Hive.openBox<Team>(_teamsBox);
    await box.put(team.id, team);
  }

  Future<Team?> loadTeam(String teamId) async {
    final box = await Hive.openBox<Team>(_teamsBox);
    return box.get(teamId);
  }

  Future<void> saveManager(Manager manager) async {
    final box = await Hive.openBox<Manager>(_managerBox);
    await box.put('current', manager);
  }

  Future<Manager?> loadManager() async {
    final box = await Hive.openBox<Manager>(_managerBox);
    return box.get('current');
  }

  Future<void> saveSeason(SeasonState season) async {
    final box = await Hive.openBox<SeasonState>(_seasonBox);
    await box.put('current', season);
  }

  Future<SeasonState?> loadSeason() async {
    final box = await Hive.openBox<SeasonState>(_seasonBox);
    return box.get('current');
  }

  /// Stores a JSON-encodable blob in the meta box (schema v1 addendum used
  /// for data that has no dedicated adapter: youth academy, form history).
  /// Erases every persisted career: the manager, the club, the season and the
  /// career blob.
  ///
  /// Used when a career genuinely ends (the board sacks the manager) so the
  /// main menu cannot offer to "Continue" a career that no longer exists. The
  /// player database and the settings box are untouched.
  Future<void> deleteCareer() async {
    for (final name in [_managerBox, _seasonBox]) {
      final box = await Hive.openBox<dynamic>(name);
      await box.clear();
    }
    final teams = await Hive.openBox<Team>(_teamsBox);
    // Only the manager's own club is a career artefact; the rest of the teams
    // box is populated by the database and shared between careers.
    final manager = await loadManager();
    if (manager != null) {
      await teams.delete(manager.teamId);
    }
    final meta = await Hive.openBox<dynamic>(_metaBox);
    await meta.delete('career_blob');
  }

  Future<void> saveJson(String key, Map<String, dynamic> value) async {
    final box = await Hive.openBox<dynamic>(_metaBox);
    await box.put(key, value);
  }

  /// Reads a JSON blob previously written by [saveJson].
  /// Returns `null` when the key does not exist.
  Future<Map<String, dynamic>?> loadJson(String key) async {
    final box = await Hive.openBox<dynamic>(_metaBox);
    final raw = box.get(key);
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<void> close() async {
    await Hive.close();
  }
}
