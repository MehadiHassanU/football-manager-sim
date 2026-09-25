import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/manager.dart';

void main() {
  group('Manager Model', () {
    test('Manager should be created with required fields', () {
      final manager = Manager(
        name: 'John Smith', age: 45, nationality: 'England',
      );
      expect(manager.name, 'John Smith');
      expect(manager.age, 45);
      expect(manager.nationality, 'England');
      expect(manager.teamId, isNull);
      expect(manager.legacyScore, 0);
      expect(manager.achievements, isEmpty);
      expect(manager.sackablePercent, 5.0);
      expect(manager.fanTrust, 75.0);
    });

    test('Manager with optional fields', () {
      final rival = Rival(
        rivalName: 'Pep Guardiola',
        rivalTeam: 'Manchester City',
        rivalryScore: 80,
        yourWins: 5,
        rivalWins: 10,
      );
      final manager = Manager(
        name: 'John', age: 45, nationality: 'England',
        teamId: 'MCI',
        legacyScore: 100,
        achievements: ['Title', 'Cup'],
        sackablePercent: 10.0,
        fanTrust: 90.0,
        rival: rival,
      );
      expect(manager.teamId, 'MCI');
      expect(manager.legacyScore, 100);
      expect(manager.achievements.length, 2);
      expect(manager.sackablePercent, 10.0);
      expect(manager.fanTrust, 90.0);
      expect(manager.rival, isNotNull);
      expect(manager.rival!.rivalName, 'Pep Guardiola');
    });

    test('Rival can be null', () {
      final manager = Manager(
        name: 'John', age: 45, nationality: 'England',
      );
      expect(manager.rival, isNull);
    });

    test('DramaMeter starts at zero intensity', () {
      final meter = DramaMeter();
      expect(meter.intensity, 0.0);
      expect(meter.events, isEmpty);
    });

    test('DramaMeter intensity increases', () {
      final meter = DramaMeter();
      meter.addEvent(DramaEvent(
        id: '1', title: 'Test', description: 'Test',
        timestamp: DateTime.now(), type: 'transfer_request', data: {},
      ));
      expect(meter.intensity, 15.0);
    });
  });
}