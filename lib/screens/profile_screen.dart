import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/providers.dart';
import '../core/readiness.dart';
import 'ncarb_calculator_screen.dart';
import '../core/theme/app_theme.dart';
import '../core/ui/app_chrome.dart';
import '../services/auth_service.dart';
import '../services/iap_service.dart';
import '../services/notification_service.dart';
import 'paywall_screen.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final _reminderEnabledProvider = StateProvider<bool>((ref) => false);
final _reminderTimeProvider = StateProvider<TimeOfDay>(
  (ref) => const TimeOfDay(hour: 9, minute: 0),
);

// ── Screen ───────────────────────────────────────────────────────────────────

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _iapService = IAPService();
  final _authService = AuthService();
  StreamSubscription<PurchaseDetails>? _purchaseSub;
  bool _restoring = false;
  bool _deleting = false;
  bool _verificationSending = false;
  DateTime? _examDate;

  @override
  void initState() {
    super.initState();
    _iapService.initialize();
    _loadReminderPref();
    _loadExamDate();
    _refreshEmailStatus();
    _purchaseSub = _iapService.purchaseUpdates.listen(
      _onPurchaseUpdate,
      onError: (_) {
        if (mounted) setState(() => _restoring = false);
      },
    );
  }

  /// Pulls the latest verification state so the "verify email" prompt hides
  /// once the user has confirmed (possibly on another device).
  Future<void> _refreshEmailStatus() async {
    if (!widget.firebaseReady) return;
    try {
      await _authService.reloadUser();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _resendVerification() async {
    if (_verificationSending) return;
    setState(() => _verificationSending = true);
    try {
      await _authService.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification email sent — check your inbox.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send right now. Try again later.')),
        );
      }
    } finally {
      if (mounted) setState(() => _verificationSending = false);
    }
  }

  Future<void> _loadReminderPref() async {
    final enabled = await NotificationService.isEnabled();
    final saved = await NotificationService.savedTime();
    if (mounted) {
      ref.read(_reminderEnabledProvider.notifier).state = enabled;
      ref.read(_reminderTimeProvider.notifier).state =
          TimeOfDay(hour: saved.hour, minute: saved.minute);
    }
  }

  Future<void> _loadExamDate() async {
    final box = await Hive.openBox('settings');
    final stored = box.get('examDate') as String?;
    if (stored != null && mounted) {
      setState(() => _examDate = DateTime.tryParse(stored));
    }
  }

  Future<void> _pickExamDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _examDate ?? now.add(const Duration(days: 90)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
      helpText: 'Select your exam date',
      confirmText: 'Set Date',
    );
    if (picked == null) return;
    final box = await Hive.openBox('settings');
    await box.put('examDate', picked.toIso8601String().substring(0, 10));
    if (mounted) setState(() => _examDate = picked);
  }

  Future<void> _clearExamDate() async {
    final box = await Hive.openBox('settings');
    await box.delete('examDate');
    if (mounted) setState(() => _examDate = null);
  }

  Future<void> _toggleReminder(bool value) async {
    if (value) {
      final granted = await NotificationService.requestPermission();
      if (!granted) return;
      final time = ref.read(_reminderTimeProvider);
      await NotificationService.scheduleDailyReminder(
        hour: time.hour,
        minute: time.minute,
      );
    } else {
      await NotificationService.cancel();
    }
    ref.read(_reminderEnabledProvider.notifier).state = value;
  }

  Future<void> _pickReminderTime() async {
    final current = ref.read(_reminderTimeProvider);
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      helpText: 'REMINDER TIME',
    );
    if (picked == null || !mounted) return;
    ref.read(_reminderTimeProvider.notifier).state = picked;
    if (ref.read(_reminderEnabledProvider)) {
      await NotificationService.scheduleDailyReminder(
        hour: picked.hour,
        minute: picked.minute,
      );
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Delete account?',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: const Text(
          'This permanently deletes your account and all your data — '
          'study progress, attempts, analytics, and AI coach history. '
          'This cannot be undone.\n\n'
          'If you have an active subscription, cancel it separately in your '
          'App Store or Google Play account settings.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _deleteAccount();
  }

  Future<void> _deleteAccount() async {
    if (_deleting) return;
    setState(() => _deleting = true);
    try {
      await _authService.deleteAccount();
      // Success: the auth-state listener at the app root returns the user to
      // the sign-in screen, so no explicit navigation is needed here.
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete account. Please try again.'),
          ),
        );
      }
    }
  }

  void _openPaywall() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaywallScreen(iapService: _iapService),
      ),
    );
  }

  void _onPurchaseUpdate(PurchaseDetails details) {
    if (!mounted) return;
    setState(() => _restoring = false);
    if (details.status == PurchaseStatus.restored) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchases restored successfully!')),
      );
    }
  }

  Future<void> _restorePurchases() async {
    if (_restoring) return;
    setState(() => _restoring = true);
    try {
      await _iapService.restorePurchases();
      // Results arrive via _purchaseSub / _onPurchaseUpdate.
      // If nothing is restored the stream stays silent, so reset after a delay.
      await Future<void>.delayed(const Duration(seconds: 8));
      if (mounted && _restoring) setState(() => _restoring = false);
    } catch (_) {
      if (mounted) {
        setState(() => _restoring = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Restore failed. Please try again.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    _iapService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.firebaseReady ? FirebaseAuth.instance.currentUser?.uid : null;
    final metricsAsync = ref.watch(
      dashboardMetricsProvider((uid: uid, firebaseReady: widget.firebaseReady)),
    );
    final role = ref.watch(userRoleProvider(uid)).valueOrNull ?? 'free';
    final isPremium = role == 'premium';
    final reminderEnabled = ref.watch(_reminderEnabledProvider);
    final reminderTime = ref.watch(_reminderTimeProvider);

    final user = widget.firebaseReady ? FirebaseAuth.instance.currentUser : null;
    final isGuest = user?.isAnonymous ?? false;
    final email = user?.email ?? (widget.firebaseReady ? 'Anonymous' : 'Demo mode');
    final displayName = isGuest ? 'Guest' : email;
    final initials = isGuest ? 'G' : _initials(email);
    final tt = Theme.of(context).textTheme;

    final metrics = metricsAsync.valueOrNull;
    final data = _ProfileData(
      readiness: metrics?.readinessPercent ?? 0,
      attempts: metrics?.attemptsCount ?? 0,
    );
    final loading = metricsAsync.isLoading;

    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: Stack(
        children: [
          const Positioned.fill(child: AppBackdrop()),
          SafeArea(
            child: ListView(
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
                          displayName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isGuest
                              ? 'Sign in to save your progress'
                              : isPremium
                                  ? 'Premium'
                                  : 'Free plan',
                          style: TextStyle(
                            fontSize: 13,
                            color: isPremium && !isGuest
                                ? AppTheme.yellow
                                : AppTheme.textSecondary,
                            fontWeight: isPremium && !isGuest
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Verify email prompt (email/password users only) ────
            if (widget.firebaseReady && _authService.needsEmailVerification) ...[
              _Card(
                child: Row(
                  children: [
                    const Icon(
                      Icons.mark_email_unread_outlined,
                      size: 20,
                      color: AppTheme.warning,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Verify your email',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Check your inbox to confirm your address.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _verificationSending ? null : _resendVerification,
                      child: Text(_verificationSending ? 'Sending…' : 'Resend'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

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
                          color: readinessColor(data.readiness),
                        ),
                        const SizedBox(width: 12),
                        _StatBox(
                          value: '${data.attempts}',
                          label: data.attempts == 1 ? 'Session' : 'Sessions',
                          color: AppTheme.blue,
                        ),
                        const SizedBox(width: 12),
                        _StatBox(
                          value: ref.watch(allQuestionsProvider).valueOrNull?.length.toString() ?? '—',
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
                        readinessColor(data.readiness),
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

            // ── Upgrade / Premium card ─────────────────────────────
            if (isPremium)
              _Card(
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.yellow.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        color: AppTheme.yellow,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Premium active',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Manage in Apple ID settings',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppTheme.yellow,
                      size: 20,
                    ),
                  ],
                ),
              )
            else
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
                                color: AppTheme.textSecondary.withValues(
                                  alpha: 0.8,
                                ),
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
            const SizedBox(height: 8),

            // Restore row — needed for users who reinstall or switch devices.
            Center(
              child: TextButton.icon(
                onPressed: _restoring ? null : _restorePurchases,
                icon: _restoring
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restore_rounded, size: 16),
                label: Text(_restoring ? 'Restoring…' : 'Restore Purchases'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Exam date ──────────────────────────────────────────
            _ExamDateCard(
              examDate: _examDate,
              onPick: _pickExamDate,
              onClear: _clearExamDate,
            ),
            const SizedBox(height: 16),

            // ── Tools ──────────────────────────────────────────────
            _Card(
              child: _SettingsRow(
                icon: Icons.calculate_outlined,
                label: 'NCARB Score Calculator',
                value: '',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NcarbCalculatorScreen()),
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
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('More languages coming soon.'),
                        duration: Duration(seconds: 2),
                      ),
                    ),
                  ),
                  _Divider(),
                  if (!kIsWeb)
                    _ReminderRow(
                      enabled: reminderEnabled,
                      time: reminderTime,
                      onChanged: _toggleReminder,
                      onTimeTap: _pickReminderTime,
                    ),
                  if (kIsWeb)
                    const _SettingsRow(
                      icon: Icons.notifications_off_outlined,
                      label: 'Daily reminder',
                      value: 'Mobile only',
                      onTap: null,
                    ),
                  _Divider(),
                  const _SettingsRow(
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
                  const _SettingsRow(
                    icon: Icons.info_outline_rounded,
                    label: 'Version',
                    value: kAppVersion,
                    onTap: null,
                  ),
                  _Divider(),
                  _SettingsRow(
                    icon: Icons.shield_outlined,
                    label: 'Privacy Policy',
                    value: '',
                    onTap: () => launchUrl(
                      Uri.parse('https://vito-bc.github.io/ARE-Coach/privacy-policy.html'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  _Divider(),
                  _SettingsRow(
                    icon: Icons.description_outlined,
                    label: 'Terms of Service',
                    value: '',
                    onTap: () => launchUrl(
                      Uri.parse('https://vito-bc.github.io/ARE-Coach/terms-and-conditions.html'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Guest: invite to sign in (signing out of the anonymous
            //     session returns them to the login screen) ────────────
            if (widget.firebaseReady && isGuest)
              FilledButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('Sign In'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.yellow,
                  foregroundColor: AppTheme.navy,
                  minimumSize: const Size.fromHeight(50),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              )

            // ── Signed-in account: sign out + delete ───────────────
            else if (widget.firebaseReady) ...[
              OutlinedButton.icon(
                onPressed: _deleting ? null : _signOut,
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Sign Out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  side: BorderSide(
                    color: AppTheme.error.withValues(alpha: 0.4),
                  ),
                ),
              ),

              // Delete account (App Store Guideline 5.1.1(v))
              Center(
                child: TextButton.icon(
                  onPressed: _deleting ? null : _confirmDeleteAccount,
                  icon: _deleting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline_rounded, size: 16),
                  label: Text(_deleting ? 'Deleting…' : 'Delete Account'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],

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
            ),
          ),
        ],
      ),
    );
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
  const _ReminderRow({
    required this.enabled,
    required this.time,
    required this.onChanged,
    required this.onTimeTap,
  });
  final bool enabled;
  final TimeOfDay time;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTimeTap;

  String _fmt(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $period';
  }

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
          if (enabled)
            GestureDetector(
              onTap: onTimeTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.yellow.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.yellow.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  _fmt(time),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.yellow,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
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

// ── Exam Date Card ────────────────────────────────────────────────────────────

class _ExamDateCard extends StatelessWidget {
  const _ExamDateCard({
    required this.examDate,
    required this.onPick,
    required this.onClear,
  });

  final DateTime? examDate;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final daysLeft = examDate?.difference(DateTime.now()).inDays;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'EXAM DATE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          if (examDate == null)
            GestureDetector(
              onTap: onPick,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.yellow.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.yellow.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.event_rounded, color: AppTheme.yellow, size: 24),
                    SizedBox(height: 6),
                    Text(
                      'Set target exam date',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.yellow,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Get a personalized daily study plan',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.yellow.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.event_rounded,
                    color: AppTheme.yellow,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDate(examDate!),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        daysLeft != null && daysLeft > 0
                            ? '$daysLeft ${daysLeft == 1 ? 'day' : 'days'} until exam'
                            : 'Exam date reached',
                        style: TextStyle(
                          fontSize: 12,
                          color: daysLeft != null && daysLeft <= 14
                              ? AppTheme.warning
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onPick,
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  color: AppTheme.textSecondary,
                  tooltip: 'Change date',
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.surfaceElevated,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  color: AppTheme.textSecondary,
                  tooltip: 'Clear date',
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.surfaceElevated,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
