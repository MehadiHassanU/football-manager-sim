import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/fixture.dart';
import 'package:football_manager_sim/core/models/manager.dart';
import 'package:football_manager_sim/core/models/match.dart';
import 'package:football_manager_sim/core/models/season.dart';
import 'package:football_manager_sim/core/models/sponsorship.dart';
import 'package:football_manager_sim/core/models/team.dart';
import 'package:football_manager_sim/core/services/sponsorship_service.dart';
import 'package:football_manager_sim/providers/career_session_provider.dart';
import 'package:football_manager_sim/providers/data_providers.dart';

import '../helpers/test_hive.dart';

/// Gives the tests a real [WidgetRef] for the provider functions.
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

CareerSession _sessionFor(PlayerDatabase db, {int matchday = 0}) {
  final ids = [for (final t in db.teams) t.id];
  final userTeam = db.teams.first;
  return CareerSession(
    manager: Manager(
      name: 'Boss',
      age: 40,
      nationality: 'Spain',
      teamId: userTeam.id,
    ),
    team: userTeam,
    season: SeasonState(
      leagueId: 'test_league',
      currentMatchday: matchday,
      currentYear: 2026,
      isPreSeason: false,
      records: {for (final id in ids) id: LeagueRecord()},
      rounds: buildRounds(ids, rng: Random(1)),
    ),
  );
}

Future<ProviderContainer> _containerFor(
  PlayerDatabase db,
  CareerSession session,
) async {
  final container = ProviderContainer(
    overrides: [
      playerDatabaseProvider.overrideWith((ref) async => db),
      careerSessionProvider.overrideWith((ref) => session),
    ],
  );
  addTearDown(container.dispose);
  await container.read(playerDatabaseProvider.future);
  return container;
}

/// A full shortlist on all three slots, generated the way a career start does.
List<SponsorshipOffer> _shortlist(Team team, int year) {
  final service = SponsorshipService(rng: Random(11));
  final used = <String>{};
  final offers = <SponsorshipOffer>[];
  for (final slot in SponsorSlot.values) {
    final slotOffers = service.generateOffers(
      team: team,
      slot: slot,
      year: year,
      excludeBrands: used,
    );
    used.addAll(slotOffers.map((o) => o.brand));
    offers.addAll(slotOffers);
  }
  return offers;
}

MatchResult _scoreline({int homeGoals = 2, int awayGoals = 1}) => MatchResult(
      homeTeam: 'Home',
      awayTeam: 'Away',
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      events: const [],
      homeMomentum: const [],
      awayMomentum: const [],
      fullTimeCommentary: '',
    );

