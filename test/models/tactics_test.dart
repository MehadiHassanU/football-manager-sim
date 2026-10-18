import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_manager_sim/core/constants/tactic_definitions.dart';
import 'package:football_manager_sim/core/models/player.dart';
import 'package:football_manager_sim/core/models/tactics.dart';

import '../helpers/test_hive.dart';

/// The manual-XI resolver: stored picks win their slots, availability still
/// has the last word, and a formation change carries the picks across.
void main() {
  List<Player> freshSquad() => stubLeagueDatabase(1).teams.first.squad;

  /// Distinct OVRs so the assistant's pecking order is testable.
  List<Player> distinctSquad() =>
      stubPlayerDatabase(random: Random(1)).teams.first.squad;

  group('Formation catalogue', () {
    test('every formation draws eleven slots with the keeper first', () {
      expect(kFormationLayouts.keys.toSet(), Formation.values.toSet(),
          reason: 'the dropdown must not offer a shape the pitch cannot draw');
      for (final formation in Formation.values) {
        final layout = kFormationLayouts[formation]!;
        expect(layout, hasLength(11), reason: formation.name);
        expect(layout.first.position, 'GK', reason: formation.name);
        expect(layout.where((s) => s.position == 'GK'), hasLength(1),
            reason: formation.name);
        for (final slot in layout) {
          expect(kPositionAffinity.containsKey(slot.position), isTrue,
              reason: '${formation.name} draws an unknown position '
                  '${slot.position}');
          expect(slot.x, inInclusiveRange(0.0, 1.0), reason: formation.name);
          expect(slot.y, inInclusiveRange(0.0, 1.0), reason: formation.name);
        }
      }
    });

    test('labels are unique and read like shapes', () {
      final labels = {for (final f in Formation.values) f.label};
      expect(labels, hasLength(Formation.values.length));
      for (final label in labels) {
        expect(label, matches(RegExp(r'^[3-5](-\d){2,3}$')), reason: label);
      }
    });

    test('the assistant can field every formation from one squad', () {
      final squad = freshSquad();
      for (final formation in Formation.values) {
        final slots = resolveFormationSlots(squad, formation, const []);
        expect(slots, hasLength(11), reason: formation.name);
        expect(slots.first.player!.primaryPosition, 'GK',
            reason: formation.name);
        final ids = [for (final slot in slots) slot.player!.id];
        expect(ids.toSet(), hasLength(11),
            reason: '${formation.name} must not field a player twice');
      }
    });
  });

  group('resolveFormationSlots', () {
    test('an empty selection is the assistant\'s pick', () {
      final squad = freshSquad();
      final auto = selectStartingEleven(squad, Formation.fourFourTwo);
      final resolved =
          resolveStartingEleven(squad, Formation.fourFourTwo, const []);
      expect(
        resolved.map((p) => p.id).toList(),
        auto.map((p) => p.id).toList(),
        reason: 'no stored picks must behave exactly like the old auto XI',
      );
    });

    test('a full manual XI seats exactly the chosen players', () {
      final squad = freshSquad();
      final layout = kFormationLayouts[Formation.fourFourTwo]!;
      final remaining = [...squad];
      final manual = <int>[];
      for (final slot in layout) {
        final pick = remaining.firstWhere(
          (p) => canFillSlot(p, slot.position),
          orElse: () => remaining.first,
        );
        remaining.remove(pick);
        manual.add(pick.id);
      }

      final slots =
          resolveFormationSlots(squad, Formation.fourFourTwo, manual);
      for (var i = 0; i < layout.length; i++) {
        expect(slots[i].player!.id, manual[i],
            reason: 'slot $i must hold the manager\'s pick');
      }
      expect(slots.every((s) => s.manual && !s.replaced), isTrue);
    });

    test('stored picks are flagged and auto slots are not', () {
      final squad = freshSquad();
      final manual = List<int>.filled(11, 0);
      manual[0] = squad[0].id; // GK
      manual[10] = squad[15].id; // second striker slot

      final slots = resolveFormationSlots(squad, Formation.fourFourTwo, manual);
      expect(slots[0].player!.id, squad[0].id);
      expect(slots[0].manual, isTrue);
      expect(slots[0].replaced, isFalse);
      expect(slots[10].player!.id, squad[15].id);
      expect(slots[10].manual, isTrue);
      expect(slots[9].manual, isFalse);

      final ids = [
        for (final s in slots)
          if (s.player != null) s.player!.id,
      ];
      expect(ids, hasLength(11));
      expect(ids.toSet().length, ids.length, reason: 'nobody plays twice');
    });

    test('an injured pick is covered by a fit team-mate and flagged', () {
      final squad = freshSquad();
      final injured = squad[1]; // CB
      injured.isInjured = true;
      final manual = List<int>.filled(11, 0);
      manual[2] = injured.id; // first centre-back slot

      final slots = resolveFormationSlots(squad, Formation.fourFourTwo, manual);
      expect(slots[2].player!.id, isNot(injured.id),
          reason: 'cover must step in while the pick is out of action');
      expect(slots[2].replaced, isTrue,
          reason: 'the manager must see his pick needs cover');
      expect(slots[2].player!.isInjured, isFalse);
      expect(
        [
          for (final s in slots)
            if (s.player != null) s.player!.id,
        ],
        isNot(contains(injured.id)),
        reason: 'a pick with fit cover never takes the field',
      );
    });

    test('when nobody fit can cover, the pick plays anyway', () {
      final squad = freshSquad();
      final striker = squad[15]; // a lone striker
      final lone = [striker];
      striker.isInjured = true;
      final manual = List<int>.filled(11, 0);
      manual[10] = striker.id;

      final slots = resolveFormationSlots(lone, Formation.fourFourTwo, manual);
      expect(slots[10].player, isNotNull);
      expect(slots[10].player!.id, striker.id);
      expect(slots[10].replaced, isFalse,
          reason: 'he may be hurt, but he is still the pick on the pitch');
      expect(slots.where((s) => s.player != null), hasLength(1));
    });

    test('a stale pick quietly returns to the assistant', () {
      final squad = freshSquad();
      final manual = List<int>.filled(11, 0);
      manual[9] = 987654; // a player who left the club long ago

      final slots = resolveFormationSlots(squad, Formation.fourFourTwo, manual);
      expect(slots[9].manual, isFalse);
      expect(slots[9].player, isNotNull, reason: 'the slot is still filled');
    });

    test('the same player cannot hold two slots', () {
      final squad = freshSquad();
      final striker = squad[15];
      final manual = List<int>.filled(11, 0);
      manual[9] = striker.id;
      manual[10] = striker.id;

      final slots = resolveFormationSlots(squad, Formation.fourFourTwo, manual);
      final placements = [
        for (final s in slots)
          if (s.player?.id == striker.id) s.position,
      ];
      expect(placements, hasLength(1),
          reason: 'he can only stand in one place');
    });
  });

  group('resolveMatchLineup', () {
    test('splits the keeper from the out-field ten', () {
      final squad = freshSquad();
      final lineup =
          resolveMatchLineup(squad, Formation.fourFourTwo, const []);
      expect(lineup.goalkeeper!.id, squad[0].id);
      expect(lineup.outfield, hasLength(10));
      expect(lineup.outfield.any((p) => p.primaryPosition == 'GK'), isFalse);
    });

    test('a stored keeper pick starts in goal', () {
      final squad = freshSquad();
      final manual = List<int>.filled(11, 0);
      manual[0] = squad[0].id;
      final lineup =
          resolveMatchLineup(squad, Formation.fourFourTwo, manual);
      expect(lineup.goalkeeper!.id, squad[0].id);
    });

    test('without a keeper the goal slot rejoins the outfield', () {
      final squad = freshSquad();
      final outfieldOnly = [
        for (final p in squad)
          if (p.primaryPosition != 'GK') p,
      ];
      final lineup =
          resolveMatchLineup(outfieldOnly, Formation.fourFourTwo, const []);
      expect(lineup.goalkeeper, isNull,
          reason: 'the match screen brings its synthetic keeper on instead');
      // The body the shape back-filled into the goal slot is no keeper, so he
      // returns to the outfield list the engine fields, exactly as before.
      expect(lineup.outfield, hasLength(11));
    });
  });

  group('resolveBenchSlots', () {
    test('the automatic bench leads with keeper cover', () {
      final squad = [...distinctSquad()];
      final fielded = {for (final p in squad.take(11)) p.id};
      // A spare keeper is the one thing a bench must carry.
      squad.add(
          stubPlayer(id: 9001, name: 'Backup Keep', position: 'GK', ovr: 60));

      final bench = resolveBenchSlots(squad, fielded, const []);
      expect(bench, hasLength(6), reason: 'every spare fits');
      expect(bench.first.player!.name, 'Backup Keep',
          reason: 'the automatic bench always names a keeper first');
      expect(bench.every((slot) => !slot.manual), isTrue);
      expect(bench.every((slot) => !fielded.contains(slot.player!.id)), isTrue,
          reason: 'nobody starts and sits on the bench');
      final rest = [for (final slot in bench.skip(1)) slot.player!];
      for (var i = 1; i < rest.length; i++) {
        expect(rest[i - 1].ovr, greaterThanOrEqualTo(rest[i].ovr),
            reason: 'after the keeper the strongest spares come first');
      }
    });

    test('stored picks are honoured, injured or not', () {
      final squad = distinctSquad();
      final fielded = {for (final p in squad.take(11)) p.id};
      final pick = squad[12]; // a spare full-back
      pick.isInjured = true;

      final bench = resolveBenchSlots(squad, fielded, [pick.id]);
      expect(bench.first.player!.id, pick.id);
      expect(bench.first.manual, isTrue);
      expect(bench.first.player!.isInjured, isTrue,
          reason: 'the manager may keep an injured player on the bench');
      expect(bench, hasLength(5));
      final ids = [for (final slot in bench) slot.player!.id];
      expect(ids.toSet().length, ids.length,
          reason: 'nobody is named twice');
    });

    test('a pick who left the club quietly returns to the assistant', () {
      final squad = distinctSquad();
      final fielded = {for (final p in squad.take(11)) p.id};
      final bench = resolveBenchSlots(squad, fielded, [424242]);
      expect(bench, hasLength(5));
      expect(bench.every((slot) => !slot.manual), isTrue);
      expect(bench.every((slot) => slot.player != null), isTrue);
    });

    test('a thin squad names what it has', () {
      final squad = distinctSquad().take(13).toList(); // a bare eleven + 2
      final fielded = {for (final p in squad.take(11)) p.id};
      final bench = resolveBenchSlots(squad, fielded, const []);
      expect(bench, hasLength(2));
    });
  });

  group('bench picks are reserved from the XI', () {
    test('a reserved player is never selected into the XI', () {
      final squad = distinctSquad();
      final striker = squad[15]; // the top-rated outfielder
      final slots = resolveFormationSlots(
        squad,
        Formation.fourFourTwo,
        const [],
        reservedIds: {striker.id},
      );
      expect(
        [
          for (final s in slots)
            if (s.player != null) s.player!.id,
        ],
        isNot(contains(striker.id)),
        reason: 'he is on the bench, not on the pitch',
      );
      expect(slots.where((s) => s.player != null), hasLength(11),
          reason: 'the next best body takes his place');
    });

    test('match lineups honour the reservation too', () {
      final squad = distinctSquad();
      final striker = squad[15];
      final lineup = resolveMatchLineup(
        squad,
        Formation.fourFourTwo,
        const [],
        reservedIds: {striker.id},
      );
      expect(lineup.outfield.map((p) => p.id), isNot(contains(striker.id)));
      expect(
        {
          if (lineup.goalkeeper != null) lineup.goalkeeper!.id,
          for (final p in lineup.outfield) p.id,
        },
        hasLength(11),
      );
    });
  });

  group('reconcileXiPicks', () {
    test('same-slot picks survive and strays find a new home', () {
      final squad = freshSquad();
      final gk = squad[0];
      final lb = squad[3];
      final winger = squad[8]; // LW: can play LM, cannot play CDM
      final manual = List<int>.filled(11, 0);
      manual[0] = gk.id;
      manual[1] = lb.id; // 4-4-2 LB -> 4-3-3 LB
      manual[5] = winger.id; // 4-4-2 LM -> 4-3-3 has no LM slot

      final result = reconcileXiPicks(
        manual,
        Formation.fourFourTwo,
        Formation.fourThreeThree,
        squad,
      );
      expect(result[0], gk.id, reason: 'the keeper stays in goal');
      expect(result[1], lb.id, reason: 'the left-back slot still exists');
      expect(result[8], winger.id,
          reason: 'the winger is re-homed to the left-wing slot');
      expect(result.last, isNot(0),
          reason: 'the sparse list must not keep trailing zeros');
    });

    test('no picks is no change', () {
      final squad = freshSquad();
      expect(
        reconcileXiPicks(const [], Formation.fourFourTwo,
            Formation.fourThreeThree, squad),
        isEmpty,
      );
    });

    test('picks who left the club are dropped', () {
      final squad = freshSquad();
      final manual = List<int>.filled(11, 0);
      manual[0] = 424242;
      manual[1] = squad[3].id;

      final result = reconcileXiPicks(
        manual,
        Formation.fourFourTwo,
        Formation.fourThreeThree,
        squad,
      );
      expect(result, isNot(contains(424242)));
      expect(result[1], squad[3].id);
    });
  });
}
