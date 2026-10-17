import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';

import '../helpers/test_hive.dart';

/// Gives the tests a real [WidgetRef], which every career mutation takes.
class _Harness extends ConsumerWidget {
  const _Harness(this.action);

  final void Function(WidgetRef) action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () => action(ref),
      child: const Text('go'),
    );
  }
}

Future<void> _run(
  WidgetTester tester,
  ProviderContainer container,
  void Function(WidgetRef) action,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: _Harness(action))),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pump();
}

void main() {
  late Directory storageDir;

  setUpAll(() async {
    storageDir = await initTestHive('fms_session_notifications');
  });

  tearDownAll(() async {
    await disposeTestHive(storageDir);
  });

  /// A career on the first stub club, with a live database so persistence and
  /// transfer rules have real data.
  (ProviderContainer, CareerSession) buildCareer() {
    final db = stubPlayerDatabase(random: Random(4));
    final team = db.teams.first;
    final session = CareerSession(
      manager: Manager(name: 'Boss', age: 40, nationality: 'Spain'),
      team: team,
      season: SeasonState(leagueId: team.leagueId),
    );
    final container = ProviderContainer(
      overrides: [
        playerDatabaseProvider.overrideWith((ref) async => db),
        careerSessionProvider.overrideWith((ref) => session),
      ],
    );
    addTearDown(container.dispose);
    return (container, session);
  }

  group('in-place career mutations reach the UI', () {
    testWidgets('transfer listing notifies and persists on the player',
        (tester) async {
      final (container, session) = buildCareer();
      var notifications = 0;
      final sub = container.listen(
        careerSessionProvider,
        (_, __) => notifications++,
      );
      addTearDown(sub.close);

      final player = session.team.squad.first;
      expect(transferListingOf(player).$1, isFalse);

      await _run(
        tester,
        container,
        (ref) => setTransferListing(ref, player, listed: true),
      );

      expect(notifications, greaterThanOrEqualTo(1),
          reason: 'the switch would look dead without a provider notification');
      expect(transferListingOf(player).$1, isTrue);
      expect(transferListingOf(player).$2, isNotNull,
          reason: 'listing a player also sets an asking price');
      // The emitted value must be a new instance that shares the same squad.
      expect(
          identical(container.read(careerSessionProvider), session), isFalse);
      expect(container.read(careerSessionProvider)!.team.squad,
          same(session.team.squad));
    });

    testWidgets('loan listing notifies', (tester) async {
      final (container, session) = buildCareer();
      var notifications = 0;
      final sub = container.listen(
        careerSessionProvider,
        (_, __) => notifications++,
      );
      addTearDown(sub.close);

      final player = session.team.squad.first;
      await _run(
        tester,
        container,
        (ref) => setLoanListing(ref, player, listed: true),
      );

      expect(notifications, greaterThanOrEqualTo(1));
      expect(loanListingOf(player), isTrue);
    });

    testWidgets('youth intake notifies and adds three prospects',
        (tester) async {
      final (container, session) = buildCareer();
      var notifications = 0;
      final sub = container.listen(
        careerSessionProvider,
        (_, __) => notifications++,
      );
      addTearDown(sub.close);

      await _run(
        tester,
        container,
        (ref) => addYouthProspect(ref, count: 3),
      );

      expect(notifications, greaterThanOrEqualTo(1));
      expect(session.youthPlayers, hasLength(3));
      expect(container.read(careerSessionProvider)!.youthPlayers, hasLength(3));
    });
  });
}
