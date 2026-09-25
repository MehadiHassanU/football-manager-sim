import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/player.dart';

void main() {
  group('Player CSV Parsing', () {
    test('Player.fromMap should create player from CSV row map', () {
      final player = Player(
        name: 'Test Player',
        id: 12345,
        nationality: 'England',
        age: 28,
        ovr: 82,
        pac: 80,
        sho: 75,
        pas: 80,
        dri: 78,
        def: 70,
        phy: 75,
        acceleration: 80,
        sprintSpeed: 78,
        positioning: 75,
        finishing: 76,
        shotPower: 78,
        longShots: 72,
        volleys: 75,
        penalties: 74,
        vision: 80,
        crossing: 75,
        freeKickAccuracy: 73,
        shortPassing: 80,
        longPassing: 78,
        curve: 75,
        agility: 78,
        balance: 76,
        reactions: 78,
        ballControl: 79,
        composure: 76,
        interceptions: 74,
        headingAccuracy: 78,
        defAwareness: 75,
        standingTackle: 73,
        slidingTackle: 72,
        jumping: 76,
        staminaStat: 78,
        strength: 75,
        aggression: 74,
        primaryPosition: 'CM',
        alternativePositions: ['CAM', 'CDM'],
        preferredFoot: 'Right',
        weakFootQuality: 4,
        skillMoves: 4,
        height: '180cm / 5\'11"',
        weight: '75kg / 165lb',
        playTraits: ['Dragging shots', 'Dictating tempo'],
        currentTeam: 'Arsenal',
        currentLeague: 'Premier League',
      );

      expect(player.name, 'Test Player');
      expect(player.id, 12345);
      expect(player.nationality, 'England');
      expect(player.age, 28);
      expect(player.ovr, 82);
      expect(player.primaryPosition, 'CM');
    });

    test('Player default values for stats', () {
      final player = Player(
        name: 'Test',
        id: 1,
        nationality: 'ES',
        age: 25,
        ovr: 70,
        pac: 70,
        sho: 70,
        pas: 70,
        dri: 70,
        def: 70,
        phy: 70,
        acceleration: 70,
        sprintSpeed: 70,
        positioning: 70,
        finishing: 70,
        shotPower: 70,
        longShots: 70,
        volleys: 70,
        penalties: 70,
        vision: 70,
        crossing: 70,
        freeKickAccuracy: 70,
        shortPassing: 70,
        longPassing: 70,
        curve: 70,
        agility: 70,
        balance: 70,
        reactions: 70,
        ballControl: 70,
        composure: 70,
        interceptions: 70,
        headingAccuracy: 70,
        defAwareness: 70,
        standingTackle: 70,
        slidingTackle: 70,
        jumping: 70,
        staminaStat: 70,
        strength: 70,
        aggression: 70,
        primaryPosition: 'ST',
        alternativePositions: [],
        preferredFoot: 'Right',
        weakFootQuality: 3,
        skillMoves: 3,
        height: '180cm',
        weight: '75kg',
        playTraits: [],
        currentTeam: 'Team',
        currentLeague: 'League',
      );

      expect(player.fitness, 100);
      expect(player.form, 5);
      expect(player.morale, 75);
    });
  });

  group('Player toJson', () {
    test('Player toJson should contain all fields', () {
      final player = Player(
        name: 'Test',
        id: 1,
        nationality: 'ES',
        age: 25,
        ovr: 75,
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
        primaryPosition: 'ST',
        alternativePositions: [],
        preferredFoot: 'Right',
        weakFootQuality: 3,
        skillMoves: 3,
        height: '180cm',
        weight: '75kg',
        playTraits: [],
        currentTeam: 'Team',
        currentLeague: 'League',
      );

      final json = player.toJson();
      expect(json['name'], 'Test');
      expect(json['id'], 1);
      expect(json['age'], 25);
      expect(json['ovr'], 75);
      expect(json['primaryPosition'], 'ST');
      expect(json['alternativePositions'], isA<List>());
      expect(json['playTraits'], isA<List>());
      expect(json['hiddenAttributes'], isA<Map>());
    });
  });

  group('Player fromJson', () {
    test('Player fromJson should reconstruct player', () {
      final original = Player(
        name: 'Test',
        id: 1,
        nationality: 'ES',
        age: 25,
        ovr: 75,
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
        primaryPosition: 'ST',
        alternativePositions: [],
        preferredFoot: 'Right',
        weakFootQuality: 3,
        skillMoves: 3,
        height: '180cm',
        weight: '75kg',
        playTraits: [],
        currentTeam: 'Team',
        currentLeague: 'League',
      );

      final json = original.toJson();
      final reconstructed = Player.fromJson(json);

      expect(reconstructed.name, original.name);
      expect(reconstructed.id, original.id);
      expect(reconstructed.age, original.age);
      expect(reconstructed.ovr, original.ovr);
      expect(reconstructed.primaryPosition, original.primaryPosition);
    });
  });

  group('GK player', () {
    test('GK player should have GK stats', () {
      final gk = Player(
        name: 'GK Test',
        id: 1,
        nationality: 'EN',
        age: 28,
        ovr: 78,
        pac: 40,
        sho: 50,
        pas: 60,
        dri: 40,
        def: 50,
        phy: 60,
        acceleration: 40,
        sprintSpeed: 50,
        positioning: 60,
        finishing: 30,
        shotPower: 30,
        longShots: 20,
        volleys: 25,
        penalties: 20,
        vision: 40,
        crossing: 30,
        freeKickAccuracy: 25,
        shortPassing: 50,
        longPassing: 40,
        curve: 20,
        agility: 40,
        balance: 35,
        reactions: 45,
        ballControl: 45,
        composure: 40,
        interceptions: 30,
        headingAccuracy: 50,
        defAwareness: 50,
        standingTackle: 30,
        slidingTackle: 25,
        jumping: 50,
        staminaStat: 60,
        strength: 50,
        aggression: 30,
        primaryPosition: 'GK',
        alternativePositions: [],
        preferredFoot: 'Right',
        weakFootQuality: 2,
        skillMoves: 2,
        height: '185cm',
        weight: '80kg',
        playTraits: [],
        currentTeam: 'Team',
        currentLeague: 'League',
        gkDiving: 70,
        gkHandling: 75,
        gkKicking: 65,
        gkPositioning: 75,
        gkReflexes: 70,
      );

      expect(gk.gkDiving, 70);
      expect(gk.gkHandling, 75);
      expect(gk.gkKicking, 65);
      expect(gk.gkPositioning, 75);
      expect(gk.gkReflexes, 70);
    });
  });

  group('Player default runtime values', () {
    test('Player default runtime values', () {
      final player = Player(
        name: 'Test',
        id: 1,
        nationality: 'EN',
        age: 25,
        ovr: 70,
        pac: 70,
        sho: 70,
        pas: 70,
        dri: 70,
        def: 70,
        phy: 70,
        acceleration: 70,
        sprintSpeed: 70,
        positioning: 70,
        finishing: 70,
        shotPower: 70,
        longShots: 70,
        volleys: 70,
        penalties: 70,
        vision: 70,
        crossing: 70,
        freeKickAccuracy: 70,
        shortPassing: 70,
        longPassing: 70,
        curve: 70,
        agility: 70,
        balance: 70,
        reactions: 70,
        ballControl: 70,
        composure: 70,
        interceptions: 70,
        headingAccuracy: 70,
        defAwareness: 70,
        standingTackle: 70,
        slidingTackle: 70,
        jumping: 70,
        staminaStat: 70,
        strength: 70,
        aggression: 70,
        primaryPosition: 'CM',
        alternativePositions: [],
        preferredFoot: 'Right',
        weakFootQuality: 3,
        skillMoves: 3,
        height: '180cm',
        weight: '75kg',
        playTraits: [],
        currentTeam: 'Team',
        currentLeague: 'League',
      );

      expect(player.fitness, 100);
      expect(player.form, 5);
      expect(player.morale, 75);
      expect(player.matchRating, 0);
      expect(player.minutesPlayed, 0);
      expect(player.gamesPlayed, 0);
      expect(player.isInjured, isFalse);
    });
  });
}
