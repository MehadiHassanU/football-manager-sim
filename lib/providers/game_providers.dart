import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/player.dart';

// Global random provider for DI
final randomProvider = Provider<Random>((ref) => Random());

// Player list provider (loaded from CSV)
final playerListProvider = Provider<List<Player>>((ref) => []);

// Currently loaded players by ID
final playersByIdProvider = Provider<Map<int, Player>>((ref) {
  final players = ref.watch(playerListProvider);
  return {for (final p in players) p.id: p};
});