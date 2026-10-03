import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/constants/tactic_definitions.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/player.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/team.dart';
import 'package:football_manager_sim/core/models/tactics.dart';
import 'package:football_manager_sim/core/models/youth_player.dart';
import 'package:football_manager_sim/core/services/save_service.dart';

Player _player({
  required int id,
  required String name,
  String position = 'CM',
  int ovr = 74,
  int fitness = 100,
  Random? random,
}) =>
    Player(
      name: name,
      id: id,
      nationality: 'Spain',
      age: 24,
      ovr: ovr,
      pac: ovr,
      sho: ovr,
      pas: ovr,
      dri: ovr,
      def: ovr,
      phy: ovr,
      acceleration: ovr,
      sprintSpeed: ovr,
      positioning: ovr,
      finishing: ovr,
      shotPower: ovr,
      longShots: ovr,
      volleys: ovr,
      penalties: ovr,
      vision: ovr,
      crossing: ovr,
      freeKickAccuracy: ovr,
      shortPassing: ovr,
      longPassing: ovr,
      curve: ovr,
      agility: ovr,
      balance: ovr,
      reactions: ovr,
      ballControl: ovr,
      composure: ovr,
      interceptions: ovr,
      headingAccuracy: ovr,
      defAwareness: ovr,
      standingTackle: ovr,
      slidingTackle: ovr,
      jumping: ovr,
      staminaStat: ovr,
      strength: ovr,
      aggression: ovr,
      primaryPosition: position,
      alternativePositions: const [],
      preferredFoot: 'Right',
      weakFootQuality: 3,
      skillMoves: 3,
      height: '180cm',
      weight: '75kg',
      playTraits: const [],
      currentTeam: 'Test FC',
      currentLeague: 'test_league',
      fitness: fitness,
      random: random,
    );

/// A squad that covers every slot of every supported formation.
List<Player> _fullSquad() => [
      _player(id: 1, name: 'Keeper One', position: 'GK', ovr: 78),
      _player(id: 2, name: 'Keeper Two', position: 'GK', ovr: 71),
      _player(id: 3, name: 'Defender One', position: 'CB', ovr: 77),
      _player(id: 4, name: 'Defender Two', position: 'CB', ovr: 76),
      _player(id: 5, name: 'Left Back', position: 'LB', ovr: 74),
      _player(id: 6, name: 'Right Back', position: 'RB', ovr: 73),
      _player(id: 7, name: 'Anchor', position: 'CDM', ovr: 78),
      _player(id: 8, name: 'Engine', position: 'CM', ovr: 79),
      _player(id: 9, name: 'Deep Mid', position: 'CM', ovr: 75),
      _player(id: 10, name: 'Attacking Mid', position: 'CAM', ovr: 80),
      _player(id: 11, name: 'Left Wing', position: 'LW', ovr: 79),
      _player(id: 12, name: 'Right Wing', position: 'RW', ovr: 80),
      _player(id: 13, name: 'Striker', position: 'ST', ovr: 81),
      _player(id: 14, name: 'Second Striker', position: 'CF', ovr: 77),
      _player(id: 15, name: 'Bench One', position: 'CM', ovr: 70),
      _player(id: 16, name: 'Bench Two', position: 'CB', ovr: 69),
      _player(id: 17, name: 'Bench Three', position: 'ST', ovr: 68),
      _player(id: 18, name: 'Bench Four', position: 'LB', ovr: 67),
    ];

Team _teamWithSquad() => Team(
      id: 'test_fc',
      name: 'Test FC',
      shortName: 'TFC',
      leagueId: 'test_league',
      country: 'Spain',
      stadiumName: 'Test Park',
      stadiumCapacity: 40000,
      budget: 50000000,
      color: '#00C853',
      badgeUrl: '',
      squad: _fullSquad(),
    );

