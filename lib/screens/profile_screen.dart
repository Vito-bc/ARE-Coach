import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Profile',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Readiness: 42%'),
                  SizedBox(height: 8),
                  Text('Daily limit: 10 free questions used 6/10'),
                  SizedBox(height: 8),
                  Text('AI messages today: 12/50'),
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
