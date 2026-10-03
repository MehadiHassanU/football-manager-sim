import 'package:flutter/material.dart';

/// App-wide visual identity: "manager's office".
///
/// Deep navy surfaces, pitch-green accents, large readable numbers. Dark is
/// the default; a light variant is provided for system light-mode users.
class AppTheme {
  AppTheme._();

  // Brand palette
  static const Color pitchGreen = Color(0xFF00C853);
  static const Color pitchGreenDark = Color(0xFF009624);
  static const Color navy = Color(0xFF0B1220);
  static const Color navySurface = Color(0xFF121B2B);
  static const Color navyCard = Color(0xFF18243A);
  static const Color navyBorder = Color(0xFF24334E);

  static const Color lightBackground = Color(0xFFF6F8FB);
  static const Color lightSurface = Color(0xFFFFFFFF);

  // Stat bucket colors (OVR badges, bars)
  static Color ovrColor(int ovr) {
    if (ovr >= 85) return const Color(0xFF00E676); // elite
    if (ovr >= 75) return const Color(0xFF7CDD72); // good
    if (ovr >= 65) return const Color(0xFFFFD54F); // average
    if (ovr >= 55) return const Color(0xFFFFB74D); // weak
    return const Color(0xFFE57373); // poor
  }

  static ThemeData dark() => _build(Brightness.dark);
  static ThemeData light() => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: pitchGreen,
      brightness: brightness,
    ).copyWith(
      primary: pitchGreen,
      onPrimary: isDark ? Colors.black : Colors.white,
      secondary: const Color(0xFF40C4FF),
      surface: isDark ? navySurface : lightSurface,
      // ignore: deprecated_member_use
      background: isDark ? navy : lightBackground,
      error: const Color(0xFFEF5350),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: brightness,
    );

    return base.copyWith(
      scaffoldBackgroundColor: isDark ? navy : lightBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? navy : lightSurface,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? navyCard : lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isDark ? navyBorder : Colors.black.withValues(alpha: 0.06)),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? navyBorder : Colors.black12,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? navySurface : lightSurface,
        indicatorColor: pitchGreen.withValues(alpha: 0.18),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark ? navySurface : lightSurface,
        indicatorColor: pitchGreen.withValues(alpha: 0.18),
        selectedIconTheme: const IconThemeData(color: pitchGreen),
        selectedLabelTextStyle: const TextStyle(color: pitchGreen, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: pitchGreen,
          foregroundColor: Colors.black,
          minimumSize: const Size(64, 48),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? Colors.white : Colors.black87,
          minimumSize: const Size(64, 48),
          side: BorderSide(color: isDark ? navyBorder : Colors.black26),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textTheme: base.textTheme.copyWith(
        displaySmall: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w800,
          color: isDark ? Colors.white : Colors.black87,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : Colors.black87,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black87,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: isDark ? Colors.white70 : Colors.black87,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white54 : Colors.black54,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? navyCard : lightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: isDark ? navyBorder : Colors.black26),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: isDark ? navyBorder : Colors.black26),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: pitchGreen, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? navyCard : lightSurface,
        side: BorderSide(color: isDark ? navyBorder : Colors.black26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? navyCard : Colors.black87,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? navySurface : lightSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? pitchGreen : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? pitchGreen.withValues(alpha: 0.4)
              : null,
        ),
      ),
    );
  }
}
