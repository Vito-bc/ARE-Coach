import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  // Apple-inspired palette
  static const Color _blue = Color(0xFF007AFF);
  static const Color _label = Color(0xFF1C1C1E);
  static const Color _secondaryLabel = Color(0xFF6E6E73);
  static const Color _systemBackground = Color(0xFFFFFFFF);
  static const Color _secondaryBackground = Color(0xFFF2F2F7);
  static const Color _separator = Color(0xFFC6C6C8);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _blue,
      primary: _blue,
      secondary: _blue,
      surface: _secondaryBackground,
      onSurface: _label,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _secondaryBackground,
      textTheme: _textTheme(brightness: Brightness.light),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _secondaryBackground,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: _label,
          letterSpacing: -0.2,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _blue,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            letterSpacing: -0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _blue,
          minimumSize: const Size.fromHeight(50),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          side: const BorderSide(color: _blue),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _blue,
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: _blue,
          backgroundColor: const Color(0xFFE8F1FF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _systemBackground,
        side: const BorderSide(color: _separator),
        labelStyle: const TextStyle(
          color: _secondaryLabel,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: _systemBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        shadowColor: Colors.black.withValues(alpha: 0.08),
      ),
      dividerTheme: const DividerThemeData(
        color: _separator,
        thickness: 0.5,
        space: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 80,
        backgroundColor: _systemBackground,
        elevation: 0,
        shadowColor: Colors.transparent,
        indicatorColor: const Color(0xFFE8F1FF),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 10,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? _blue : _secondaryLabel,
            letterSpacing: 0,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? _blue
                : _secondaryLabel,
            size: 24,
          );
        }),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: _label,
        ),
        subtitleTextStyle: TextStyle(fontSize: 13, color: _secondaryLabel),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _blue,
        linearTrackColor: Color(0xFFE5E5EA),
      ),
    );
  }

  static ThemeData dark() {
    const darkLabel = Color(0xFFFFFFFF);
    const darkSecondaryLabel = Color(0xFFAEAEB2);
    const darkBackground = Color(0xFF000000);
    const darkSecondaryBackground = Color(0xFF1C1C1E);
    const darkCardBackground = Color(0xFF2C2C2E);
    const darkBlue = Color(0xFF0A84FF);
    const darkSeparator = Color(0xFF38383A);

    final scheme = ColorScheme.fromSeed(
      brightness: Brightness.dark,
      seedColor: darkBlue,
      primary: darkBlue,
      secondary: darkBlue,
      surface: darkSecondaryBackground,
      onSurface: darkLabel,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: darkBackground,
      textTheme: _textTheme(brightness: Brightness.dark),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: darkBackground,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: darkLabel,
          letterSpacing: -0.2,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: darkBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            letterSpacing: -0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkBlue,
          minimumSize: const Size.fromHeight(50),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          side: const BorderSide(color: darkBlue),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: darkBlue,
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: darkBlue,
          backgroundColor: darkBlue.withValues(alpha: 0.15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: darkCardBackground,
        side: const BorderSide(color: darkSeparator),
        labelStyle: const TextStyle(
          color: darkSecondaryLabel,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: darkCardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: darkSeparator,
        thickness: 0.5,
        space: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 80,
        backgroundColor: darkSecondaryBackground,
        elevation: 0,
        indicatorColor: darkBlue.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 10,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? darkBlue : darkSecondaryLabel,
            letterSpacing: 0,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? darkBlue
                : darkSecondaryLabel,
            size: 24,
          );
        }),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: darkLabel,
        ),
        subtitleTextStyle: TextStyle(fontSize: 13, color: darkSecondaryLabel),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: darkBlue,
        linearTrackColor: Color(0xFF3A3A3C),
      ),
    );
  }

  static TextTheme _textTheme({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;
    final primary = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1C1C1E);
    final secondary =
        isDark ? const Color(0xFFAEAEB2) : const Color(0xFF6E6E73);

    return TextTheme(
      // Large bold page title — "Home", "Tests", "Coach"
      displayLarge: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: primary,
      ),
      // Section header — "Want to Read", "Weak Sections"
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: primary,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: primary,
      ),
      titleSmall: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.1,
        height: 1.4,
        color: primary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: secondary,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),
      labelLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
    );
  }
}
