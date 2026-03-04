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

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      brightness: Brightness.dark,
      seedColor: const Color(0xFF6EE7F9),
      primary: const Color(0xFF93C5FD),
      secondary: const Color(0xFF67E8F9),
      surface: const Color(0xFF070B14),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF04070E),
      textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: const Color(0xFFE5E7EB),
            displayColor: const Color(0xFFF3F4F6),
            fontFamily: 'Georgia',
          ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      chipTheme: ChipThemeData(
        color: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.08)),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
        selectedColor: Colors.white.withValues(alpha: 0.12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF0EA5E9),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        color: Colors.white.withValues(alpha: 0.06),
      ),
    );
  }
}
