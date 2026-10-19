import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/sponsorship.dart';
import 'package:football_manager_sim/core/services/sponsorship_service.dart';
import 'package:football_manager_sim/providers/ad_provider.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';
import 'package:football_manager_sim/screens/sponsorship/sponsorship_screen.dart';

import '../helpers/test_hive.dart';

class _FakeAds implements AdService {
  _FakeAds(this.reward);

  final AdReward reward;
  int calls = 0;

  @override
  Future<AdReward> showRewarded({required String placement}) async {
    calls += 1;
    return reward;
  }
}

CareerSession _sessionWithOffers(PlayerDatabase db) {
  final team = db.teams.first;
  final session = CareerSession(
    manager: Manager(
      name: 'Boss',
      age: 40,
      nationality: 'Spain',
      teamId: team.id,
    ),
    team: team,
    season: SeasonState(leagueId: 'test_league', currentYear: 2026),
  );
  final service = SponsorshipService(rng: Random(11));
  final used = <String>{};
  for (final slot in SponsorSlot.values) {
    final offers = service.generateOffers(
      team: team,
      slot: slot,
      year: 2026,
      excludeBrands: used,
    );
    used.addAll(offers.map((o) => o.brand));
    session.sponsorshipOffers.addAll(offers);
  }
  return session;
}

Future<void> _pump(
  WidgetTester tester,
  CareerSession session,
  AdService ads,
) async {
  // Give the whole desk room: the surface is a scrolling list, and a 600px
  // window would keep the sleeve board off-screen (and therefore unbuilt).
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      careerSessionProvider.overrideWith((ref) => session),
      adServiceProvider.overrideWith((ref) => ads),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SponsorshipScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await initTestHive('fms_sponsorship_screen');
  });

  testWidgets('the desk lists every bid with its criteria and bonus',
      (tester) async {
    final db = stubLeagueDatabase(8);
    final session = _sessionWithOffers(db);
    await _pump(tester, session, _FakeAds(AdReward.earned));

    expect(find.text('COMMERCIAL INCOME'), findsOneWidget);
    expect(find.textContaining('a year'), findsWidgets);
    expect(find.textContaining('Criteria:'), findsWidgets,
        reason: 'every offer shows what the brand is paying for');
    expect(find.text('Sign'), findsNWidgets(session.sponsorshipOffers.length));
    expect(find.text('Watch an ad for fresh offers'), findsNWidgets(3));
  });

  testWidgets('signing moves the slot onto the books', (tester) async {
    final db = stubLeagueDatabase(8);
    final session = _sessionWithOffers(db);
    await _pump(tester, session, _FakeAds(AdReward.earned));
    final offer = session.sponsorshipOffers
        .firstWhere((o) => o.slot == SponsorSlot.front);

    await tester.tap(find.text('Sign').first);
    await tester.pumpAndSettle();

    expect(session.sponsorships.single.brand, offer.brand);
    expect(
      find.text('Sign'),
      findsNWidgets(session.sponsorshipOffers.length),
      reason: 'the signed slot no longer shows a shortlist',
    );
    expect(find.textContaining(offer.brand), findsWidgets,
        reason: 'the deal card names the new sponsor');
  });

  testWidgets('an unavailable ad leaves the shortlist alone', (tester) async {
    final db = stubLeagueDatabase(8);
    final session = _sessionWithOffers(db);
    final ads = _FakeAds(AdReward.unavailable);
    await _pump(tester, session, ads);
    final before = [for (final o in session.sponsorshipOffers) o.id];

    await tester.tap(find.text('Watch an ad for fresh offers').first);
    await tester.pumpAndSettle();

    expect(ads.calls, 1);
    expect([for (final o in session.sponsorshipOffers) o.id], before);
    expect(
      find.text('No ad available right now — try again shortly.'),
      findsOneWidget,
    );
  });

  testWidgets('a watched ad rerolls that slot only', (tester) async {
    final db = stubLeagueDatabase(8);
    final session = _sessionWithOffers(db);
    final ads = _FakeAds(AdReward.earned);
    await _pump(tester, session, ads);

    Set<String> idsOf(SponsorSlot slot) => {
          for (final o in session.sponsorshipOffers)
            if (o.slot == slot) o.id,
        };
    final sleeveBefore = idsOf(SponsorSlot.sleeve);
    final frontBefore = idsOf(SponsorSlot.front);

    // The last board belongs to the sleeve slot.
    await tester.tap(find.text('Watch an ad for fresh offers').last);
    await tester.pumpAndSettle();

    expect(ads.calls, 1);
    expect(idsOf(SponsorSlot.sleeve), isNot(sleeveBefore));
    expect(idsOf(SponsorSlot.sleeve).length, inInclusiveRange(2, 4));
    expect(idsOf(SponsorSlot.front), frontBefore);
    expect(find.text('New offers on the table.'), findsOneWidget);
  });

  testWidgets('a dismissed ad does not reroll', (tester) async {
    final db = stubLeagueDatabase(8);
    final session = _sessionWithOffers(db);
    final ads = _FakeAds(AdReward.dismissed);
    await _pump(tester, session, ads);
    final before = [for (final o in session.sponsorshipOffers) o.id];

    await tester.tap(find.text('Watch an ad for fresh offers').first);
    await tester.pumpAndSettle();

    expect([for (final o in session.sponsorshipOffers) o.id], before);
    expect(
      find.text('Watch the video to the end to unlock fresh offers.'),
      findsOneWidget,
    );
  });
}
