import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/match.dart';
import 'package:football_manager_sim/screens/match/match_screen.dart';

MatchEvent _event(
  String type,
  String team, {
  Map<String, dynamic>? extraData,
}) =>
    MatchEvent(
      type: type,
      team: team,
      player: 'A Player',
      description: 'Something happened.',
      minute: 12,
      extraData: extraData,
    );

void main() {
  group('pausesUserMatch', () {
    test('the manager\'s own injury stops the match', () {
      expect(
        pausesUserMatch(_event('injury', 'home'), userTeam: 'home'),
        isTrue,
      );
      expect(
        pausesUserMatch(_event('injury', 'away'), userTeam: 'home'),
        isFalse,
        reason: 'the opponent\'s knocks are the assistant\'s problem',
      );
    });

    test('only a red card stops play', () {
      expect(
        pausesUserMatch(
          _event('card', 'away', extraData: {'red': true}),
          userTeam: 'away',
        ),
        isTrue,
      );
      expect(
        pausesUserMatch(
          _event('card', 'away', extraData: {'red': false}),
          userTeam: 'away',
        ),
        isFalse,
      );
      expect(
        pausesUserMatch(
          _event('card', 'away', extraData: {'red': true}),
          userTeam: 'home',
        ),
        isFalse,
        reason: 'a red card for the opponent does not interrupt the manager',
      );
    });

    test('ordinary events never stop the clock', () {
      for (final type in [
        'goal',
        'foul',
        'corner',
        'sub',
        'chance',
        'save',
        'commentary',
      ]) {
        expect(
          pausesUserMatch(_event(type, 'home'), userTeam: 'home'),
          isFalse,
          reason: '$type must not pause the match',
        );
      }
    });
  });
}
