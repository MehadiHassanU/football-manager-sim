import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/constants/tactic_definitions.dart';
import 'package:football_manager_sim/screens/team_management/team_management_screen.dart';
import 'package:football_manager_sim/ui/ui.dart';

import '../helpers/test_hive.dart';

/// The pitch used to place each token with `x * width - marker / 2` while the
/// token box was 2.2 markers wide, so every marker sat ~18 dp right of its
/// slot, and the goalkeeper (y = 0.93) was clamped onto the goal line.
void main() {
  testWidgets('markers are centred on their slots and stay inside the pitch',
      (tester) async {
    final squad = stubPlayerDatabase(random: Random(3)).teams.first.squad;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 328,
              child: PitchPreview(
                squad: squad,
                formation: Formation.fourFourTwo,
                height: 300,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final pitch = tester.getRect(find.byType(PitchPreview));

    // Player names are the 10 px labels under each marker.
    final labels = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(PitchPreview),
            matching: find.byType(Text),
          ),
        )
        .where((t) => t.style?.fontSize == 10)
        .toList();
    expect(labels, hasLength(11), reason: 'one label per starting slot');

    for (final label in labels) {
      final rect = tester.getRect(find.byWidget(label));
      expect(rect.left, greaterThanOrEqualTo(pitch.left),
          reason: 'token "${label.data}" overflows the left touchline');
      expect(rect.right, lessThanOrEqualTo(pitch.right),
          reason: 'token "${label.data}" overflows the right touchline');
      expect(rect.top, greaterThanOrEqualTo(pitch.top));
      expect(rect.bottom, lessThanOrEqualTo(pitch.bottom),
          reason: 'token "${label.data}" overflows the goal line');
    }

    // The keeper is the first slot of 4-4-2 and must sit on the centre line.
    final keeper = tester.getRect(find.text('0'));
    expect(keeper.center.dx, closeTo(pitch.center.dx, 1.0),
        reason:
            'the goalkeeper must be horizontally centred, not shifted right');
    expect(keeper.bottom, lessThan(pitch.bottom - 4),
        reason: 'the keeper must not be clamped against the goal line');

    // The two strikers are the highest tokens on the pitch; they must straddle
    // the centre line, which is what proves the whole row is not shifted.
    final rects = [
      for (final label in labels) tester.getRect(find.byWidget(label)),
    ]..sort((a, b) => a.top.compareTo(b.top));
    final strikerMid = (rects[0].center.dx + rects[1].center.dx) / 2;
    expect(strikerMid, closeTo(pitch.center.dx, 1.0),
        reason: 'the front two must straddle the centre');
    expect(tester.takeException(), isNull);
  });
}
