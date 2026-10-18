import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/match.dart';
import 'package:football_manager_sim/screens/match/match_screen.dart';

MatchResult _score(int home, int away) => MatchResult(
      homeTeam: 'Home',
      awayTeam: 'Away',
      homeGoals: home,
      awayGoals: away,
      events: const [],
      homeMomentum: const [],
      awayMomentum: const [],
      fullTimeCommentary: '',
    );

void main() {
  group('fullTimeOutcome reads the user side, not the home score line', () {
    test('home win is a Victory', () {
      expect(
        fullTimeOutcome(result: _score(2, 1), userIsHome: true),
        'Victory',
      );
    });

    test('home loss is a Defeat', () {
      expect(
        fullTimeOutcome(result: _score(0, 3), userIsHome: true),
        'Defeat',
      );
    });

    test('home draw is a Draw', () {
      expect(
        fullTimeOutcome(result: _score(1, 1), userIsHome: true),
        'Draw',
      );
    });

    test('away win is a Victory (the old bug showed Defeat here)', () {
      expect(
        fullTimeOutcome(result: _score(0, 2), userIsHome: false),
        'Victory',
      );
    });

    test('away loss is a Defeat', () {
      expect(
        fullTimeOutcome(result: _score(3, 1), userIsHome: false),
        'Defeat',
      );
    });

    test('away draw is a Draw', () {
      expect(
        fullTimeOutcome(result: _score(2, 2), userIsHome: false),
        'Draw',
      );
    });
  });
}
