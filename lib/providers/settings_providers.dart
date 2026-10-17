import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
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

/// System / light / dark, as stored. Maps to a [ThemeMode] via [themeModeOf].
final themeModeProvider = StateProvider<String>((ref) => 'system');

const String _settingsBox = 'settings_box';

/// Every persisted setting and its default, in one table.
///
/// [resetSettingsToDefaults] reads its values from here rather than restating
/// the numbers, so a setting can never be reset to something other than the
/// default it was declared with.
const Map<String, Object> _settingDefaults = {
  'sackablePercent': 5.0,
  'ffpEnabled': false,
  'difficulty': 'Normal',
  'sackingEnabled': true,
  'commentary': true,
  'commentaryAudio': true,
  'crowdNoise': true,
  'matchSpeed': 'normal',
  'commentaryLevel': 'keyEvents',
  'themeMode': 'system',
};

/// The current value of every setting, read synchronously from its providers.
///
/// Persistence works off a snapshot rather than a captured `WidgetRef`, so a
/// debounced write never reads a provider after the widget that scheduled it
/// has been disposed.
Map<String, Object> settingsSnapshot(WidgetRef ref) {
  return {
    'sackablePercent': ref.read(sackablePercentProvider),
    'ffpEnabled': ref.read(ffpEnabledProvider),
    'difficulty': ref.read(difficultyProvider),
    'sackingEnabled': ref.read(isSackingEnabledProvider),
    'commentary': ref.read(commentaryEnabledProvider),
    'commentaryAudio': ref.read(commentaryAudioEnabledProvider),
    'crowdNoise': ref.read(crowdNoiseEnabledProvider),
    'matchSpeed': ref.read(matchSpeedProvider),
    'commentaryLevel': ref.read(commentaryLevelProvider),
    'themeMode': ref.read(themeModeProvider),
  };
}

/// Persists a single settings value to the Hive settings box.
Future<void> persistSetting(String key, Object value) async {
  try {
    final box = await Hive.openBox<dynamic>(_settingsBox);
    await box.put(key, value);
  } catch (_) {
    // Persistence failures must never crash the UI.
  }
}

/// Writes a whole [values] map in one transaction.
///
/// Takes a plain map rather than a `WidgetRef` so it is safe to call from a
/// timer and so callers can capture values before awaiting anything.
Future<void> persistSettings(Map<String, Object> values) async {
  try {
    final box = await Hive.openBox<dynamic>(_settingsBox);
    await box.putAll(values);
  } catch (_) {
    // Persistence failures must never crash the UI.
  }
}

/// Writes every current setting to Hive.
Future<void> saveAllSettings(WidgetRef ref) =>
    persistSettings(settingsSnapshot(ref));

/// Debounce window for continuous controls such as sliders.
const Duration kSettingsSaveDebounce = Duration(milliseconds: 400);

Timer? _saveDebounce;

/// Persists settings shortly after the last change.
///
/// Dragging a slider emits a change per frame; persisting each one would queue
/// hundreds of overlapping ten-key Hive writes. The snapshot is taken eagerly,
/// so the write is still correct if the widget is gone when the timer fires.
void scheduleSettingsSave(WidgetRef ref) {
  final snapshot = settingsSnapshot(ref);
  _saveDebounce?.cancel();
  _saveDebounce = Timer(kSettingsSaveDebounce, () {
    unawaited(persistSettings(snapshot));
  });
}

/// Cancels any pending debounced write and persists immediately. Used by
/// discrete controls (toggles, segmented buttons) and on leaving the screen.
void saveSettingsNow(WidgetRef ref) {
  _saveDebounce?.cancel();
  unawaited(saveAllSettings(ref));
}

/// Restores every setting to its default and persists the result.
void resetSettingsToDefaults(WidgetRef ref) {
  const defaults = _settingDefaults;
  ref.read(sackablePercentProvider.notifier).state =
      defaults['sackablePercent']! as double;
  ref.read(ffpEnabledProvider.notifier).state = defaults['ffpEnabled']! as bool;
  ref.read(difficultyProvider.notifier).state =
      defaults['difficulty']! as String;
  ref.read(isSackingEnabledProvider.notifier).state =
      defaults['sackingEnabled']! as bool;
  ref.read(commentaryEnabledProvider.notifier).state =
      defaults['commentary']! as bool;
  ref.read(matchSpeedProvider.notifier).state =
      defaults['matchSpeed']! as String;
  ref.read(commentaryLevelProvider.notifier).state =
      defaults['commentaryLevel']! as String;
  ref.read(themeModeProvider.notifier).state = defaults['themeMode']! as String;
  saveSettingsNow(ref);
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
    final themeMode = box.get('themeMode') as String?;
    if (themeMode != null) {
      ref.read(themeModeProvider.notifier).state = themeMode;
    }
  } catch (_) {
    // First run or corrupted box: defaults apply.
  }
}

/// Maps the stored theme-mode string onto a Flutter [ThemeMode].
ThemeMode themeModeOf(String value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

/// Multiplier applied to every rival's strength so that the difficulty
/// setting actually changes how the opposition plays.
///
/// "Normal" is a neutral 1.0, so the default career behaves exactly as it did
/// before this setting had any effect.
double difficultyStrengthMultiplier(String difficulty) {
  switch (difficulty) {
    case 'Easy':
      return 0.90;
    case 'Hard':
      return 1.10;
    default:
      return 1.0;
  }
}

/// How much wage-ceiling headroom a new season grants the manager, by
/// difficulty.
///
/// The board sanctions a fresh ceiling at the rollover from the opening wage
/// bill. Hard managers get a tighter sanction to plan around, Easy managers
/// a little more room to experiment. Every factor still stays close to the
/// bill the club actually carries, so all three remain constrained — this is
/// calibration, not a free pass.
double wageCeilingHeadroomFactor(String difficulty) {
  switch (difficulty) {
    case 'Easy':
      return 1.22;
    case 'Hard':
      return 1.10;
    default:
      return 1.15;
  }
}
