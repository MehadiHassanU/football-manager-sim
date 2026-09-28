import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/screens/match/match_screen.dart';

void main() {
  group('MatchScreen', () {
    test('widget can be built', () {
      final screen = MatchScreen();
      expect(screen, isNotNull);
    });

    test('widget has key', () {
      final screen = MatchScreen();
      expect(screen.key, isNull);
    });
  });
}