import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/career_session_provider.dart';
import '../../providers/data_providers.dart';
import '../../providers/settings_providers.dart';
import '../../core/constants/app_config.dart';
import '../../ui/ui.dart';

class StartupScreen extends ConsumerStatefulWidget {
  const StartupScreen({super.key});

  @override
  ConsumerState<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends ConsumerState<StartupScreen> {
  bool _done = false;
  bool _navigated = false;
  String _status = 'Warming up…';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Warm the player database in parallel: nothing here awaits the CSV
    // parse, so the button is ready as soon as settings + career restore
    // finish. The database keeps loading in the background and screens that
    // need it already render their own loading states.
    unawaited(
      ref.read(playerDatabaseProvider.future).then(
            (db) => debugPrint(
                '[STARTUP] Player database ready (${db.players.length} players)'),
            onError: (Object e) =>
                debugPrint('[STARTUP] Player database failed: $e'),
          ),
    );

    setState(() => _status = 'Loading settings…');
    await loadPersistedSettings(ref);

    setState(() => _status = 'Checking for saved career…');
    await tryRestoreCareer(ref);

    if (mounted) {
      setState(() => _done = true);
    }
  }

  void _navigate() {
    if (_navigated) return;
    _navigated = true;
    final hasCareer = ref.read(careerSessionProvider) != null;
    context.go(hasCareer ? '/home' : '/main-menu');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dbAsync = ref.watch(playerDatabaseProvider);
    // Database load genuinely failed (empty result): offer a retry. A still-
    // loading database does NOT block the button — that is the whole point.
    final dbFailed =
        _done && dbAsync.hasValue && (dbAsync.value?.players.isEmpty ?? false);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) =>
                    Transform.scale(scale: value, child: child),
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppTheme.pitchGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(
                    Icons.sports_soccer,
                    size: 56,
                    color: AppTheme.pitchGreen,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(AppConfig.appName, style: theme.textTheme.displaySmall),
              const SizedBox(height: 8),
              Text(
                AppConfig.tagline,
                style: theme.textTheme.bodySmall,
              ),
              const Spacer(),
              if (!_done) ...[
                const CircularProgressIndicator(color: AppTheme.pitchGreen),
                const SizedBox(height: 16),
                Text(_status, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: 'Skip',
                    onPressed: _navigate,
                  ),
                ),
              ] else if (dbFailed) ...[
                ErrorState(
                  message: 'Could not load the player database.',
                  onRetry: () {
                    ref.invalidate(playerDatabaseProvider);
                    // Kick off a fresh load; failures surface in the ErrorState
                    // that [playerDatabaseProvider] renders.
                    unawaited(ref.read(playerDatabaseProvider.future).then(
                          (_) {},
                          onError: (Object e) =>
                              debugPrint('[STARTUP] retry failed: $e'),
                        ));
                  },
                ),
              ] else ...[
                // Instant-ready: button only, no extra status text.
                SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    label: 'Continue',
                    onPressed: _navigate,
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
