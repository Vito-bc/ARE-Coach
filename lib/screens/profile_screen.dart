import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.isDarkMode,
    required this.onThemeChanged,
  });

  final bool isDarkMode;
  final ValueChanged<bool> onThemeChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Profile',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Readiness: 42%'),
                  const SizedBox(height: 8),
                  const Text('Daily limit: 10 free questions used 6/10'),
                  const SizedBox(height: 8),
                  const Text('AI messages today: 12/50'),
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: isDark
                            ? [
                                const Color(0xFF0B1326),
                                const Color(0xFF0F1B3D),
                              ]
                            : [
                                const Color(0xFFEAF6F6),
                                const Color(0xFFF8F3FF),
                              ],
                      ),
                    ),
                    child: SwitchListTile(
                      title: const Text(
                        'Day / Night Theme',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(isDarkMode ? 'Night mode active' : 'Day mode active'),
                      value: isDarkMode,
                      onChanged: onThemeChanged,
                      secondary: Icon(
                        isDarkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Subscription',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text('Free tier active'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Upgrade to Premium \$7.99/mo'),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('Buy 100 extra coach tokens (\$2.99)'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Settings'),
                  SizedBox(height: 8),
                  Text('Language: English / Russian'),
                  Text('Offline cache: enabled'),
                  Text('Notifications: daily progress bot'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