void main() {
  setUpAll(() async {
    await initTestHive('fms_sponsorship_flow');
  });

  test('a session copy keeps the deals and the shortlist', () {
    final db = stubLeagueDatabase(8);
    final session = _sessionFor(db);
    session.sponsorships.add(Sponsorship(
      slot: SponsorSlot.front,
      brand: 'Volt Energy',
      annualValue: 3000000,
      startYear: 2026,
      durationYears: 2,
    ));
    session.sponsorshipOffers.addAll(_shortlist(session.team, 2026));

    // The copy is what every in-place bump emits. It used to drop the
    // commercial book, which is why deals vanished from Finances mid-season.
    final copy = session.shallowCopy();
    expect(copy.sponsorships, same(session.sponsorships));
    expect(copy.sponsorshipOffers, same(session.sponsorshipOffers));
  });

  testWidgets('signing an offer closes its slot and announces the deal',
      (tester) async {
    final db = stubLeagueDatabase(8);
    final session = _sessionFor(db);
    session.sponsorshipOffers.addAll(_shortlist(session.team, 2026));
    final container = await _containerFor(db, session);
    final offer = session.sponsorshipOffers
        .firstWhere((o) => o.slot == SponsorSlot.front);

    var signed = false;
    await _run(tester, container, (ref) {
      signed = signSponsorshipOffer(ref, offer);
    });

    expect(signed, isTrue);
    expect(session.sponsorships.single.slot, SponsorSlot.front);
    expect(session.sponsorships.single.brand, offer.brand);
    expect(session.sponsorships.single.annualValue, offer.annualValue);
    expect(
      session.sponsorshipOffers.any((o) => o.slot == SponsorSlot.front),
      isFalse,
      reason: 'the losing bids lapse with the signature',
    );
    expect(
      session.sponsorshipOffers.any((o) => o.slot == SponsorSlot.back),
      isTrue,
      reason: 'the other slots are untouched',
    );
    expect(
      session.transferDesk.news.any((n) => n.title.contains(offer.brand)),
      isTrue,
    );

    // A fast double-tap cannot sell the same slot twice.
    var second = true;
    await _run(tester, container, (ref) {
      second = signSponsorshipOffer(ref, offer);
    });
    expect(second, isFalse);
    expect(session.sponsorships.length, 1);
  });

  testWidgets('a reroll replaces one shortlist and spares the others',
      (tester) async {
    final db = stubLeagueDatabase(8);
    final session = _sessionFor(db);
    session.sponsorshipOffers.addAll(_shortlist(session.team, 2026));
    final container = await _containerFor(db, session);
    final frontIds = {
      for (final o in session.sponsorshipOffers)
        if (o.slot == SponsorSlot.front) o.id,
    };

    await _run(tester, container, (ref) {
      rerollSponsorshipOffers(ref, SponsorSlot.sleeve);
    });

    final sleeve = [
      for (final o in session.sponsorshipOffers)
        if (o.slot == SponsorSlot.sleeve) o,
    ];
    expect(sleeve.length, inInclusiveRange(2, 4));
    expect(sleeve.every((o) => o.year == 2026), isTrue);
    expect(
      {
        for (final o in session.sponsorshipOffers)
          if (o.slot == SponsorSlot.front) o.id,
      },
      frontIds,
      reason: 'only the rerolled slot changes',
    );
    final brands = [for (final o in session.sponsorshipOffers) o.brand];
    expect(brands.toSet().length, brands.length,
        reason: 'the new shortlist must not clash with the others');
  });

  testWidgets('the first matchday signs the best offers left',
      (tester) async {
    final db = stubLeagueDatabase(8);
    final session = _sessionFor(db);
    session.sponsorshipOffers.addAll(_shortlist(session.team, 2026));
    final container = await _containerFor(db, session);

    final service = SponsorshipService();
    final best = <SponsorSlot, SponsorshipOffer>{
      for (final slot in SponsorSlot.values)
        slot: service.bestOffer(
          service.offersForSlot(session.sponsorshipOffers, slot),
        )!,
    };
    final back = session.sponsorshipOffers
        .firstWhere((o) => o.slot == SponsorSlot.back);

    await _run(tester, container, (ref) {
      signSponsorshipOffer(ref, back);
      applyMatchResult(ref, _scoreline());
    });

    expect(session.sponsorships.length, SponsorSlot.values.length,
        reason: 'the season cannot start with an unsold shirt');
    expect(
      session.sponsorships.firstWhere((d) => d.slot == SponsorSlot.back).brand,
      back.brand,
      reason: 'the manager\'s own choice is never overwritten',
    );
    for (final slot in [SponsorSlot.front, SponsorSlot.sleeve]) {
      final deal = session.sponsorships.firstWhere((d) => d.slot == slot);
      expect(deal.brand, best[slot]!.brand,
          reason: 'the board takes the biggest cheque on $slot');
      expect(deal.annualValue, best[slot]!.annualValue);
    }
    expect(session.sponsorshipOffers, isEmpty);
    expect(
      session.transferDesk.news
          .any((n) => n.title == 'The window closes on the kit'),
      isTrue,
    );
  });

  testWidgets('the rollover pays the clauses and reopens the market',
      (tester) async {
    final db = stubLeagueDatabase(8);
    // 8 clubs play a double round-robin: 14 matchdays, all of them played.
    final session = _sessionFor(db, matchday: 14);
    final team = session.team;
    // A title-winning season: 30 wins is 90 points and first place.
    session.season.records[team.id]!
      ..played = 30
      ..won = 30
      ..goalsFor = team.goalsFor;
    final before = team.budget;
    session.sponsorships.add(Sponsorship(
      slot: SponsorSlot.front,
      brand: 'Aurora Telecom',
      annualValue: 8000000,
      startYear: 2026,
      durationYears: 1,
      clause: const SponsorshipClause(
        kind: ClauseKind.leagueTop,
        amount: 2000000,
        threshold: 4,
      ),
    ));
    final container = await _containerFor(db, session);

    SeasonOutcome? outcome;
    await _run(tester, container, (ref) {
      outcome = rollIntoNextSeason(ref);
    });

    expect(outcome, isNotNull, reason: 'the season must be over first');
    expect(team.budget - before, greaterThanOrEqualTo(2000000),
        reason: 'the top-4 clause paid on the 90-point title');
    // The rollover builds a fresh session object; the live one is the state.
    final after = container.read(careerSessionProvider)!;
    expect(
      after.sponsorships
          .any((d) => d.slot == SponsorSlot.front && d.isActiveIn(2027)),
      isFalse,
      reason: 'an expired deal is not renewed behind the manager\'s back',
    );
    expect(
      after.sponsorshipOffers
          .any((o) => o.slot == SponsorSlot.front && o.year == 2027),
      isTrue,
      reason: 'the freed slot goes back on the market',
    );
    expect(
      after.transferDesk.news.any((n) => n.title == 'Sponsors pay the bonuses'),
      isTrue,
    );
  });
}
