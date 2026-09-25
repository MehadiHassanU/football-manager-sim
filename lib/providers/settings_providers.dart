import 'package:flutter_riverpod/flutter_riverpod.dart';

final sackablePercentProvider = StateProvider<double>((ref) => 5.0);
final ffpEnabledProvider = StateProvider<bool>((ref) => false);
final difficultyProvider = StateProvider<String>((ref) => 'Normal');
final isSackingEnabledProvider = StateProvider<bool>((ref) => true);
final commentaryEnabledProvider = StateProvider<bool>((ref) => true);
final commentaryAudioEnabledProvider = StateProvider<bool>((ref) => true);
final crowdNoiseEnabledProvider = StateProvider<bool>((ref) => true);
final matchSpeedProvider = StateProvider<String>((ref) => 'normal');
final commentaryLevelProvider = StateProvider<String>((ref) => 'keyEvents');