import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/manager.dart';

final managerProvider = StateProvider<Manager>((ref) => Manager(
  name: 'Your Name',
  age: 35,
  nationality: 'Spain',
  legacyScore: 0,
  sackablePercent: 5.0,
  fanTrust: 75.0,
));

final dramaMeterProvider = StateProvider<DramaMeter>((ref) => DramaMeter());
final achievementsProvider = StateProvider<List<Achievement>>((ref) => []);
final rivalProvider = StateProvider<Rival?>((ref) => null);