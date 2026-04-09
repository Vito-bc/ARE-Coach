import 'package:flutter/material.dart';

import 'coach_screen.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import 'tests_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.firebaseReady});

  static const routeName = '/home';
  final bool firebaseReady;

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
      ProfileScreen(firebaseReady: widget.firebaseReady),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: screens[_index],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF161B22),
          border: Border(
            top: BorderSide(color: Color(0xFF21262D), width: 0.5),
          ),
        ),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.transparent,
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.book_outlined),
              selectedIcon: Icon(Icons.book_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.layers_outlined),
              selectedIcon: Icon(Icons.layers_rounded),
              label: 'Tests',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Coach',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
