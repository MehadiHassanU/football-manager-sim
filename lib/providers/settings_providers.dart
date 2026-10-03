import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

final sackablePercentProvider = StateProvider<double>((ref) => 5.0);
final ffpEnabledProvider = StateProvider<bool>((ref) => false);
final difficultyProvider = StateProvider<String>((ref) => 'Normal');
final isSackingEnabledProvider = StateProvider<bool>((ref) => true);
final commentaryEnabledProvider = StateProvider<bool>((ref) => true);
final commentaryAudioEnabledProvider = StateProvider<bool>((ref) => true);
final crowdNoiseEnabledProvider = StateProvider<bool>((ref) => true);
final matchSpeedProvider = StateProvider<String>((ref) => 'normal');
final commentaryLevelProvider = StateProvider<String>((ref) => 'keyEvents');

const String _settingsBox = 'settings_box';

/// Persists a settings value to the Hive settings box.
Future<void> persistSetting(String key, Object value) async {
  try {
    final box = await Hive.openBox<dynamic>(_settingsBox);
    await box.put(key, value);
  } catch (_) {
    // Persistence failures must never crash the UI.
  }
}

/// Loads all persisted settings into their providers at startup.
Future<void> loadPersistedSettings(WidgetRef ref) async {
  try {
    final box = await Hive.openBox<dynamic>(_settingsBox);
    final sackable = box.get('sackablePercent') as double?;
    if (sackable != null) {
      ref.read(sackablePercentProvider.notifier).state = sackable;
    }
    final ffp = box.get('ffpEnabled') as bool?;
    if (ffp != null) ref.read(ffpEnabledProvider.notifier).state = ffp;
    final difficulty = box.get('difficulty') as String?;
    if (difficulty != null) {
      ref.read(difficultyProvider.notifier).state = difficulty;
    }
    final sacking = box.get('sackingEnabled') as bool?;
    if (sacking != null) {
      ref.read(isSackingEnabledProvider.notifier).state = sacking;
    }
    final commentary = box.get('commentary') as bool?;
    if (commentary != null) {
      ref.read(commentaryEnabledProvider.notifier).state = commentary;
    }
    final commentaryAudio = box.get('commentaryAudio') as bool?;
    if (commentaryAudio != null) {
      ref.read(commentaryAudioEnabledProvider.notifier).state = commentaryAudio;
    }
    final crowd = box.get('crowdNoise') as bool?;
    if (crowd != null) {
      ref.read(crowdNoiseEnabledProvider.notifier).state = crowd;
    }
    final speed = box.get('matchSpeed') as String?;
    if (speed != null) ref.read(matchSpeedProvider.notifier).state = speed;
    final level = box.get('commentaryLevel') as String?;
    if (level != null) {
      ref.read(commentaryLevelProvider.notifier).state = level;
    }
  } catch (_) {
    // First run or corrupted box: defaults apply.
  }
}

/// Writes every current setting to Hive (called after user changes).
Future<void> saveAllSettings(WidgetRef ref) async {
  await persistSetting('sackablePercent', ref.read(sackablePercentProvider));
  await persistSetting('ffpEnabled', ref.read(ffpEnabledProvider));
  await persistSetting('difficulty', ref.read(difficultyProvider));
  await persistSetting('sackingEnabled', ref.read(isSackingEnabledProvider));
  await persistSetting('commentary', ref.read(commentaryEnabledProvider));
  await persistSetting('commentaryAudio', ref.read(commentaryAudioEnabledProvider));
  await persistSetting('crowdNoise', ref.read(crowdNoiseEnabledProvider));
  await persistSetting('matchSpeed', ref.read(matchSpeedProvider));
  await persistSetting('commentaryLevel', ref.read(commentaryLevelProvider));
}