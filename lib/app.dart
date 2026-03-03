import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/splash_screen.dart';

class ArchitectulaApp extends StatelessWidget {
  const ArchitectulaApp({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Architectula Education',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routes: {
        SplashScreen.routeName: (_) => const SplashScreen(),
        OnboardingScreen.routeName: (_) => const OnboardingScreen(),
        HomeShell.routeName: (_) => HomeShell(firebaseReady: firebaseReady),
      },
      initialRoute: SplashScreen.routeName,
    );
  }
}
