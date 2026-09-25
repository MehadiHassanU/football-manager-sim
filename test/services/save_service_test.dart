import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/player.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/team.dart';
import 'package:football_manager_sim/core/services/save_service.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  group('SaveService', () {
    late Directory storageDirectory;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      storageDirectory =
          await Directory.systemTemp.createTemp('fms_save_service_test');
    });

    tearDownAll(() async {
      await Hive.close();
      if (storageDirectory.existsSync()) {
        await storageDirectory.delete(recursive: true);
      }
    });

    Future<SaveService> createService() async {
      final service = SaveService();
      await service.init(storageDirectory: storageDirectory.path);
      return service;
    }

    test('adapters are registered', () async {
      await createService();
      expect(Hive.isAdapterRegistered(0), isTrue);
      expect(Hive.isAdapterRegistered(1), isTrue);
      expect(Hive.isAdapterRegistered(2), isTrue);
      expect(Hive.isAdapterRegistered(3), isTrue);
    });

    test('init registers adapters', () async {
      final service = await createService();
      expect(service, isA<SaveService>());
      expect(Hive.isAdapterRegistered(0), isTrue);
    });

    test('save and load players', () async {
      final service = await createService();
      await service.savePlayers([
        Player(
          name: 'P1',
          id: 1,
          nationality: 'EN',
          age: 25,
          ovr: 80,
          pac: 80,
          sho: 80,
          pas: 80,
          dri: 80,
          def: 80,
          phy: 80,
          acceleration: 80,
          sprintSpeed: 80,
          positioning: 80,
          finishing: 80,
          shotPower: 80,
          longShots: 80,
          volleys: 80,
          penalties: 80,
          vision: 80,
          crossing: 80,
          freeKickAccuracy: 80,
          shortPassing: 80,
          longPassing: 80,
          curve: 80,
          agility: 80,
          balance: 80,
          reactions: 80,
          ballControl: 80,
          composure: 80,
          interceptions: 80,
          headingAccuracy: 80,
          defAwareness: 80,
          standingTackle: 80,
          slidingTackle: 80,
          jumping: 80,
          staminaStat: 80,
          strength: 80,
          aggression: 80,
          primaryPosition: 'ST',
          alternativePositions: [],
          preferredFoot: 'Right',
          weakFootQuality: 3,
          skillMoves: 3,
          height: '180cm',
          weight: '75kg',
          playTraits: [],
          currentTeam: 'T',
          currentLeague: 'L',
        ),
        Player(
          name: 'P2',
          id: 2,
          nationality: 'ES',
          age: 28,
          ovr: 85,
          pac: 75,
          sho: 75,
          pas: 75,
          dri: 75,
          def: 75,
          phy: 75,
          acceleration: 75,
          sprintSpeed: 75,
          positioning: 75,
          finishing: 75,
          shotPower: 75,
          longShots: 75,
          volleys: 75,
          penalties: 75,
          vision: 75,
          crossing: 75,
          freeKickAccuracy: 75,
          shortPassing: 75,
          longPassing: 75,
          curve: 75,
          agility: 75,
          balance: 75,
          reactions: 75,
          ballControl: 75,
          composure: 75,
          interceptions: 75,
          headingAccuracy: 75,
          defAwareness: 75,
          standingTackle: 75,
          slidingTackle: 75,
          jumping: 75,
          staminaStat: 75,
          strength: 75,
          aggression: 75,
          primaryPosition: 'CM',
          alternativePositions: [],
          preferredFoot: 'Right',
          weakFootQuality: 3,
          skillMoves: 3,
          height: '178cm',
          weight: '73kg',
          playTraits: [],
          currentTeam: 'T',
          currentLeague: 'L',
        ),
      ]);
      final loaded = await service.loadPlayers();
      expect(loaded.length, 2);
      expect(loaded[0].name, 'P1');
      expect(loaded[1].id, 2);
    });

    test('saveTeam and loadTeam', () async {
      final service = await createService();
      await service.saveTeam(Team(
        id: '1',
        name: 'Test Club',
        shortName: 'TC',
        leagueId: 'pl',
        country: 'England',
        stadiumName: 'Stadium',
        stadiumCapacity: 50000,
        budget: 100000000,
        color: '#FF0000',
        badgeUrl: 'badge.png',
      ));
      final loaded = await service.loadTeam('1');
      expect(loaded, isNotNull);
      expect(loaded!.name, 'Test Club');
    });

    test('saveManager and loadManager', () async {
      final service = await createService();
      await service
          .saveManager(Manager(name: 'John', age: 45, nationality: 'England'));
      final loaded = await service.loadManager();
      expect(loaded, isNotNull);
      expect(loaded!.name, 'John');
    });

    test('saveSeason and loadSeason', () async {
      final service = await createService();
      await service.saveSeason(SeasonState(
          leagueId: 'laliga', currentMatchday: 10, totalMatchdays: 38));
      final loaded = await service.loadSeason();
      expect(loaded, isNotNull);
      expect(loaded!.leagueId, 'laliga');
    });
  });
}
