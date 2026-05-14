import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/providers.dart';
import '../core/readiness.dart';
import '../core/theme/app_theme.dart';
import '../core/ui/app_chrome.dart';
import '../models/flashcard.dart';
import '../services/flashcard_repository.dart';
import '../services/progress_repository.dart';
import 'attempt_history_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  static const _emptyMetrics = DashboardMetrics(
    readinessPercent: 0,
    attemptsCount: 0,
    weakSections: [],
    sectionTrends: [],
  );

  int _streak = 0;
  List<_DivisionProgress> _divisionProgress = [];

  @override
  void initState() {
    super.initState();
    _loadStreak();
    _loadFlashcardProgress();
  }

  Future<void> _loadStreak() async {
    final box = await Hive.openBox('settings');
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastDate = box.get('lastStudyDate') as String?;
    final stored = box.get('studyStreak', defaultValue: 0) as int;

    int streak;
    if (lastDate == null) {
      streak = 1;
    } else if (lastDate == today) {
      streak = stored;
    } else {
      final last = DateTime.tryParse(lastDate);
      final diff = last != null ? DateTime.now().difference(last).inDays : 999;
      streak = diff == 1 ? stored + 1 : 1;
    }

    await box.put('studyStreak', streak);
    await box.put('lastStudyDate', today);
    if (mounted) setState(() => _streak = streak);
  }

  Future<void> _loadFlashcardProgress() async {
    final repo = FlashcardRepository();
    final cards = await repo.loadAll();
    final statuses = await repo.allStatuses();

    const divs = [
      ('PcM', 'Practice Management'),
      ('PjM', 'Project Management'),
      ('PA', 'Programming & Analysis'),
      ('PPD', 'Project Planning & Design'),
      ('PDD', 'Project Docs & Delivery'),
      ('CE', 'Construction & Evaluation'),
      ('NYC', 'NYC Building Codes'),
    ];

    final progress = divs.map((d) {
      final sectionCards = cards.where((c) => c.section == d.$2).toList();
      final mastered =
          sectionCards.where((c) => statuses[c.id] == CardStatus.mastered).length;
      return _DivisionProgress(abbr: d.$1, mastered: mastered, total: sectionCards.length);
    }).toList();

    if (mounted) setState(() => _divisionProgress = progress);
  }

  @override
  Widget build(BuildContext context) {
    final uid =
        widget.firebaseReady ? FirebaseAuth.instance.currentUser?.uid : null;
    final metricsAsync = ref.watch(
      dashboardMetricsProvider((uid: uid, firebaseReady: widget.firebaseReady)),
    );

    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;
    final loading = metricsAsync.isLoading;
    final hasError = metricsAsync.hasError;
    final metrics = metricsAsync.valueOrNull ?? _emptyMetrics;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/bg_hero.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.42),
                    const Color(0xFF0D1117).withValues(alpha: 0.72),
                    const Color(0xFF0D1117).withValues(alpha: 0.94),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      if (hasError)
                        _ErrorBanner(
                          onRetry: () => ref.invalidate(dashboardMetricsProvider),
                        ),
                      Expanded(
                        child: CustomScrollView(
                          slivers: [
                            // Header with streak chip
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Home', style: tt.displayLarge),
                                          const SizedBox(height: 4),
                                          Text(
                                            widget.firebaseReady
                                                ? 'NYC ARE Prep'
                                                : 'Demo mode',
                                            style: tt.bodyMedium,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_streak > 0) _StreakChip(streak: _streak),
                                  ],
                                ),
                              ),
                            ),

                            // Readiness card
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                                child: _ReadinessCard(
                                  percent: metrics.readinessPercent,
                                  attempts: metrics.attemptsCount,
                                  isDark: isDark,
                                  accent: accent,
                                  tt: tt,
                                ),
                              ),
                            ),

                            const SliverToBoxAdapter(child: SizedBox(height: 24)),

                            // Weak sections
                            if (metrics.weakSections.isNotEmpty) ...[
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                                  child: AppSection(
                                    title: 'Focus Areas',
                                    trailing: TextButton(
                                      onPressed: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => AttemptHistoryScreen(
                                            firebaseReady: widget.firebaseReady,
                                          ),
                                        ),
                                      ),
                                      child: const Text('See All'),
                                    ),
                                    child: Column(
                                      children: [
                                        ...metrics.weakSections.asMap().entries.map(
                                          (e) => _WeakRow(
                                            section: e.value.section,
                                            accuracy: e.value.accuracy,
                                            showDivider:
                                                e.key < metrics.weakSections.length - 1,
                                            isDark: isDark,
                                            accent: accent,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SliverToBoxAdapter(child: SizedBox(height: 24)),
                            ],

                            // Section trends
                            if (metrics.sectionTrends.isNotEmpty) ...[
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                                  child: AppSection(
                                    title: 'Section Trends',
                                    child: Column(
                                      children: [
                                        ...metrics.sectionTrends.asMap().entries.map(
                                          (e) => _TrendRow(
                                            metric: e.value,
                                            showDivider:
                                                e.key < metrics.sectionTrends.length - 1,
                                            isDark: isDark,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SliverToBoxAdapter(child: SizedBox(height: 24)),
                            ],

                            // Empty state
                            if (metrics.weakSections.isEmpty &&
                                metrics.sectionTrends.isEmpty)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                                  child: AppGlassCard(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.quiz_outlined,
                                          size: 40,
                                          color: accent.withValues(alpha: 0.6),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Take your first test',
                                          style: tt.titleSmall,
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Complete a practice session to unlock your readiness analytics.',
                                          style: tt.bodyMedium,
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                            // Flashcard progress
                            if (_divisionProgress.isNotEmpty) ...[
                              const SliverToBoxAdapter(child: SizedBox(height: 24)),
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                                  child: AppSection(
                                    title: 'Flashcard Progress',
                                    child: Column(
                                      children: _divisionProgress
                                          .asMap()
                                          .entries
                                          .map(
                                            (e) => _FlashcardDivisionRow(
                                              progress: e.value,
                                              showDivider:
                                                  e.key < _divisionProgress.length - 1,
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ),
                              ),
                            ],

                            const SliverToBoxAdapter(child: SizedBox(height: 32)),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────────

class _DivisionProgress {
  const _DivisionProgress({
    required this.abbr,
    required this.mastered,
    required this.total,
  });

  final String abbr;
  final int mastered;
  final int total;

  double get ratio => total == 0 ? 0.0 : mastered / total;
}

// ── Streak chip ───────────────────────────────────────────────────────────────

class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final color = streak >= 3 ? AppTheme.yellow : AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_rounded, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            '$streak day${streak == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

// ── Flashcard division row ────────────────────────────────────────────────────

class _FlashcardDivisionRow extends StatelessWidget {
  const _FlashcardDivisionRow({
    required this.progress,
    required this.showDivider,
  });

  final _DivisionProgress progress;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final isDone = progress.mastered == progress.total && progress.total > 0;
    final hasStarted = progress.mastered > 0;
    final barColor = isDone
        ? AppTheme.success
        : hasStarted
            ? AppTheme.yellow
            : AppTheme.textSecondary;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.yellow.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      progress.abbr,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.yellow,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${progress.mastered} / ${progress.total}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: barColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress.ratio,
                  minHeight: 3,
                  backgroundColor: AppTheme.separator,
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(
            height: 0,
            indent: 16,
            color: AppTheme.separator,
            thickness: 0.5,
          ),
      ],
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF3D0000),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 16, color: Colors.redAccent),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Could not load your data. Check your connection.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Retry', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ── Readiness card ────────────────────────────────────────────────────────────

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({
    required this.percent,
    required this.attempts,
    required this.isDark,
    required this.accent,
    required this.tt,
  });

  final int percent;
  final int attempts;
  final bool isDark;
  final Color accent;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Readiness Score', style: tt.titleSmall),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: (percent / 100).clamp(0.0, 1.0),
                      strokeWidth: 8,
                      strokeCap: StrokeCap.round,
                      backgroundColor: isDark
                          ? const Color(0xFF3A3A3C)
                          : const Color(0xFFE5E5EA),
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                    Center(
                      child: Text(
                        '$percent%',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: accent,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      readinessLabel(percent),
                      style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$attempts ${attempts == 1 ? 'session' : 'sessions'} completed',
                      style: tt.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (percent / 100).clamp(0.0, 1.0),
              minHeight: 6,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
              backgroundColor:
                  isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Weak section row ──────────────────────────────────────────────────────────

class _WeakRow extends StatelessWidget {
  const _WeakRow({
    required this.section,
    required this.accuracy,
    required this.showDivider,
    required this.isDark,
    required this.accent,
  });

  final String section;
  final int accuracy;
  final bool showDivider;
  final bool isDark;
  final Color accent;

  Color get _barColor {
    if (accuracy < 40) return const Color(0xFFFF3B30);
    if (accuracy < 60) return const Color(0xFFFF9F0A);
    return const Color(0xFF34C759);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(section, style: tt.bodyLarge)),
                  Text(
                    '$accuracy%',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _barColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: accuracy / 100,
                  minHeight: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(_barColor),
                  backgroundColor:
                      isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 0,
            indent: 16,
            color: isDark ? const Color(0xFF38383A) : const Color(0xFFC6C6C8),
            thickness: 0.5,
          ),
      ],
    );
  }
}

// ── Trend row ─────────────────────────────────────────────────────────────────

class _TrendRow extends StatelessWidget {
  const _TrendRow({
    required this.metric,
    required this.showDivider,
    required this.isDark,
  });

  final SectionTrendMetric metric;
  final bool showDivider;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isUp = metric.delta >= 0;
    final trendColor = isUp ? const Color(0xFF34C759) : const Color(0xFFFF3B30);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Expanded(child: Text(metric.section, style: tt.bodyLarge)),
              Text(
                '${metric.currentAccuracy}%',
                style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              Icon(
                isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 18,
                color: trendColor,
              ),
              Text(
                isUp ? '+${metric.delta}' : '${metric.delta}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: trendColor,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 0,
            indent: 16,
            color: isDark ? const Color(0xFF38383A) : const Color(0xFFC6C6C8),
            thickness: 0.5,
          ),
      ],
    );
  }
}
