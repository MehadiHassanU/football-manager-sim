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
      expect(season.rounds, isEmpty);
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

    test('SeasonState derives points from the club records', () {
      final season = SeasonState(
        leagueId: 'laliga',
        records: {
          'team1': LeagueRecord(won: 10),
          'team2': LeagueRecord(won: 8, drawn: 1),
          'team3': LeagueRecord(won: 6, drawn: 2),
        },
      );
      expect(season.standings['team1'], 30);
      expect(season.standings['team2'], 25);
      expect(season.standings['team3'], 20);
    });
  });
}
