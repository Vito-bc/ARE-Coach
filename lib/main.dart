import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  var firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
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
    return ArchitectulaApp(firebaseReady: widget.firebaseReady);
  }
}
