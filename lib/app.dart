import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/theme/app_theme.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/splash_screen.dart';

class ArchiEdApp extends StatefulWidget {
  const ArchiEdApp({
    super.key,
    required this.firebaseReady,
    required this.initialThemeMode,
  });

  final bool firebaseReady;
  final ThemeMode initialThemeMode;

  @override
  State<ArchiEdApp> createState() => _ArchiEdAppState();
}

class _ArchiEdAppState extends State<ArchiEdApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
  }

  Future<void> _setDarkMode(bool enabled) async {
    setState(() => _themeMode = enabled ? ThemeMode.dark : ThemeMode.light);
    final box = Hive.box('settings');
    await box.put('darkMode', enabled);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ArchiEd',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routes: {
        SplashScreen.routeName: (_) => const SplashScreen(),
        OnboardingScreen.routeName: (_) => const OnboardingScreen(),
        HomeShell.routeName: (_) => HomeShell(
              firebaseReady: widget.firebaseReady,
              isDarkMode: _themeMode == ThemeMode.dark,
              onThemeChanged: _setDarkMode,
            ),
      },
      initialRoute: SplashScreen.routeName,
    );
  }
}
