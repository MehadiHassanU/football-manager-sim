import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/tactics.dart';

final currentTacticsProvider = StateProvider<Tactic>((ref) => Tactic());
const availableTactics = ['4-4-2', '4-3-3', '4-2-3-1', '3-5-2', '4-5-1', '4-1-4-1', '4-4-2 DM', '3-4-3', '4-2-2-2', '4-1-2-3', '3-4-2-1', '5-3-2', '4-3-3 WM'];