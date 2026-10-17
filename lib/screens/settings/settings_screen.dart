import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/career_session_provider.dart';
import '../../providers/settings_providers.dart';
import '../../ui/ui.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final hasCareer = ref.watch(careerSessionProvider) != null;
    final ffpEnabled = ref.watch(ffpEnabledProvider);
    final difficulty = ref.watch(difficultyProvider);
    final isSacking = ref.watch(isSackingEnabledProvider);
    final commentary = ref.watch(commentaryEnabledProvider);
    final matchSpeed = ref.watch(matchSpeedProvider);
    final commentaryLevel = ref.watch(commentaryLevelProvider);
    final sackablePercent = ref.watch(sackablePercentProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Discrete controls persist immediately; sliders debounce through
    // [scheduleSettingsSave], because a drag emits a change per frame.
    void changed() => saveSettingsNow(ref);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader(title: 'Appearance'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Theme'),
                  Text('Follow the system, or pick one',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'system', label: Text('System')),
                        ButtonSegment(value: 'light', label: Text('Light')),
                        ButtonSegment(value: 'dark', label: Text('Dark')),
                      ],
                      selected: {themeMode},
                      onSelectionChanged: (selection) {
                        ref.read(themeModeProvider.notifier).state =
                            selection.first;
                        changed();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SectionHeader(title: 'Gameplay'),
          Card(
            child: Column(
              children: [
                // Full-width segmented control below the label: squeezing it
                // into a ListTile's trailing slot wraps long labels like
                // "Normal" and breaks the layout.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Difficulty'),
                      Text('Scales every rival club except yours',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'Easy', label: Text('Easy')),
                            ButtonSegment(
                                value: 'Normal', label: Text('Normal')),
                            ButtonSegment(value: 'Hard', label: Text('Hard')),
                          ],
                          selected: {difficulty},
                          onSelectionChanged: (selection) {
                            ref.read(difficultyProvider.notifier).state =
                                selection.first;
                            changed();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  title: const Text('Manager sacking'),
                  subtitle: const Text('The board can sack you at 100% risk'),
                  value: isSacking,
                  onChanged: (v) {
                    ref.read(isSackingEnabledProvider.notifier).state = v;
                    changed();
                  },
                ),
                ListTile(
                  title: const Text('Sack risk'),
                  subtitle: Slider(
                    value: sackablePercent,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '${sackablePercent.round()}%',
                    onChanged: (v) {
                      ref.read(sackablePercentProvider.notifier).state = v;
                      // Move the Home gauge with the slider, but do not write
                      // the career save on every frame of the drag.
                      syncSackRiskToManager(ref);
                      setState(() {});
                      scheduleSettingsSave(ref);
                    },
                    onChangeEnd: (_) => unawaited(saveCareerNow(ref)),
                  ),
                  trailing: Text('${sackablePercent.round()}%'),
                ),
                SwitchListTile(
                  title: const Text('FFP enforcement'),
                  subtitle: const Text(
                      'Blocks signings that breach the wage-ratio limit'),
                  value: ffpEnabled,
                  onChanged: (v) {
                    ref.read(ffpEnabledProvider.notifier).state = v;
                    changed();
                  },
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'Match presentation'),
          Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Match speed'),
                      Text('A match takes ~60s at normal speed',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'slow', label: Text('Slow')),
                            ButtonSegment(
                                value: 'normal', label: Text('Normal')),
                            ButtonSegment(value: 'fast', label: Text('Fast')),
                          ],
                          selected: {matchSpeed},
                          onSelectionChanged: (selection) {
                            ref.read(matchSpeedProvider.notifier).state =
                                selection.first;
                            changed();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Commentary level'),
                      Text(
                          commentaryLevel == 'all'
                              ? 'Every event'
                              : 'Key events only (goals, fouls, cards, '
                                  'injuries, substitutions)',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                                value: 'keyEvents', label: Text('Key')),
                            ButtonSegment(value: 'all', label: Text('All')),
                          ],
                          selected: {commentaryLevel},
                          onSelectionChanged: (selection) {
                            ref.read(commentaryLevelProvider.notifier).state =
                                selection.first;
                            changed();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'Commentary & audio'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Text commentary'),
                  subtitle: const Text('Show the live match feed during play'),
                  value: commentary,
                  onChanged: (v) {
                    ref.read(commentaryEnabledProvider.notifier).state = v;
                    changed();
                  },
                ),
                // Audio is genuinely absent from this build: there is no audio
                // dependency and no sound file in the project, so these are
                // shown as unavailable rather than as switches that do nothing.
                ListTile(
                  enabled: false,
                  leading: const Icon(Icons.volume_off_outlined),
                  title: const Text('Commentary audio & crowd noise'),
                  subtitle: const Text(
                      'Not in this build. The game ships no sound files and '
                      'plays no audio yet.'),
                ),
              ],
            ),
          ),
          if (hasCareer) ...[
            const SectionHeader(title: 'Career'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.save_outlined),
                    title: const Text('Save career now'),
                    subtitle: const Text(
                        'Manually persist your club, squad and season progress'),
                    trailing: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: _saving
                        ? null
                        : () async {
                            // Capture the messenger before awaiting so no
                            // BuildContext is used across the async gap.
                            final messenger = ScaffoldMessenger.of(context);
                            setState(() => _saving = true);
                            final ok = await saveCareerNow(ref);
                            if (!mounted) return;
                            setState(() => _saving = false);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(ok
                                    ? 'Career saved'
                                    : 'Save failed — check device storage'),
                              ),
                            );
                          },
                  ),
                  ListTile(
                    leading: const Icon(Icons.home_outlined),
                    title: const Text('Back to main menu'),
                    subtitle: const Text(
                        'Your career is saved automatically as you play'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/main-menu'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          const SectionHeader(title: 'About'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy Policy'),
                  subtitle: const Text('How your data is handled'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/privacy'),
                ),
                ListTile(
                  leading: const Icon(Icons.restart_alt),
                  title: const Text('Reset settings'),
                  subtitle: const Text('Restore every option to its default'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _confirmReset(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Settings are saved automatically',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }

  /// Asks before wiping every option; the messenger is captured up front so no
  /// [BuildContext] is used across the dialog's await.
  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset all settings?'),
        content: const Text(
            'Every option returns to its default. Your career is not '
            'affected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    resetSettingsToDefaults(ref);
    syncSackRiskToManager(ref);
    messenger.showSnackBar(
      const SnackBar(content: Text('Settings restored to defaults')),
    );
  }
}
