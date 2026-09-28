import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:football_manager_sim/app.dart';

void main() {
  testWidgets('app starts on the startup screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: FootballManagerSimApp()),
    );
    // The startup screen shows an indeterminate CircularProgressIndicator, which
    // animates forever, so pumpAndSettle() can never settle and always times
    // out. A single pump renders the first frame, which is all these assertions
    // need.
    await tester.pump();

    expect(find.text('Football Manager Sim'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
