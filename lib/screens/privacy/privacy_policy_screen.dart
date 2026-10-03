import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_config.dart';

/// In-app privacy policy, reachable from Settings.
///
/// The canonical hosted copy lives in `docs/store/privacy-policy.html`;
/// keep the two in sync when either changes.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Settings',
          onPressed: () => context.go('/settings'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Effective date: 30 September 2026',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          _section(
            context,
            'Overview',
            '${AppConfig.appName} is an offline football management simulation. '
                'Your career data (manager profile, club, season progress, '
                'settings) is stored locally on your device only, using the '
                'Hive local database. We operate no servers and never receive '
                'your game data.',
          ),
          _section(
            context,
            'Data we collect',
            'None. The app has no accounts, no sign-in, no analytics, and no '
                'third-party trackers. Nothing you do in the game leaves '
                'your device.',
          ),
          _section(
            context,
            'Data stored on your device',
            'Game saves (career, squad, season) and your settings are kept in '
                'app-private storage on this device. Uninstalling the app '
                'permanently deletes all of it.',
          ),
          _section(
            context,
            'Permissions',
            'The app requests no dangerous permissions. It does not access '
                'your camera, microphone, contacts, location, or files.',
          ),
          _section(
            context,
            'Advertising (planned)',
            'A future release of ${AppConfig.appName} may include '
                'advertisements served by Google AdMob. When that happens, '
                'the ad provider may collect device identifiers and usage '
                'data to deliver and measure ads, as described in Google\'s '
                'own privacy policy. This update will be announced in the '
                'release notes and this policy will be updated before the '
                'ad-enabled version ships.',
          ),
          _section(
            context,
            'Children',
            '${AppConfig.appName} is not directed at children under 13. The '
                'store listing targets ages 13 and over.',
          ),
          _section(
            context,
            'Your choices',
            'All game data is local, so you can delete everything at any '
                'time by clearing the app\'s storage from your device '
                'settings or by uninstalling the app.',
          ),
          _section(
            context,
            'Contact',
            'Questions about this policy: ${AppConfig.supportEmail}',
          ),
          const SizedBox(height: 16),
          Text(
            'The hosted version of this policy lives at the URL listed on '
            'the store listing.',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, String body) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
