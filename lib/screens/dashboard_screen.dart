import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/providers.dart';
import '../core/readiness.dart';
import '../core/study_streak.dart';
import '../core/theme/app_theme.dart';
import '../core/ui/app_chrome.dart';
import '../core/ui/app_tappable.dart';
import '../models/flashcard.dart';
import '../services/flashcard_repository.dart';
import '../services/progress_repository.dart';
import 'attempt_history_screen.dart';
import 'insights_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({
    super.key,
    required this.firebaseReady,
    this.onSelectTab,
  });

  final bool firebaseReady;

  /// Lets the dashboard switch the bottom-nav tab (e.g. a "Start practice"
  /// CTA jumps to Tests, division tiles jump to Cards).
  final void Function(int index)? onSelectTab;

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
  DateTime? _examDate;

  @override
  void initState() {
    super.initState();
    _loadStreak();
    _loadFlashcardProgress();
    _loadExamDate();
  }

  Future<void> _loadExamDate() async {
    final box = await Hive.openBox('settings');
    final stored = box.get('examDate') as String?;
    if (stored != null && mounted) {
      setState(() => _examDate = DateTime.tryParse(stored));
    }
  }

  Future<void> _loadStreak() async {
    final streak = await StudyStreak.read();
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

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  /// Merges the two overlapping accuracy views (weakest-3 + per-section trends)
  /// into a single list, worst-first, so "what to focus on" surfaces at the top
  /// without showing the same divisions twice.
  List<_SectionPerf> _buildSectionPerf(DashboardMetrics m) {
    final List<_SectionPerf> list;
    if (m.sectionTrends.isNotEmpty) {
      list = m.sectionTrends
          .map((t) => _SectionPerf(t.section, t.currentAccuracy, t.delta))
          .toList();
    } else {
      list = m.weakSections
          .map((w) => _SectionPerf(w.section, w.accuracy, null))
          .toList();
    }
    list.sort((a, b) => a.accuracy.compareTo(b.accuracy));
    return list;
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
    final sectionPerf = _buildSectionPerf(metrics);

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
                  // Stronger scrim so the hero reads as a subtle top accent
                  // and the data below sits on near-solid navy for legibility.
                  stops: const [0.0, 0.28, 0.5],
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    const Color(0xFF0D1117).withValues(alpha: 0.88),
                    const Color(0xFF0D1117),
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
                                          Text(_greeting(), style: tt.displayLarge),
                                          const SizedBox(height: 4),
                                          Text(
                                            widget.firebaseReady
                                                ? 'Ready to study?'
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
                                  isDemo: !widget.firebaseReady,
                                ),
                              ),
                            ),

                            const SliverToBoxAdapter(child: SizedBox(height: 16)),

                            // Primary CTA — jump straight into practice
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                                child: _StartPracticeCard(
                                  onTap: () => widget.onSelectTab?.call(1),
                                ),
                              ),
                            ),

                            const SliverToBoxAdapter(child: SizedBox(height: 24)),

                            // Performance by section — one consolidated view
                            // (worst-first), replacing the old duplicated
                            // "Focus Areas" + "Section Trends" lists.
                            if (sectionPerf.isNotEmpty) ...[
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                                  child: AppSection(
                                    title: 'Performance by Section',
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
                                        for (var i = 0;
                                            i < sectionPerf.length;
                                            i++)
                                          _SectionRow(
                                            perf: sectionPerf[i],
                                            showDivider:
                                                i < sectionPerf.length - 1,
                                            isDark: isDark,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SliverToBoxAdapter(child: SizedBox(height: 16)),
                              // Insights entry
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                                  child: _InsightsEntryRow(
                                    firebaseReady: widget.firebaseReady,
                                  ),
                                ),
                              ),
                              const SliverToBoxAdapter(child: SizedBox(height: 8)),
                            ],

                            // Empty state
                            if (sectionPerf.isEmpty)
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

                            // Flashcard progress — tappable division grid
                            if (_divisionProgress.isNotEmpty) ...[
                              const SliverToBoxAdapter(child: SizedBox(height: 24)),
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
                                        child: Text(
                                          'FLASHCARD PROGRESS',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.3,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ),
                                      LayoutBuilder(
                                        builder: (context, c) {
                                          const gap = 10.0;
                                          final w = (c.maxWidth - gap) / 2;
                                          return Wrap(
                                            spacing: gap,
                                            runSpacing: gap,
                                            children: _divisionProgress
                                                .map(
                                                  (p) => _DivisionTile(
                                                    progress: p,
                                                    width: w,
                                                    onTap: () =>
                                                        widget.onSelectTab?.call(2),
                                                  ),
                                                )
                                                .toList(),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],

                            // Study plan
                            if (_examDate != null) ...[
                              const SliverToBoxAdapter(child: SizedBox(height: 24)),
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                                  child: _StudyPlanCard(
                                    examDate: _examDate!,
                                    divisionProgress: _divisionProgress,
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

class _StartPracticeCard extends StatelessWidget {
  const _StartPracticeCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      accentBorder: AppTheme.yellow.withValues(alpha: 0.35),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.yellow.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.bolt_rounded, color: AppTheme.yellow, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Start a practice test',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Quick quiz, by division, or full mock exam',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppTheme.yellow),
        ],
      ),
    );
  }
}

class _DivisionTile extends StatelessWidget {
  const _DivisionTile({
    required this.progress,
    required this.width,
    required this.onTap,
  });

