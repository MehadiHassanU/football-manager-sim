import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/match.dart';
import 'package:football_manager_sim/screens/match/match_screen.dart';
import 'package:football_manager_sim/ui/ui.dart';

/// The live screen used to print `result.homeGoals` / `result.awayGoals` from
/// kick-off, so a 0-1 defeat read "0 - 1" at minute one. The scoreboard must
/// follow the goals that have actually been shown.
void main() {
  MatchResult finalScore() => MatchResult(
        homeTeam: 'Athletico',
        awayTeam: 'Real',
        homeGoals: 3,
        awayGoals: 1,
        events: [
          MatchEvent(
            type: 'kickoff',
            team: 'home',
            player: '',
            description: 'Kick-off.',
            minute: 0,
            homeScore: 0,
            awayScore: 0,
          ),
        ],
        playerRatings: const [],
        homeMomentum: const [],
        awayMomentum: const [],
        fullTimeCommentary: 'Full-time: 3 - 1',
      );

  testWidgets('kick-off shows 0-0, not the final 3-1', (tester) async {
    final result = finalScore();
    final shown = result.events.take(1).toList();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: LiveMatch(
          result: result,
          homeGoals: scoreAt(shown, 1).home,
          awayGoals: scoreAt(shown, 1).away,
          minute: 1,
          events: shown,
          homeMomentum: const [],
          awayMomentum: const [],
          onHalfTime: () {},
          onSkip: () {},
        ),
      ),
    );

    expect(find.text('0 - 0'), findsOneWidget);
    expect(find.text('3 - 1'), findsNothing);
    expect(find.text("1'"), findsOneWidget);
  });
}
