import 'package:flutter/material.dart';

class AppTheme {
  static const Color _primary = Color(0xFF111827);
  static const Color _accent = Color(0xFF0F766E);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _primary,
      primary: _primary,
      secondary: _accent,
      surface: const Color(0xFFF4F4F3),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: ThemeData.light().textTheme.apply(
            bodyColor: const Color(0xFF111827),
            displayColor: const Color(0xFF111827),
            fontFamily: 'Georgia',
          ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      chipTheme: ChipThemeData(
        color: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.9)),
        side: const BorderSide(color: Color(0xFFD1D5DB)),
        selectedColor: const Color(0xFFE5E7EB),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: Color(0xFF9CA3AF)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        color: Colors.white,
      ),
    );
  }
}
