import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/player.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/youth_player.dart';
import 'package:football_manager_sim/core/services/csv_loader_service.dart';
import 'package:football_manager_sim/core/services/save_service.dart';

/// A fully specified out-field player; only [random] varies between cases.
Player _player({Random? random}) => Player(
      name: 'Seed Probe',
      id: 4242,
      nationality: 'Spain',
      age: 24,
      ovr: 80,
      pac: 78,
      sho: 74,
      pas: 79,
      dri: 77,
      def: 70,
      phy: 73,
      acceleration: 78,
      sprintSpeed: 77,
      positioning: 72,
      finishing: 74,
      shotPower: 75,
      longShots: 71,
      volleys: 72,
      penalties: 70,
      vision: 79,
      crossing: 74,
      freeKickAccuracy: 70,
      shortPassing: 79,
      longPassing: 76,
      curve: 73,
      agility: 77,
      balance: 75,
      reactions: 76,
      ballControl: 78,
      composure: 75,
      interceptions: 71,
      headingAccuracy: 73,
      defAwareness: 70,
      standingTackle: 69,
      slidingTackle: 68,
      jumping: 74,
      staminaStat: 76,
      strength: 72,
      aggression: 70,
      primaryPosition: 'CM',
      alternativePositions: const ['CAM'],
      preferredFoot: 'Right',
      weakFootQuality: 3,
      skillMoves: 3,
      height: '180cm / 5\'11"',
      weight: '75kg / 165lb',
      playTraits: const [],
      currentTeam: 'Athletic',
      currentLeague: 'LaLiga',
      random: random,
    );

YouthPlayer _youth({Random? random}) => YouthPlayer(
      name: 'Academy Probe',
      age: 17,
      potential: 84,
      currentStats: 62,
      position: 'ST',
      nationality: 'Argentina',
      random: random,
    );

void main() {
  group('Seeded generation is reproducible', () {
    test('Player hiddenAttributes are identical for the same seed', () {
      expect(
        _player(random: Random(42)).hiddenAttributes,
        _player(random: Random(42)).hiddenAttributes,
      );
    });

    test('Player hiddenAttributes differ across seeds', () {
      expect(
        _player(random: Random(1)).hiddenAttributes,
        isNot(equals(_player(random: Random(99991)).hiddenAttributes)),
      );
    });

    test('potential stays within ovr + 0..4 for every seed tried', () {
      for (final seed in const [1, 7, 13, 42, 99, 2026]) {
        final potential =
            _player(random: Random(seed)).hiddenAttributes['potential'] as int;
        expect(potential, inInclusiveRange(80, 84));
      }
    });

    test('YouthPlayer hiddenAttributes are identical for the same seed', () {
      expect(
        _youth(random: Random(42)).hiddenAttributes,
        _youth(random: Random(42)).hiddenAttributes,
      );
    });
  });

  group('SeasonState phase logic', () {
    test('isActive is driven by the calendar, not the pre-season flag', () {
      // Regression: isPreSeason defaulted to true, so a mid-season schedule
      // reported itself as inactive.
      expect(SeasonState(leagueId: 'laliga', currentMatchday: 15).isActive,
          isTrue);
      expect(SeasonState(leagueId: 'laliga').isActive, isFalse,
          reason: 'matchday 0 has not started');
      expect(
          SeasonState(leagueId: 'laliga', currentMatchday: 38, totalMatchdays: 38)
              .isActive,
          isFalse,
          reason: 'season is finished');
      expect(
          SeasonState(leagueId: 'laliga', currentMatchday: 15, isWinterBreak: true)
              .isActive,
          isFalse,
          reason: 'winter break pauses the season');
    });
  });

  group('CsvLoaderService asset seam', () {
    test('returns false when no source is injected', () async {
      expect(await CsvLoaderService().loadFromAsset('players.csv'), isFalse);
    });

    test('returns false when the source yields nothing', () async {
      final service = CsvLoaderService(assetSource: (_) async => null);
      expect(await service.loadFromAsset('players.csv'), isFalse);
    });

    test('returns false when the source throws', () async {
      final service = CsvLoaderService(
        assetSource: (_) async => throw StateError('asset missing'),
      );
      expect(await service.loadFromAsset('players.csv'), isFalse);
    });

    test('returns false for unparsable content instead of throwing', () async {
      final service = CsvLoaderService(
        assetSource: (_) async => 'not,a,valid,players,csv\n1,2,3',
      );
      expect(await service.loadFromAsset('players.csv'), isFalse);
      expect(service.players, isEmpty);
    });
  });

  group('SaveService schema stamping', () {
    test('stamps and reports the current schema version', () async {
      final dir = Directory.systemTemp.createTempSync('fms_schema');
      try {
        final service = SaveService();
        await service.init(storageDirectory: dir.path);
        expect(await service.storedSchemaVersion(), SaveService.schemaVersion);
        await service.close();
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
