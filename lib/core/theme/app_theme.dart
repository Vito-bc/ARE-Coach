import 'package:flutter/material.dart';

class AppTheme {
  static const Color _primary = Color(0xFF111827);
  static const Color _accent = Color(0xFF0F766E);

  static ThemeData light() {
    const titleColor = Color(0xFF0F172A);
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
      textTheme: ThemeData.light().textTheme
          .apply(
            bodyColor: const Color(0xFF111827),
            displayColor: const Color(0xFF111827),
            fontFamily: 'Georgia',
          )
          .copyWith(
            titleLarge: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: titleColor,
            ),
            titleMedium: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: titleColor,
            ),
            bodyLarge: const TextStyle(
              fontSize: 16,
              height: 1.35,
              color: Color(0xFF1F2937),
            ),
            bodyMedium: const TextStyle(
              fontSize: 14.5,
              height: 1.35,
              color: Color(0xFF334155),
            ),
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
          minimumSize: const Size.fromHeight(50),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF111827),
          minimumSize: const Size.fromHeight(50),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.2),
          side: const BorderSide(color: Color(0xFF9CA3AF)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: const Color(0xFF111827),
          backgroundColor: Colors.white.withValues(alpha: 0.88),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(fontWeight: FontWeight.w700, fontSize: 12);
          }
          return const TextStyle(fontWeight: FontWeight.w500, fontSize: 12);
        }),
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
      textTheme: ThemeData.dark().textTheme
          .apply(
            bodyColor: const Color(0xFFE5E7EB),
            displayColor: const Color(0xFFF3F4F6),
            fontFamily: 'Georgia',
          )
          .copyWith(
            titleLarge: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: Color(0xFFF8FAFC),
            ),
            titleMedium: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFFE2E8F0),
            ),
            bodyLarge: const TextStyle(
              fontSize: 16,
              height: 1.35,
              color: Color(0xFFE2E8F0),
            ),
            bodyMedium: const TextStyle(
              fontSize: 14.5,
              height: 1.35,
              color: Color(0xFFCBD5E1),
            ),
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
          minimumSize: const Size.fromHeight(50),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.2),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(fontWeight: FontWeight.w700, fontSize: 12);
          }
          return const TextStyle(fontWeight: FontWeight.w500, fontSize: 12);
        }),
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
