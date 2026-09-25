import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:football_manager_sim/app.dart';

void main() {
  testWidgets('app starts on the startup screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: FootballManagerSimApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Football Manager Sim'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
