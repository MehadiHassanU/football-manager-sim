import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/player.dart';
import '../core/models/team.dart';

final selectedTeamProvider = Provider<Team?>((ref) => null);
final teamProvider = StateProvider<Team?>((ref) => null);
final squadProvider = Provider<List<Player>>((ref) {
  final team = ref.watch(teamProvider);
  return team?.squad ?? [];
});