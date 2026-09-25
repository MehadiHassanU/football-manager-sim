import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/season.dart';

void main() {
  group('SeasonState Model', () {
    test('SeasonState should be created with defaults', () {
      final season = SeasonState(leagueId: 'laliga');
      expect(season.leagueId, 'laliga');
      expect(season.currentMatchday, 0);
      expect(season.totalMatchdays, 38);
      expect(season.currentYear, 2024);
      expect(season.isPreSeason, isTrue);
      expect(season.isWinterBreak, isFalse);
      expect(season.standings, isEmpty);
      expect(season.matchdayFixtures, isEmpty);
    });

    test('SeasonState isPostSeason check', () {
      final season = SeasonState(
        leagueId: 'laliga',
        currentMatchday: 38,
        totalMatchdays: 38,
      );
      expect(season.isPostSeason, isTrue);
    });

    test('SeasonState isActive check', () {
      final active = SeasonState(
        leagueId: 'laliga',
        currentMatchday: 15,
        totalMatchdays: 38,
      );
      expect(active.isActive, isTrue);

      final preSeason = SeasonState(leagueId: 'laliga', isPreSeason: true);
      expect(preSeason.isActive, isFalse);

      final postseason = SeasonState(
        leagueId: 'laliga',
        currentMatchday: 38,
        totalMatchdays: 38,
      );
      expect(postseason.isActive, isFalse);
    });

    test('SeasonState matchdayNumber is 1-based', () {
      final season = SeasonState(
        leagueId: 'laliga',
        currentMatchday: 14,
      );
      expect(season.matchdayNumber, 15);
    });

    test('SeasonState with standings', () {
      final season = SeasonState(
        leagueId: 'laliga',
        standings: {'team1': 30, 'team2': 25, 'team3': 20},
      );
      expect(season.standings['team1'], 30);
      expect(season.standings['team2'], 25);
    });
  });
}