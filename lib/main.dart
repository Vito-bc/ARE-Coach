import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'screens/auth/login_screen.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  var firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    try {
      await FirebaseAppCheck.instance.activate(
        androidProvider: AndroidProvider.playIntegrity,
        appleProvider: AppleProvider.deviceCheck,
        webProvider: ReCaptchaV3Provider(
          const String.fromEnvironment('RECAPTCHA_SITE_KEY'),
        ),
      );
    } catch (_) {
      // App Check can be enabled per environment; keep app runnable in dev.
    }
    firebaseReady = true;
  } catch (_) {
    // Firebase may be configured later; app still runs with local seed data.
  }

  runApp(ArchitectulaBootstrap(firebaseReady: firebaseReady));
}

class ArchitectulaBootstrap extends StatefulWidget {
  const ArchitectulaBootstrap({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<ArchitectulaBootstrap> createState() => _ArchitectulaBootstrapState();
}

class _ArchitectulaBootstrapState extends State<ArchitectulaBootstrap> {
  bool _initializing = true;
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final box = await Hive.openBox('settings');
    final isDark = box.get('darkMode', defaultValue: false) as bool;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;

    if (widget.firebaseReady) {
      try {
        final authService = AuthService();
        await authService.ensureSignedIn();
      } catch (_) {
        // If auth is not enabled yet, keep app in demo/fallback mode.
      }
    }
    if (!mounted) return;
    setState(() => _initializing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (!widget.firebaseReady) {
      return ArchitectulaApp(
        firebaseReady: false,
        initialThemeMode: _themeMode,
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const MaterialApp(
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: _themeMode,
            home: LoginScreen(firebaseReady: widget.firebaseReady),
          );
        }
        return ArchitectulaApp(
          firebaseReady: widget.firebaseReady,
          initialThemeMode: _themeMode,
        );
      },
    );
  }
}
