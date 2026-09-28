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
  static const int schemaVersion = 1;

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
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(SeasonStateAdapter());
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

  Future<void> close() async {
    await Hive.close();
  }
}