void main() {
  group('Formation selection', () {
    test('every formation produces an eleven with a goalkeeper in goal', () {
      final squad = _teamWithSquad().squad;
      for (final formation in Formation.values) {
        final xi = selectStartingEleven(squad, formation);
        expect(xi.length, 11, reason: formation.name);
        expect(xi.where((p) => p.primaryPosition == 'GK').length, 1,
            reason: formation.name);
      }
    });

    test('a low-fitness keeper is dropped when a fit one exists', () {
      final squad = [
        _player(
            id: 99,
            name: 'Injured Keeper',
            position: 'GK',
            ovr: 90,
            fitness: 10),
        ..._fullSquad(),
      ];
      final xi = selectStartingEleven(squad, Formation.fourFourTwo);
      expect(
          xi.where((p) => p.primaryPosition == 'GK').single.name, 'Keeper One');
    });

    test('outfield selection excludes the keeper', () {
      final outfield =
          startingOutfield(_teamWithSquad().squad, Formation.fourThreeThree);
      expect(outfield.length, 10);
      expect(outfield.any((p) => p.primaryPosition == 'GK'), isFalse);
    });

    test('slot affinity only accepts sensible positions', () {
      expect(
          canFillSlot(_player(id: 1, name: 'K', position: 'GK'), 'GK'), isTrue);
      expect(canFillSlot(_player(id: 1, name: 'K', position: 'GK'), 'ST'),
          isFalse);
      expect(
          canFillSlot(_player(id: 1, name: 'S', position: 'ST'), 'ST'), isTrue);
    });
  });

  group('Tactic persistence', () {
    test('formation survives a JSON round-trip', () {
      const tactic = Tactic(
        formation: Formation.threeFiveTwo,
        playingStyle: PlayingStyle.counterAttack,
        tempo: Tempo.fast,
        width: Width.wide,
        defensiveLine: DefensiveLine.high,
        offsideTrap: true,
        counterPress: true,
        possessionFocus: PossessionFocus.longBalls,
        setPieceAggressive: true,
      );
      final restored = Tactic.fromJson(tactic.toJson());
      expect(restored.formation, Formation.threeFiveTwo);
      expect(restored.playingStyle, PlayingStyle.counterAttack);
      expect(restored.tempo, Tempo.fast);
      expect(restored.width, Width.wide);
      expect(restored.defensiveLine, DefensiveLine.high);
      expect(restored.offsideTrap, isTrue);
      expect(restored.counterPress, isTrue);
      expect(restored.possessionFocus, PossessionFocus.longBalls);
      expect(restored.setPieceAggressive, isTrue);
    });

    test('an old save without a formation falls back to 4-4-2', () {
      final restored = Tactic.fromJson({'playingStyle': 'defensive'});
      expect(restored.formation, Formation.fourFourTwo);
      expect(restored.playingStyle, PlayingStyle.defensive);
    });
  });

  group('Youth prospect persistence', () {
    test('key attributes survive a JSON round-trip', () {
      final youth = YouthPlayer(
        name: 'Kai Vega',
        age: 17,
        potential: 88,
        currentStats: 61,
        position: 'ST',
        nationality: 'Spain',
        random: Random(3),
      );
      youth.hiddenAttributes['keyAttributes'] = {
        for (final n in youth.keyAttributeNames) n: 72,
      };

      final restored = YouthPlayer.fromJson(youth.toJson());
      expect(restored.name, 'Kai Vega');
      expect(restored.potential, 88);
      expect(restored.keyAttributeNames, youth.keyAttributeNames);
      expect(restored.keyAttributeValues(), [72, 72, 72]);
    });

    test('scout report is derived, not random', () {
      final youth = YouthPlayer(
        name: 'Kai Vega',
        age: 17,
        potential: 88,
        currentStats: 61,
        position: 'ST',
        nationality: 'Spain',
        random: Random(3),
      );
      expect(youth.scoutReport(), youth.scoutReport());
      expect(youth.scoutReport(), contains('ST'));
    });
  });

  group('Career save round-trip', () {
    late Directory dir;
    late SaveService save;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('fms_career_persist');
      save = SaveService();
      await save.init(storageDirectory: dir.path);
    });

    tearDownAll(() async {
      // Hive was opened outside a fake-async zone here, so closing is safe.
      await save.close();
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('a team round-trips its squad through Hive', () async {
      // Regression: the Team adapter used to cast the nested squad map as
      // Map<String, dynamic> while Hive hands back Map<dynamic, dynamic>,
      // which threw and made "Continue Career" bounce back to the menu.
      final team = _teamWithSquad();
      await save.saveTeam(team);
      final loaded = await save.loadTeam(team.id);

      expect(loaded, isNotNull);
      expect(loaded!.squad.length, team.squad.length);
      expect(
        loaded.squad.map((p) => p.name).toList(),
        team.squad.map((p) => p.name).toList(),
      );
      expect(loaded.squad.first.primaryPosition, 'GK');
    });

    test('the career blob keeps nested lists and maps', () async {
      await save.saveJson('career_blob', {
        'youthPlayers': [
          {'name': 'Kai Vega', 'potential': 88},
        ],
        'startXI': [1, 2, 3],
        'savedTactics': [
          {'name': 'Press High', 'tactic': const Tactic().toJson()},
        ],
      });

      final blob = await save.loadJson('career_blob');
      expect(blob, isNotNull);
      expect((blob!['youthPlayers'] as List).length, 1);
      expect((blob['startXI'] as List).cast<int>(), [1, 2, 3]);
      expect((blob['savedTactics'] as List).first['name'], 'Press High');
    });

    test('a missing key reads back as null', () async {
      expect(await save.loadJson('never_written'), isNull);
    });

    test('manager and season restore alongside the club', () async {
      final manager = Manager(
        name: 'Boss',
        age: 40,
        nationality: 'Spain',
        teamId: 'test_fc',
      );
      final season = SeasonState(
        leagueId: 'test_league',
        currentMatchday: 3,
        totalMatchdays: 38,
        standings: const {'test_fc': 7, 'rival_fc': 4},
      );
      await save.saveManager(manager);
      await save.saveSeason(season);

      expect((await save.loadManager())?.name, 'Boss');
      expect((await save.loadSeason())?.standings['test_fc'], 7);
    });
  });
}
