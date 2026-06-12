import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/theme/app_theme.dart';
import 'services/notification_service.dart';
import 'firebase_options.dart';
import 'screens/auth/login_screen.dart';
import 'screens/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await NotificationService.init();

  var firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    try {
      const recaptchaKey = String.fromEnvironment('RECAPTCHA_SITE_KEY');
      if (!kIsWeb || recaptchaKey.isNotEmpty) {
        await FirebaseAppCheck.instance.activate(
          androidProvider: AndroidProvider.playIntegrity,
          appleProvider: AppleProvider.deviceCheck,
          webProvider: recaptchaKey.isNotEmpty
              ? ReCaptchaV3Provider(recaptchaKey)
              : ReCaptchaV3Provider(''),
        );
      }
    } catch (_) {
      // App Check can be enabled per environment; keep app runnable in dev.
    }
    firebaseReady = true;

    if (!kIsWeb) {
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }
  } catch (_) {
    // Firebase may be configured later; app still runs with local seed data.
  }

  runApp(ProviderScope(child: ArchiEdBootstrap(firebaseReady: firebaseReady)));
}

class ArchiEdBootstrap extends StatefulWidget {
  const ArchiEdBootstrap({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<ArchiEdBootstrap> createState() => _ArchiEdBootstrapState();
}

class _ArchiEdBootstrapState extends State<ArchiEdBootstrap> {
  bool _loading = true;
  bool _onboarded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final box = await Hive.openBox('settings');
    final onboarded = box.get('onboarded', defaultValue: false) as bool;
    if (!mounted) return;
    setState(() {
      _onboarded = onboarded;
      _loading = false;
    });
  }

  Future<void> _completeOnboarding() async {
    final box = await Hive.openBox('settings');
    await box.put('onboarded', true);
    if (mounted) setState(() => _onboarded = true);
  }

  Widget _wait() => const MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ARE Coach',
        home: Scaffold(
          backgroundColor: AppTheme.navy,
          body: Center(child: CircularProgressIndicator(color: AppTheme.yellow)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return _wait();

    // 1. First launch → onboarding before anything else.
    if (!_onboarded) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ARE Coach',
        theme: AppTheme.dark(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: OnboardingScreen(onDone: _completeOnboarding),
      );
    }

    // 2. No Firebase configured → run the app in demo mode (no auth).
    if (!widget.firebaseReady) {
      return const ArchiEdApp(firebaseReady: false);
    }

    // 3. Auth gate: signed out → Login; signed in (incl. guest/anonymous) → app.
    //    Email, Apple, registration and "continue as guest" all change the auth
    //    state, which this StreamBuilder reacts to. Sign-out returns to Login.
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _wait();
        }
        if (snapshot.data == null) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'ARE Coach',
            theme: AppTheme.dark(),
            darkTheme: AppTheme.dark(),
            themeMode: ThemeMode.dark,
            home: const LoginScreen(firebaseReady: true),
          );
        }
        return const ArchiEdApp(firebaseReady: true);
      },
    );
  }
}