  final _DivisionProgress progress;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDone = progress.mastered == progress.total && progress.total > 0;
    final hasStarted = progress.mastered > 0;
    final color = isDone
        ? AppTheme.success
        : hasStarted
            ? AppTheme.yellow
            : AppTheme.textSecondary;

    return AppTappable(
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDone
                ? AppTheme.success.withValues(alpha: 0.3)
                : AppTheme.separator,
            width: isDone ? 1 : 0.5,
          ),
        ),
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
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.yellow,
                    ),
                  ),
                ),
                const Spacer(),
                if (isDone)
                  const Icon(Icons.check_circle_rounded,
                      size: 14, color: AppTheme.success),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${progress.mastered} / ${progress.total}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'cards mastered',
              style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress.ratio,
                minHeight: 3,
                backgroundColor: AppTheme.separator,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
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
    this.isDemo = false,
  });

  final int percent;
  final int attempts;
  final bool isDark;
  final Color accent;
  final TextTheme tt;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Readiness Score', style: tt.titleSmall),
              if (isDemo) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.textSecondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'SAMPLE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
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
                        // No sessions yet -> no readiness claim at all.
                        attempts > 0 ? '$percent%' : '—',
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
                      attempts > 0
                          ? readinessLabel(percent)
                          : 'Not enough data yet',
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
        ],
      ),
    );
  }
}

// ── Performance-by-section row ───────────────────────────────────────────────

/// Unified per-section accuracy entry. [delta] is null when there is no trend
/// data (e.g. only the weakest-sections fallback was available).
class _SectionPerf {
  const _SectionPerf(this.section, this.accuracy, this.delta);

  final String section;
  final int accuracy;
  final int? delta;
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.perf,
    required this.showDivider,
    required this.isDark,
  });

  final _SectionPerf perf;
  final bool showDivider;
  final bool isDark;

  Color get _accColor {
    // 0% means "not enough signal yet" — keep it calm/neutral rather than
    // alarming red so a fresh dashboard doesn't read as failure.
    if (perf.accuracy == 0) return AppTheme.textSecondary;
    if (perf.accuracy < 40) return const Color(0xFFFF3B30);
    if (perf.accuracy < 60) return const Color(0xFFFF9F0A);
    return const Color(0xFF34C759);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final delta = perf.delta;
    // No movement yet → neutral dash, not a green "↑ +0" that falsely implies
    // improvement.
    final noChange = delta == null || delta == 0;
    final isUp = (delta ?? 0) > 0;
    final trendColor = noChange
        ? AppTheme.textSecondary
        : isUp
            ? const Color(0xFF34C759)
            : const Color(0xFFFF3B30);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(perf.section, style: tt.bodyLarge)),
                  Text(
                    '${perf.accuracy}%',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _accColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (noChange)
                    const Text(
                      '—',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    )
                  else ...[
                    Icon(
                      isUp
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 16,
                      color: trendColor,
                    ),
                    Text(
                      isUp ? '+$delta' : '$delta',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: trendColor,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: perf.accuracy / 100,
                  minHeight: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(_accColor),
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

// ── Insights entry ─────────────────────────────────────────────────────────

class _InsightsEntryRow extends StatelessWidget {
  const _InsightsEntryRow({required this.firebaseReady});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InsightsScreen(firebaseReady: firebaseReady),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.yellow.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: const Row(
          children: [
            Icon(Icons.insights_rounded, size: 18, color: AppTheme.yellow),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'View Progress Insights',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Study Plan ────────────────────────────────────────────────────────────────

class _StudyPlanCard extends StatelessWidget {
  const _StudyPlanCard({
    required this.examDate,
    required this.divisionProgress,
  });

  final DateTime examDate;
  final List<_DivisionProgress> divisionProgress;

  @override
  Widget build(BuildContext context) {
    final daysLeft = examDate.difference(DateTime.now()).inDays;
    final safeDays = daysLeft.clamp(1, 9999);
    final totalCards = divisionProgress.fold(0, (s, d) => s + d.total);
    final masteredCards = divisionProgress.fold(0, (s, d) => s + d.mastered);
    final remainingCards = totalCards - masteredCards;
    final dailyCards = (remainingCards / safeDays).ceil().clamp(3, 40);
    final dailyQuestions = (500 / safeDays).ceil().clamp(5, 30);
    final urgency = daysLeft <= 14
        ? AppTheme.error
        : daysLeft <= 30
            ? AppTheme.warning
            : AppTheme.success;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final subtitleColor =
        isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: urgency.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_rounded, size: 18, color: urgency),
                const SizedBox(width: 8),
                Text(
                  '$daysLeft days until exam',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: urgency,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Keep this pace to be ready',
              style: TextStyle(fontSize: 12, color: subtitleColor),
            ),
            const SizedBox(height: 16),
            const Text(
              "TODAY'S GOAL",
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _GoalChip(
                  icon: Icons.style_rounded,
                  value: dailyCards,
                  label: 'Cards',
                  color: AppTheme.yellow,
                ),
                const SizedBox(width: 10),
                _GoalChip(
                  icon: Icons.quiz_rounded,
                  value: dailyQuestions,
                  label: 'Questions',
                  color: AppTheme.blue,
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: totalCards == 0 ? 0 : masteredCards / totalCards,
                minHeight: 6,
                backgroundColor: AppTheme.separator,
                valueColor: AlwaysStoppedAnimation<Color>(urgency),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$masteredCards / $totalCards flashcards mastered',
              style: TextStyle(fontSize: 11, color: subtitleColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalChip extends StatelessWidget {
  const _GoalChip({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

