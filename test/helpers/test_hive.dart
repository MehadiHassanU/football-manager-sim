import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/player.dart';
import 'package:football_manager_sim/core/models/team.dart';
import 'package:football_manager_sim/core/services/save_service.dart';
import 'package:football_manager_sim/providers/data_providers.dart';

/// Initialises Hive against a throwaway directory.
///
/// Widget tests boot the real app, which touches Hive during startup (settings
/// box, career restore, `hasSaveProvider`). Without an initialised backend
/// `Hive.openBox` throws, and because Hive completes its internal open
/// completer with the error, that surfaces as an *unhandled* async error that
/// fails the test even though the app catches it. Pointing Hive at a temp
/// directory keeps these tests hermetic and off platform channels.
Future<Directory> initTestHive([String prefix = 'fms_widget_test']) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = await Directory.systemTemp.createTemp(prefix);
  await SaveService().init(storageDirectory: dir.path);
  return dir;
}

/// Removes the directory created by [initTestHive].
///
/// Deliberately does NOT call `Hive.close()`: boxes opened from inside a
/// `testWidgets` fake-async zone complete their close through microtasks in
/// that zone, and by `tearDownAll` time nothing pumps it any more, so the
/// close future never resolves and the test times out. Each test file gets its
/// own temp directory and the OS reclaims it, so leaking the handles is
/// harmless.
Future<void> disposeTestHive(Directory dir) async {
  try {
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  } on IOException {
    // Windows still holds the .hive file open; the temp dir is disposable.
  }
}

/// Lets genuinely asynchronous work (Hive file I/O, asset reads) finish.
///
/// `testWidgets` runs its body inside a fake-async zone, so real Futures that
/// touch the filesystem only advance inside [WidgetTester.runAsync], and the
/// continuations they schedule only run on the next [WidgetTester.pump].
/// `pumpAndSettle` is not an option: it never settles while a progress
/// indicator spins.
///
/// This is a fixed number of `runAsync` + `pump` cycles, because each one
/// advances the real event loop by [step] and then drains the fake zone. The
/// default budget is generous because app startup opens five Hive boxes, each of
/// which needs several sequential file operations to complete.
Future<void> settleRealAsync(
  WidgetTester tester, {
  int rounds = 200,
  Duration step = const Duration(milliseconds: 5),
}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump();
  }
}

/// Like [settleRealAsync], but returns as soon as [done] holds.
///
/// [maxRounds] bounds the wait so a regression fails the test with a clear
/// message instead of hanging until the harness timeout.
Future<bool> waitForReal(
  WidgetTester tester,
  bool Function() done, {
  int maxRounds = 400,
  Duration step = const Duration(milliseconds: 5),
}) async {
  for (var i = 0; i < maxRounds; i++) {
    if (done()) return true;
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump();
  }
  return done();
}

/// Deterministic test player. Only [random] varies, so fixtures are stable
/// across runs exactly like the production CSV-driven squad builder.
Player stubPlayer({
  required int id,
  required String name,
  String position = 'CM',
  String team = 'Test FC',
  String league = 'test_league',
  int ovr = 74,
  int? gk,
  Random? random,
}) =>
    Player(
      name: name,
      id: id,
      nationality: 'Spain',
      age: 24,
      ovr: ovr,
      pac: ovr - 2,
      sho: ovr - 4,
      pas: ovr - 1,
      dri: ovr - 3,
      def: ovr - 6,
      phy: ovr - 5,
      acceleration: ovr - 2,
      sprintSpeed: ovr - 3,
      positioning: ovr - 4,
      finishing: ovr - 4,
      shotPower: ovr - 2,
      longShots: ovr - 6,
      volleys: ovr - 5,
      penalties: ovr - 7,
      vision: ovr - 1,
      crossing: ovr - 3,
      freeKickAccuracy: ovr - 6,
      shortPassing: ovr - 1,
      longPassing: ovr - 3,
      curve: ovr - 4,
      agility: ovr - 2,
      balance: ovr - 4,
      reactions: ovr - 3,
      ballControl: ovr - 2,
      composure: ovr - 4,
      interceptions: ovr - 5,
      headingAccuracy: ovr - 4,
      defAwareness: ovr - 6,
      standingTackle: ovr - 7,
      slidingTackle: ovr - 8,
      jumping: ovr - 3,
      staminaStat: ovr - 4,
      strength: ovr - 5,
      aggression: ovr - 6,
      gkDiving: gk ?? 40,
      gkHandling: gk ?? 40,
      gkKicking: gk ?? 38,
      gkPositioning: gk ?? 42,
      gkReflexes: gk ?? 41,
      primaryPosition: position,
      alternativePositions: const [],
      preferredFoot: 'Right',
      weakFootQuality: 3,
      skillMoves: 3,
      height: '180cm',
      weight: '75kg',
      playTraits: const [],
      currentTeam: team,
      currentLeague: league,
      random: random,
    );

