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

  /// Opens the Hive boxes and registers the generated type adapters.
  ///
  /// [storageDirectory] pins the storage location. Production passes nothing and
  /// defers to `path_provider`, while tests pass a temporary directory so they
  /// never depend on platform channels.
  Future<void> init({String? storageDirectory}) async {
    if (storageDirectory == null) {
      await Hive.initFlutter();
    } else {
      Hive.init(storageDirectory);
    }
    _registerAdapters();
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

  Future<void> saveToDisk() async {
    await savePlayers(await loadPlayers());
  }

  Future<void> close() async {
    await Hive.close();
  }
}