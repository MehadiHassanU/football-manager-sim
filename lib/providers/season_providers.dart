import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/season.dart';

final seasonProvider = StateProvider<SeasonState>((ref) => SeasonState(
  leagueId: 'laliga',
  currentYear: 2024,
  totalMatchdays: 38,
));

final transferOffersProvider = StateProvider<List<TransferOffer>>((ref) => []);
final scoutingResultsProvider = StateProvider<List<ScoutingResult>>((ref) => []);