/// Two 16-player clubs in one league, enough for New Career, the transfer
/// market and the squad screen to render real rows in a screen test.
PlayerDatabase stubPlayerDatabase({Random? random}) {
  final rng = random ?? Random(7);
  final home = <Player>[];
  final away = <Player>[];
  const positions = [
    'GK',
    'CB',
    'CB',
    'LB',
    'RB',
    'CDM',
    'CM',
    'CAM',
    'LW',
    'RW',
    'ST',
    'CF',
    'LB',
    'RB',
    'CM',
    'ST'
  ];

  for (var i = 0; i < 16; i++) {
    home.add(stubPlayer(
      id: 1000 + i,
      name: 'Home $i',
      position: positions[i],
      ovr: 70 + i,
      random: rng,
    ));
    away.add(stubPlayer(
      id: 2000 + i,
      name: 'Away $i',
      position: positions[i],
      team: 'Rival FC',
      ovr: 69 + i,
      random: rng,
    ));
  }

  final homeTeam = Team(
    id: 'test_fc',
    name: 'Test FC',
    shortName: 'TFC',
    leagueId: 'test_league',
    country: 'Spain',
    stadiumName: 'Test Park',
    stadiumCapacity: 40000,
    budget: 50000000,
    color: '#00C853',
    badgeUrl: '',
    squad: home,
  );
  final awayTeam = Team(
    id: 'rival_fc',
    name: 'Rival FC',
    shortName: 'RFC',
    leagueId: 'test_league',
    country: 'Spain',
    stadiumName: 'Rival Arena',
    stadiumCapacity: 38000,
    budget: 45000000,
    color: '#E53935',
    badgeUrl: '',
    squad: away,
  );

  return PlayerDatabase(
    players: [...home, ...away],
    teams: [homeTeam, awayTeam],
    leagues: const [
      LeagueInfo(
        id: 'test_league',
        name: 'Test League',
        country: 'Spain',
        teamCount: 2,
      ),
    ],
    playersByTeam: {
      'test_fc': home,
      'rival_fc': away,
    },
  );
}

/// Overrides that boot the app without parsing the bundled 6.6 MB dataset.
List<Override> stubDatabaseOverrides({Random? random}) => <Override>[
      playerDatabaseProvider
          .overrideWith((ref) async => stubPlayerDatabase(random: random)),
    ];

/// A whole league of [clubCount] clubs in one division.
///
/// The two-club stub is enough to render screens, but a league needs real
/// rivals for the schedule and the table to mean anything: with only two clubs
/// there is no other fixture in a round for the season logic to simulate.
PlayerDatabase stubLeagueDatabase(int clubCount, {Random? random}) {
  final rng = random ?? Random(7);
  final teams = <Team>[];
  final players = <Player>[];
  final byTeam = <String, List<Player>>{};

  for (var c = 0; c < clubCount; c++) {
    final id = 'club_$c';
    final name = 'Club $c';
    final squad = <Player>[];
    for (var i = 0; i < 16; i++) {
      squad.add(stubPlayer(
        id: clubCount * 1000 + c * 100 + i,
        name: '$name $i',
        position: positionsFor(i),
        team: name,
        ovr: 62 + (c % 8),
        random: rng,
      ));
    }
    players.addAll(squad);
    byTeam[id] = squad;
    teams.add(Team(
      id: id,
      name: name,
      shortName: 'C$c',
      leagueId: 'test_league',
      country: 'Spain',
      stadiumName: '$name Park',
      stadiumCapacity: 30000,
      budget: 10000000,
      color: '#00C853',
      badgeUrl: '',
      squad: squad,
    ));
  }

  return PlayerDatabase(
    players: players,
    teams: teams,
    leagues: [
      LeagueInfo(
        id: 'test_league',
        name: 'Test League',
        country: 'Spain',
        teamCount: clubCount,
      ),
    ],
    playersByTeam: byTeam,
  );
}

/// A workable shape: one keeper, a back four, a midfield and an attack.
String positionsFor(int i) => const [
      'GK',
      'CB',
      'CB',
      'LB',
      'RB',
      'CDM',
      'CM',
      'CAM',
      'LW',
      'RW',
      'ST',
      'CF',
      'LB',
      'RB',
      'CM',
      'ST',
    ][i % 16];
