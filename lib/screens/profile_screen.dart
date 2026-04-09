import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../core/theme/app_theme.dart';
import '../services/iap_service.dart';
import '../services/notification_service.dart';
import '../services/progress_repository.dart';
import 'paywall_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _progressRepository = ProgressRepository();
  final _iapService = IAPService();

  late final Future<_ProfileData> _dataFuture;
  bool _reminderEnabled = false;

  @override
  void initState() {
    super.initState();
    _iapService.initialize();
    _dataFuture = _loadData();
    _loadReminderPref();
  }

  Future<void> _loadReminderPref() async {
    final enabled = await NotificationService.isEnabled();
    if (mounted) setState(() => _reminderEnabled = enabled);
  }

  Future<void> _toggleReminder(bool value) async {
    if (value) {
      final granted = await NotificationService.requestPermission();
      if (!granted) return;
      await NotificationService.scheduleDailyReminder(hour: 9, minute: 0);
    } else {
      await NotificationService.cancel();
    }
    if (mounted) setState(() => _reminderEnabled = value);
  }

  Future<_ProfileData> _loadData() async {
    if (!widget.firebaseReady) {
      return const _ProfileData(readiness: 42, attempts: 3);
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const _ProfileData(readiness: 0, attempts: 0);

    try {
      final metrics = await _progressRepository
          .fetchDashboardMetrics(uid: uid)
          .timeout(const Duration(seconds: 4));
      return _ProfileData(
        readiness: metrics.readinessPercent,
        attempts: metrics.attemptsCount,
      );
    } catch (_) {
      return const _ProfileData(readiness: 0, attempts: 0);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  void _openPaywall() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaywallScreen(iapService: _iapService),
      ),
    );
  }

  @override
  void dispose() {
    _iapService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.firebaseReady ? FirebaseAuth.instance.currentUser : null;
    final email = user?.email ?? (widget.firebaseReady ? 'Anonymous' : 'Demo mode');
    final initials = _initials(email);
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: SafeArea(
        child: FutureBuilder<_ProfileData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            final data = snapshot.data ?? const _ProfileData(readiness: 0, attempts: 0);
            final loading = snapshot.connectionState != ConnectionState.done;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              children: [
                // ── Header ─────────────────────────────────────────────
                Text('Profile', style: tt.displayLarge),
                const SizedBox(height: 20),

                // ── User card ──────────────────────────────────────────
                _Card(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppTheme.yellow.withValues(alpha: 0.15),
                        child: Text(
                          initials,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.yellow,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              email,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Free plan',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Readiness stats ────────────────────────────────────
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'YOUR PROGRESS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (loading)
                        const Center(
                          child: SizedBox(
                            height: 40,
                            child: CircularProgressIndicator(
                              color: AppTheme.yellow,
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      else
                        Row(
                          children: [
                            _StatBox(
                              value: '${data.readiness}%',
                              label: 'Readiness',
                              color: _readinessColor(data.readiness),
                            ),
                            const SizedBox(width: 12),
                            _StatBox(
                              value: '${data.attempts}',
                              label: data.attempts == 1 ? 'Session' : 'Sessions',
                              color: AppTheme.blue,
                            ),
                            const SizedBox(width: 12),
                            _StatBox(
                              value: '213',
                              label: 'Questions',
                              color: AppTheme.yellow,
                            ),
                          ],
                        ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: (data.readiness / 100).clamp(0.0, 1.0),
                          minHeight: 6,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _readinessColor(data.readiness),
                          ),
                          backgroundColor: const Color(0xFF21262D),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        data.readiness >= 70
                            ? 'On track for the exam'
                            : data.readiness >= 40
                                ? 'Keep practicing — you\'re building momentum'
                                : 'Complete tests to build your readiness score',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Upgrade card ───────────────────────────────────────
                GestureDetector(
                  onTap: _openPaywall,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1A2744), Color(0xFF1C1004)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: AppTheme.yellow.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.yellow.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.bolt_rounded,
                            color: AppTheme.yellow,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Upgrade to Premium',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Unlimited coach · all divisions · voice mode',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppTheme.yellow,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Settings / Info ────────────────────────────────────
                _Card(
                  child: Column(
                    children: [
                      _SettingsRow(
                        icon: Icons.language_outlined,
                        label: 'Language',
                        value: 'English',
                        onTap: null,
                      ),
                      _Divider(),
                      if (!kIsWeb)
                        _ReminderRow(
                          enabled: _reminderEnabled,
                          onChanged: _toggleReminder,
                        ),
                      if (kIsWeb)
                        const _SettingsRow(
                          icon: Icons.notifications_off_outlined,
                          label: 'Daily reminder',
                          value: 'Mobile only',
                          onTap: null,
                        ),
                      _Divider(),
                      _SettingsRow(
                        icon: Icons.download_outlined,
                        label: 'Offline cache',
                        value: 'Enabled',
                        onTap: null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── About ──────────────────────────────────────────────
                _Card(
                  child: Column(
                    children: [
                      _SettingsRow(
                        icon: Icons.info_outline_rounded,
                        label: 'Version',
                        value: '1.0.0',
                        onTap: null,
                      ),
                      _Divider(),
                      _SettingsRow(
                        icon: Icons.shield_outlined,
                        label: 'Privacy Policy',
                        value: '',
                        onTap: () {},
                      ),
                      _Divider(),
                      _SettingsRow(
                        icon: Icons.description_outlined,
                        label: 'Terms of Service',
                        value: '',
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Sign out ───────────────────────────────────────────
                if (widget.firebaseReady)
                  OutlinedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Sign Out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      side: BorderSide(
                        color: AppTheme.error.withValues(alpha: 0.4),
                      ),
                    ),
                  ),

                const SizedBox(height: 12),
                const Text(
                  'Questions are AI-assisted study aids. Verify with official NCARB materials.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Color _readinessColor(int percent) {
    if (percent >= 70) return AppTheme.success;
    if (percent >= 40) return AppTheme.warning;
    return AppTheme.error;
  }

  String _initials(String email) {
    if (email == 'Anonymous' || email == 'Demo mode') return 'A';
    final parts = email.split('@').first.split('.');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return email.isNotEmpty ? email[0].toUpperCase() : 'U';
  }
}

// ── Local widgets ────────────────────────────────────────────────────────────

class _ProfileData {
  const _ProfileData({required this.readiness, required this.attempts});
  final int readiness;
  final int attempts;
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.separator, width: 0.5),
      ),
      child: child,
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.value,
    required this.label,
    required this.color,
  });
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            if (value.isNotEmpty)
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
            if (onTap != null)
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppTheme.textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.enabled, required this.onChanged});
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.notifications_outlined,
              size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Daily reminder',
              style: TextStyle(fontSize: 15, color: AppTheme.textPrimary),
            ),
          ),
          Switch(
            value: enabled,
            onChanged: onChanged,
            activeThumbColor: AppTheme.yellow,
            activeTrackColor: AppTheme.yellow.withValues(alpha: 0.3),
            inactiveThumbColor: AppTheme.textSecondary,
            inactiveTrackColor: AppTheme.surfaceElevated,
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Divider(height: 0, color: AppTheme.separator, thickness: 0.5);
  }
}
