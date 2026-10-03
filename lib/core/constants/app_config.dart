/// Single source of truth for app identity.
///
/// Every user-facing surface (MaterialApp title, Android label, store copy,
/// startup branding) reads from here so a rename touches exactly one file.
class AppConfig {
  AppConfig._();

  /// Store-facing app name (Play Store limit: 30 chars).
  static const String appName = 'Touchline Legend';

  /// Store short description (Play Store limit: 80 chars).
  static const String tagline = 'Your Tactics. Your Club. Your Legacy.';

  /// Version shown in menus and release notes.
  static const String version = '1.0.0';

  /// Support contact shown in the privacy policy and store listing.
  /// TODO: Replace with the studio's real support inbox before publishing.
  static const String supportEmail = 'support@yourstudio.example';
}
