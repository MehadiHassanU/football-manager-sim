import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/app.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/team.dart';
import 'package:football_manager_sim/core/constants/tactic_definitions.dart';
import 'package:football_manager_sim/core/models/youth_player.dart';
import 'package:football_manager_sim/ui/ui.dart';

import '../helpers/test_hive.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

Team _team({String id = 'test_fc'}) {
  return Team(
    id: id,
    name: 'Test FC',
    shortName: 'TFC',
    leagueId: 'test_league',
    country: 'Spain',
    stadiumName: 'Test Park',
    stadiumCapacity: 40000,
    budget: 50000000,
    color: '#00C853',
    badgeUrl: '',
  );
}

void main() {
  group('AppTheme', () {
    test('dark theme uses pitch green primary', () {
      expect(AppTheme.dark().colorScheme.primary, AppTheme.pitchGreen);
    });

    test('ovrColor buckets map to expected ranges', () {
      expect(AppTheme.ovrColor(90), isNot(AppTheme.ovrColor(50)));
      expect(AppTheme.ovrColor(85), AppTheme.ovrColor(99));
      expect(AppTheme.ovrColor(40), AppTheme.ovrColor(50));
    });
  });

  group('CareerSession', () {
    test('youth prospects can be added and promoted out', () {
      final session = CareerSession(
        manager: Manager(name: 'Boss', age: 40, nationality: 'Spain'),
        team: _team(),
        season: SeasonState(leagueId: 'test_league'),
      );
      expect(session.youthPlayers, isEmpty);

      final youth = YouthPlayer(
        name: 'Kai Vega',
        age: 16,
        potential: 85,
        currentStats: 55,
        position: 'CM',
        nationality: 'Spain',
      );
      session.youthPlayers.add(youth);
      expect(session.youthPlayers.length, 1);

      session.youthPlayers.remove(youth);
      expect(session.youthPlayers, isEmpty);
    });

    test('tactic updates via copyWith preserve other fields', () {
      final session = CareerSession(
        manager: Manager(name: 'Boss', age: 40, nationality: 'Spain'),
        team: _team(),
        season: SeasonState(leagueId: 'test_league'),
      );
      final updated = session.tactic.copyWith(tempo: Tempo.fast);
      expect(updated.tempo, Tempo.fast);
      expect(updated.playingStyle, PlayingStyle.balanced);
      session.tactic = updated;
      expect(session.tactic.tempo, Tempo.fast);
    });
  });

  group('FormGuide', () {
    testWidgets('renders W/D/L pills', (tester) async {
      await tester.pumpWidget(_wrap(
        const FormGuide(results: [3, 1, 0, 3]),
      ));
      expect(find.text('W'), findsNWidgets(2));
      expect(find.text('D'), findsOneWidget);
      expect(find.text('L'), findsOneWidget);
    });

    testWidgets('shows empty message with no results', (tester) async {
      await tester.pumpWidget(_wrap(
        const FormGuide(results: []),
      ));
      expect(find.text('No matches yet'), findsOneWidget);
    });
  });

  group('App', () {
    late Directory storageDir;

    setUpAll(() async {
      storageDir = await initTestHive('fms_ui_redesign');
    });

    tearDownAll(() async {
      await disposeTestHive(storageDir);
    });

    testWidgets('boots into the startup screen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: stubDatabaseOverrides(),
          child: const FootballManagerSimApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Touchline Legend'), findsOneWidget);
      // Drain the bootstrap so no in-flight Hive open leaks into other tests.
      expect(
        await waitForReal(
            tester, () => find.text('Continue').evaluate().isNotEmpty),
        isTrue,
      );
    });
  });
}
