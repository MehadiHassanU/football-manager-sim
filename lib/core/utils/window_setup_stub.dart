/// Web/unsupported-platform implementation.
///
/// Desktop window controls are unavailable on the web, so this is a no-op and
/// keeps `window_manager` out of the web dependency graph.
Future<void> configureDesktopWindow() async {}
