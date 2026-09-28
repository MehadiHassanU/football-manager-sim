import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ffpEnabled = ref.watch(ffpEnabledProvider);
    final difficulty = ref.watch(difficultyProvider);
    final isSacking = ref.watch(isSackingEnabledProvider);
    final commentary = ref.watch(commentaryEnabledProvider);
    final commentaryAudio = ref.watch(commentaryAudioEnabledProvider);
    final crowdNoise = ref.watch(crowdNoiseEnabledProvider);
    // NOTE: sackablePercent, matchSpeed and commentaryLevel providers exist but
    // have no widget on this screen yet. Their reads were removed rather than
    // wired to dead UI; they return with the Stage 7 settings rebuild.

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Game Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SwitchListTile(
            title: const Text('Sack Enabled'),
            value: isSacking,
            onChanged: (v) => ref.read(isSackingEnabledProvider.notifier).state = v,
          ),
          SwitchListTile(
            title: const Text('FFP Enabled'),
            value: ffpEnabled,
            onChanged: (v) => ref.read(ffpEnabledProvider.notifier).state = v,
          ),
          ListTile(
            title: const Text('Difficulty'),
            subtitle: Text(difficulty),
            onTap: () {
              final options = ['Easy', 'Normal', 'Hard'];
              final idx = options.indexOf(difficulty);
              ref.read(difficultyProvider.notifier).state = options[(idx + 1) % options.length];
            },
          ),
          SwitchListTile(
            title: const Text('Commentary'),
            value: commentary,
            onChanged: (v) => ref.read(commentaryEnabledProvider.notifier).state = v,
          ),
          const SizedBox(height: 16),
          const Text('Audio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SwitchListTile(
            title: const Text('Commentary Audio'),
            value: commentaryAudio,
            onChanged: (v) => ref.read(commentaryAudioEnabledProvider.notifier).state = v,
          ),
          SwitchListTile(
            title: const Text('Crowd Noise'),
            value: crowdNoise,
            onChanged: (v) => ref.read(crowdNoiseEnabledProvider.notifier).state = v,
          ),
        ],
      ),
    );
  }
}
