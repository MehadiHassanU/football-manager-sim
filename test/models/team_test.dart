import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/team.dart';
import 'package:football_manager_sim/core/models/player.dart';

void main() {
  group('Team Model', () {
    test('Team should be created with required fields', () {
      final squad = [
        Player(
          name: 'P1', id: 1, nationality: 'EN', age: 25,
          ovr: 80, pac: 80, sho: 80, pas: 80, dri: 80, def: 80, phy: 80,
          acceleration: 80, sprintSpeed: 80, positioning: 80, finishing: 80,
          shotPower: 80, longShots: 80, volleys: 80, penalties: 80,
          vision: 80, crossing: 80, freeKickAccuracy: 80, shortPassing: 80,
          longPassing: 80, curve: 80, agility: 80, balance: 80,
          reactions: 80, ballControl: 80, composure: 80, interceptions: 80,
          headingAccuracy: 80, defAwareness: 80, standingTackle: 80,
          slidingTackle: 80, jumping: 80, staminaStat: 80, strength: 80,
          aggression: 80, primaryPosition: 'ST', alternativePositions: [],
          preferredFoot: 'Right', weakFootQuality: 3, skillMoves: 3,
          height: '180cm', weight: '75kg', playTraits: [],
          currentTeam: 'Team', currentLeague: 'League',
        ),
      ];

      final team = Team(
        id: '1', name: 'Test Club', shortName: 'TC',
        leagueId: 'pl', country: 'England',
        stadiumName: 'Stadium', stadiumCapacity: 50000,
        budget: 100000000, color: '#FF0000', badgeUrl: 'badge.png',
        squad: squad,
      );

      expect(team.id, '1');
      expect(team.name, 'Test Club');
      expect(team.squad.length, 1);
      expect(team.squadSize, 1);
      expect(team.transferBudget, 30000000); // 30% of budget
      expect(team.sackablePercent, 5.0);
      expect(team.fanTrust, 75.0);
    });

    test('Team toJson should serialize squad', () {
      final squad = [
        Player(
          name: 'P1', id: 1, nationality: 'EN', age: 25,
          ovr: 80, pac: 80, sho: 80, pas: 80, dri: 80, def: 80, phy: 80,
          acceleration: 80, sprintSpeed: 80, positioning: 80, finishing: 80,
          shotPower: 80, longShots: 80, volleys: 80, penalties: 80,
          vision: 80, crossing: 80, freeKickAccuracy: 80, shortPassing: 80,
          longPassing: 80, curve: 80, agility: 80, balance: 80,
          reactions: 80, ballControl: 80, composure: 80, interceptions: 80,
          headingAccuracy: 80, defAwareness: 80, standingTackle: 80,
          slidingTackle: 80, jumping: 80, staminaStat: 80, strength: 80,
          aggression: 80, primaryPosition: 'CM', alternativePositions: [],
          preferredFoot: 'Right', weakFootQuality: 3, skillMoves: 3,
          height: '180cm', weight: '75kg', playTraits: [],
          currentTeam: 'Team', currentLeague: 'League',
        ),
      ];

      final team = Team(
        id: '1', name: 'Test Club', shortName: 'TC',
        leagueId: 'pl', country: 'England',
        stadiumName: 'Stadium', stadiumCapacity: 50000,
        budget: 100000000, color: '#FF0000', badgeUrl: 'badge.png',
        squad: squad,
      );

      final json = team.toJson();
      expect(json['squad'], isA<List>());
      expect(json['squad'].length, 1);
      expect(json['youthAcademy'], isA<List>());
      expect(json['id'], '1');
      expect(json['name'], 'Test Club');
    });

    test('Team hasSquadSpace check', () {
      final team = Team(
        id: '1', name: 'Test', shortName: 'T',
        leagueId: 'pl', country: 'EN',
        stadiumName: 'S', stadiumCapacity: 50000,
        budget: 1000000, color: '#FFF', badgeUrl: 'b',
      );
      expect(team.hasSquadSpace, isTrue);
    });

    test('Team starters filters unfit players', () {
      final squad = [
        Player(
          name: 'Fit', id: 1, nationality: 'EN', age: 25,
          ovr: 80, pac: 80, sho: 80, pas: 80, dri: 80, def: 80, phy: 80,
          acceleration: 80, sprintSpeed: 80, positioning: 80, finishing: 80,
          shotPower: 80, longShots: 80, volleys: 80, penalties: 80,
          vision: 80, crossing: 80, freeKickAccuracy: 80, shortPassing: 80,
          longPassing: 80, curve: 80, agility: 80, balance: 80,
          reactions: 80, ballControl: 80, composure: 80, interceptions: 80,
          headingAccuracy: 80, defAwareness: 80, standingTackle: 80,
          slidingTackle: 80, jumping: 80, staminaStat: 80, strength: 80,
          aggression: 80, primaryPosition: 'ST', alternativePositions: [],
          preferredFoot: 'Right', weakFootQuality: 3, skillMoves: 3,
          height: '180cm', weight: '75kg', playTraits: [],
          currentTeam: 'Team', currentLeague: 'League',
          fitness: 80,
        ),
        Player(
          name: 'Unfit', id: 2, nationality: 'EN', age: 25,
          ovr: 70, pac: 70, sho: 70, pas: 70, dri: 70, def: 70, phy: 70,
          acceleration: 70, sprintSpeed: 70, positioning: 70, finishing: 70,
          shotPower: 70, longShots: 70, volleys: 70, penalties: 70,
          vision: 70, crossing: 70, freeKickAccuracy: 70, shortPassing: 70,
          longPassing: 70, curve: 70, agility: 70, balance: 70,
          reactions: 70, ballControl: 70, composure: 70, interceptions: 70,
          headingAccuracy: 70, defAwareness: 70, standingTackle: 70,
          slidingTackle: 70, jumping: 70, staminaStat: 70, strength: 70,
          aggression: 70, primaryPosition: 'CM', alternativePositions: [],
          preferredFoot: 'Right', weakFootQuality: 3, skillMoves: 3,
          height: '180cm', weight: '75kg', playTraits: [],
          currentTeam: 'Team', currentLeague: 'League',
          fitness: 30,
        ),
      ];

      final team = Team(
        id: '1', name: 'Test', shortName: 'T',
        leagueId: 'pl', country: 'EN',
        stadiumName: 'S', stadiumCapacity: 50000,
        budget: 1000000, color: '#FFF', badgeUrl: 'b',
        squad: squad,
      );

      expect(team.starters.length, 1);
      expect(team.starters.first.name, 'Fit');
    });
  });
}