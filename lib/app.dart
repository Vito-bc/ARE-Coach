import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/splash_screen.dart';

class ArchiEdApp extends StatefulWidget {
  const ArchiEdApp({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<ArchiEdApp> createState() => _ArchiEdAppState();
}

class _ArchiEdAppState extends State<ArchiEdApp> {
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
            ),
      },
      initialRoute: SplashScreen.routeName,
    );
  }
}
