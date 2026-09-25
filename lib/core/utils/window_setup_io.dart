import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop/mobile implementation for the native window manager.
///
/// Failures are intentionally contained here so a platform without a native
/// window channel can still start the app.
Future<void> configureDesktopWindow() async {
  try {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(1024, 600));
    await windowManager.setSize(const Size(1400, 900));
    await windowManager.center();
  } catch (_) {}
}
