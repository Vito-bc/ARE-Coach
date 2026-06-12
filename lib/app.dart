import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/home_shell.dart';

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
      title: 'ARE Coach',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routes: {
        HomeShell.routeName: (_) => HomeShell(
              firebaseReady: widget.firebaseReady,
            ),
      },
      initialRoute: HomeShell.routeName,
    );
  }
}
