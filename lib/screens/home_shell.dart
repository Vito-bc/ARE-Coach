import 'package:flutter/material.dart';

import 'coach_screen.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import 'tests_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.firebaseReady,
    required this.isDarkMode,
    required this.onThemeChanged,
  });

  static const routeName = '/home';
  final bool firebaseReady;
  final bool isDarkMode;
  final ValueChanged<bool> onThemeChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(firebaseReady: widget.firebaseReady),
      TestsScreen(firebaseReady: widget.firebaseReady),
      const CoachScreen(),
      ProfileScreen(
        isDarkMode: widget.isDarkMode,
        onThemeChanged: widget.onThemeChanged,
      ),
    ];

    return Scaffold(
      body: screens[_index],
      bottomNavigationBar: NavigationBar(
        backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
        indicatorColor: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.22),
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz_rounded),
            label: 'Tests',
          ),
          NavigationDestination(
            icon: Icon(Icons.mic_none_rounded),
            selectedIcon: Icon(Icons.mic_rounded),
            label: 'Coach',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
