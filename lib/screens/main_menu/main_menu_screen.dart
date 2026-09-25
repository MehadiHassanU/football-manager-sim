import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Main Menu')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => context.go('/career'),
              child: const Text('Career Mode'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/team-management'),
              child: const Text('Team Management'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/settings'),
              child: const Text('Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
