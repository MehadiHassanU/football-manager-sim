import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/match.dart';
import '../core/models/tactics.dart';

final currentMatchProvider = StateProvider<MatchResult?>((ref) => null);
final matchEventsProvider = Provider<List<MatchEvent>>((ref) => []);
final halfTimeTacticsProvider = StateProvider<Tactic?>((ref) => null);