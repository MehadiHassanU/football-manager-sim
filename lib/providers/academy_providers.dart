import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/youth_player.dart';

final youthAcademyProvider = StateProvider<List<YouthPlayer>>((ref) => []);
final scoutingInProgressProvider = StateProvider<bool>((ref) => false);