import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/models/player.dart';
import 'package:football_manager_sim/core/models/youth_player.dart';
import 'package:football_manager_sim/core/services/development_service.dart';

import '../helpers/test_hive.dart';

/// A stub player pinned to an age and a potential, with the hidden attribute
/// bag primed for the development engine.
Player _aged({
  required int id,
  required String name,
  required int age,
  int ovr = 60,
  int potential = 99,
}) {
  final player = stubPlayer(id: id, name: name, ovr: ovr, random: Random(id));
  player.age = age;
  player.hiddenAttributes['potential'] = potential;
  return player;
}

/// Plays [weeks] of development at a fixed weekly [minutes], counting how
/// many weeks tipped the OVR.
int _seasonTicks(Player player, {required int minutes, int weeks = 38}) {
  var ticks = 0;
  for (var week = 0; week < weeks; week++) {
    if (DevelopmentService.developWeek(
      player,
      minutes: minutes,
      leagueId: 'test_league',
      year: 2026,
      matchday: week,
    )) {
      ticks++;
    }
  }
  return ticks;
}

void main() {
  group('Weekly development', () {
    test('youth outgrow the peak years, which outgrow the veterans', () {
      final young = _aged(id: 1, name: 'Young', age: 19);
      final peak = _aged(id: 2, name: 'Peak', age: 25);
      final veteran = _aged(id: 3, name: 'Veteran', age: 29);

      final youngTicks = _seasonTicks(young, minutes: 90);
      final peakTicks = _seasonTicks(peak, minutes: 90);
      final veteranTicks = _seasonTicks(veteran, minutes: 90);

      expect(youngTicks, greaterThan(peakTicks));
      expect(peakTicks, greaterThan(veteranTicks));
      expect(young.ovr, 60 + youngTicks);
    });

    test('potential is the ceiling: OVR never grows past it', () {
      final capped = _aged(id: 4, name: 'Capped', age: 19, ovr: 70,
          potential: 70);

      expect(_seasonTicks(capped, minutes: 90), 0);
      expect(capped.ovr, 70);
      expect(capped.hiddenAttributes[DevelopmentService.progressKey], isNull);
    });

    test('game time decides how much of the week actually counts', () {
      final starter = _aged(id: 5, name: 'Starter', age: 20);
      final bench = _aged(id: 6, name: 'Bench', age: 20);

      final starterTicks = _seasonTicks(starter, minutes: 90);
      final benchTicks = _seasonTicks(bench, minutes: 5);

      expect(starterTicks, greaterThan(benchTicks));
    });

    test('an OVR point leans towards the training focus', () {
      final striker = _aged(id: 7, name: 'Striker', age: 24, ovr: 70,
          potential: 80);
      striker.hiddenAttributes['trainingFocus'] = 'Finishing';
      striker.hiddenAttributes[DevelopmentService.progressKey] = 0.99;
      final shoBefore = striker.sho;
      final pasBefore = striker.pas;
      final gkBefore = striker.gkDiving;

      final grew = DevelopmentService.developWeek(
        striker,
        minutes: 90,
        leagueId: 'test_league',
        year: 2026,
        matchday: 1,
      );

      expect(grew, isTrue);
      expect(striker.ovr, 71);
      // The focus group takes the bigger step; the other cores tag along.
      expect(striker.sho, shoBefore + 2);
      expect(striker.pas, pasBefore + 1);
      expect(striker.gkDiving, gkBefore);
    });

    test('veterans decline and never sink below the floor', () {
      final old = _aged(id: 8, name: 'Old', age: 36, ovr: 44);
      final phyBefore = old.phy;

      _seasonTicks(old, minutes: 90, weeks: 200);

      expect(old.ovr, lessThan(44));
      expect(old.ovr, greaterThanOrEqualTo(40));
      expect(old.phy, lessThan(phyBefore));
    });

    test('the same week replays identically', () {
      final first = _aged(id: 9, name: 'Replay', age: 21, ovr: 65);
      final second = _aged(id: 9, name: 'Replay', age: 21, ovr: 65);

      for (final player in [first, second]) {
        DevelopmentService.developWeek(player,
            minutes: 90, leagueId: 'l', year: 2026, matchday: 3);
        DevelopmentService.developWeek(player,
            minutes: 30, leagueId: 'l', year: 2026, matchday: 4);
      }

      expect(first.ovr, second.ovr);
      expect(
        first.hiddenAttributes[DevelopmentService.progressKey],
        second.hiddenAttributes[DevelopmentService.progressKey],
      );
      expect(first.sho, second.sho);
    });

    test('an injured player is in the treatment room, not on the grass', () {
      final hurt = _aged(id: 10, name: 'Hurt', age: 20, ovr: 65);
      hurt.isInjured = true;
      hurt.hiddenAttributes[DevelopmentService.progressKey] = 0.99;

      final grew = DevelopmentService.developWeek(
        hurt,
        minutes: 90,
        leagueId: 'l',
        year: 2026,
        matchday: 1,
      );

      expect(grew, isFalse);
      expect(hurt.ovr, 65);
      expect(hurt.hiddenAttributes[DevelopmentService.progressKey], 0.99);
    });
  });

  group('Season development for rivals', () {
    test('a rival season rolls a whole year in one pass', () {
      final rival = _aged(id: 11, name: 'Rival Youth', age: 18, ovr: 62);
      final before = rival.ovr;

      final delta = DevelopmentService.developSeason(
        rival,
        leagueId: 'test_league',
        year: 2026,
      );

      expect(rival.ovr, before + delta);
      expect(delta, greaterThan(0));
    });

    test('a rival at his potential does not move', () {
      final capped =
          _aged(id: 12, name: 'Rival Capped', age: 18, ovr: 62, potential: 62);

      final delta = DevelopmentService.developSeason(
        capped,
        leagueId: 'test_league',
        year: 2026,
      );

      expect(delta, 0);
    });

    test('recorded world growth layers onto a rebuilt squad', () {
      final a = stubPlayer(id: 20, name: 'A', ovr: 70, random: Random(2));
      final b = stubPlayer(id: 21, name: 'B', ovr: 41, random: Random(3));
      final c = stubPlayer(id: 22, name: 'C', ovr: 70, random: Random(4));

      DevelopmentService.applyWorldGrowth([a, b, c], {20: 3, 21: -5});

      expect(a.ovr, 73);
      expect(b.ovr, 40); // clamped at the floor
      expect(c.ovr, 70); // not in the map -> untouched
    });
  });

  group('Academy prospects', () {
    test('prospects tick towards their potential', () {
      final prospect = YouthPlayer(
        name: 'Prospect',
        age: 17,
        potential: 80,
        currentStats: 60,
        position: 'ST',
        nationality: 'Spain',
        random: Random(1),
      );

      var ticks = 0;
      for (var week = 0; week < 38; week++) {
        if (DevelopmentService.developYouth(
          prospect,
          leagueId: 'test_league',
          year: 2026,
          matchday: week,
        )) {
          ticks++;
        }
      }

      expect(prospect.currentStats, 60 + ticks);
      expect(ticks, greaterThan(0));
    });

    test('a finished prospect stays put', () {
      final done = YouthPlayer(
        name: 'Done',
        age: 18,
        potential: 70,
        currentStats: 70,
        position: 'CM',
        nationality: 'Spain',
        random: Random(2),
      );

      expect(
        DevelopmentService.developYouth(
          done,
          leagueId: 'test_league',
          year: 2026,
          matchday: 1,
        ),
        isFalse,
      );
      expect(done.currentStats, 70);
    });
  });
}
