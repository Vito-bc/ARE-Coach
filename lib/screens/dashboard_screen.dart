import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/ui/app_chrome.dart';
import '../services/progress_repository.dart';
import 'attempt_history_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _progressRepository = ProgressRepository();
  late final Future<DashboardMetrics> _metricsFuture;

  @override
  void initState() {
    super.initState();
    _metricsFuture = _loadMetrics();
  }

  Future<DashboardMetrics> _loadMetrics() async {
    if (!widget.firebaseReady) {
      return const DashboardMetrics(
        readinessPercent: 42,
        attemptsCount: 3,
        weakSections: [
          WeakSectionMetric(section: 'Project Management', accuracy: 31),
          WeakSectionMetric(section: 'Programming & Analysis', accuracy: 38),
          WeakSectionMetric(section: 'Structural Systems', accuracy: 43),
        ],
        sectionTrends: [],
      );
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const DashboardMetrics(
        readinessPercent: 0,
        attemptsCount: 0,
        weakSections: [],
        sectionTrends: [],
      );
    }
    return _progressRepository.fetchDashboardMetrics(uid: uid);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: FutureBuilder<DashboardMetrics>(
          future: _metricsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final metrics = snapshot.data ??
                const DashboardMetrics(
                  readinessPercent: 0,
                  attemptsCount: 0,
                  weakSections: [],
                  sectionTrends: [],
                );

            return CustomScrollView(
              slivers: [
                // Large title header — Apple Books style
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
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

                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            );
          },
        ),
      ),
    );
  }
}

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
              // Circular progress
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
                      percent >= 70
                          ? 'On track for the exam'
                          : percent >= 40
                              ? 'Keep practicing'
                              : 'Just getting started',
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
              backgroundColor: isDark
                  ? const Color(0xFF3A3A3C)
                  : const Color(0xFFE5E5EA),
            ),
          ),
        ],
      ),
    );
  }
}

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
                  Expanded(
                    child: Text(section, style: tt.bodyLarge),
                  ),
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
                  backgroundColor: isDark
                      ? const Color(0xFF3A3A3C)
                      : const Color(0xFFE5E5EA),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 0,
            indent: 16,
            color: isDark
                ? const Color(0xFF38383A)
                : const Color(0xFFC6C6C8),
            thickness: 0.5,
          ),
      ],
    );
  }
}

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
    final trendColor = isUp
        ? const Color(0xFF34C759)
        : const Color(0xFFFF3B30);

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
            color: isDark
                ? const Color(0xFF38383A)
                : const Color(0xFFC6C6C8),
            thickness: 0.5,
          ),
      ],
    );
  }
}
