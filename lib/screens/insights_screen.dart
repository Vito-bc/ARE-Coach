import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/theme/app_theme.dart';
import '../core/ui/app_chrome.dart';
import '../models/flashcard.dart';
import '../services/flashcard_repository.dart';
import '../services/progress_repository.dart';

class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  int _mastered = 0;
  int _learning = 0;
  int _fresh = 0;
  int _total = 0;
  bool _cardsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadFlashcardStats();
  }

  Future<void> _loadFlashcardStats() async {
    final repo = FlashcardRepository();
    final cards = await repo.loadAll();
    final statuses = await repo.allStatuses();
    int mastered = 0, learning = 0, fresh = 0;
    for (final c in cards) {
      final s = statuses[c.id] ?? CardStatus.fresh;
      if (s == CardStatus.mastered) {
        mastered++;
      } else if (s == CardStatus.learning) {
        learning++;
      } else {
        fresh++;
      }
    }
    if (mounted) {
      setState(() {
        _mastered = mastered;
        _learning = learning;
        _fresh = fresh;
        _total = cards.length;
        _cardsLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.firebaseReady
        ? FirebaseAuth.instance.currentUser?.uid
        : null;
    final args = (uid: uid, firebaseReady: widget.firebaseReady);

    final scoresAsync = ref.watch(recentScoresProvider(args));
    final accuraciesAsync = ref.watch(allSectionAccuraciesProvider(args));
    final metricsAsync = ref.watch(dashboardMetricsProvider(args));

    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(
        title: const Text('Progress Insights'),
        backgroundColor: AppTheme.navy.withValues(alpha: 0.92),
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: AppBackdrop()),
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
            children: [
              // ── Score Trend ────────────────────────────────────────────
              const _SectionHeader('Score Trend'),
              const SizedBox(height: 12),
              scoresAsync.when(
                data: (scores) => _ScoreTrendCard(scores: scores),
                loading: () => const _LoadingCard(),
                error: (_, __) => _ErrorCard(
                  onRetry: () => ref.invalidate(recentScoresProvider(args)),
                ),
              ),

              const SizedBox(height: 28),

              // ── Section Accuracy ───────────────────────────────────────
              const _SectionHeader('Accuracy by Division'),
              const SizedBox(height: 12),
              accuraciesAsync.when(
                data: (list) => _AccuracyCard(accuracies: list),
                loading: () => const _LoadingCard(),
                error: (_, __) => _ErrorCard(
                  onRetry: () => ref.invalidate(allSectionAccuraciesProvider(args)),
                ),
              ),

              const SizedBox(height: 28),

              // ── Weak Spots ─────────────────────────────────────────────
              metricsAsync.maybeWhen(
                data: (metrics) {
                  if (metrics.weakSections.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionHeader('Focus Areas'),
                      const SizedBox(height: 12),
                      ...metrics.weakSections.map(
                        (w) => _WeakSpotCard(metric: w),
                      ),
                      const SizedBox(height: 28),
                    ],
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),

              // ── Flashcard Mastery ──────────────────────────────────────
              const _SectionHeader('Flashcard Mastery'),
              const SizedBox(height: 12),
              _cardsLoaded
                  ? _FlashcardMasteryCard(
                      mastered: _mastered,
                      learning: _learning,
                      fresh: _fresh,
                      total: _total,
                    )
                  : const _LoadingCard(),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Score Trend
// ─────────────────────────────────────────────────────────────────────────────

class _ScoreTrendCard extends StatelessWidget {
  const _ScoreTrendCard({required this.scores});

  final List<ScorePoint> scores;

  @override
  Widget build(BuildContext context) {
    if (scores.isEmpty) {
      return const _EmptyState(
        icon: Icons.show_chart_rounded,
        message: 'Complete a test to see your score trend.',
      );
    }

    final avg = (scores.map((s) => s.score).reduce((a, b) => a + b) /
            scores.length)
        .round();
    final latest = scores.last.score;
    final latestColor = latest >= 70
        ? AppTheme.success
        : latest >= 50
            ? AppTheme.warning
            : AppTheme.error;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatPill(
                label: 'Latest',
                value: '$latest%',
                color: latestColor,
              ),
              const SizedBox(width: 10),
              _StatPill(
                label: 'Average',
                value: '$avg%',
                color: AppTheme.textSecondary,
              ),
              const Spacer(),
              Text(
                '${scores.length} attempt${scores.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 110,
            width: double.infinity,
            child: CustomPaint(
              painter: _SparklinePainter(scores: scores),
            ),
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Older',
                style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
              ),
              Text(
                'Recent',
                style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.scores});

  final List<ScorePoint> scores;

  static const _pass = 70.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.isEmpty) return;

    final n = scores.length;
    final values = scores.map((s) => s.score.toDouble()).toList();

    // Dashed 70% threshold line
    final thresholdY = size.height * (1 - _pass / 100);
    final dashPaint = Paint()
      ..color = AppTheme.success.withValues(alpha: 0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const dw = 6.0;
    const ds = 4.0;
    double dx = 0;
    while (dx < size.width) {
      canvas.drawLine(
        Offset(dx, thresholdY),
        Offset(math.min(dx + dw, size.width), thresholdY),
        dashPaint,
      );
      dx += dw + ds;
    }

    // Compute screen positions
    final pts = <Offset>[];
    for (int i = 0; i < n; i++) {
      final px = n == 1 ? size.width / 2 : (i / (n - 1)) * size.width;
      final py = size.height * (1 - values[i] / 100);
      pts.add(Offset(px, py));
    }

    // Line connecting dots
    if (pts.length > 1) {
      final linePaint = Paint()
        ..color = AppTheme.yellow.withValues(alpha: 0.65)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(path, linePaint);
    }

    // Dots
    for (int i = 0; i < pts.length; i++) {
      final v = values[i];
      final dotColor = v >= 70
          ? AppTheme.success
          : v >= 50
              ? AppTheme.warning
              : AppTheme.error;
      // Navy ring so dot stands out against line
      canvas.drawCircle(
        pts[i],
        6,
        Paint()..color = AppTheme.navy,
      );
      canvas.drawCircle(
        pts[i],
        4.5,
        Paint()
          ..color = dotColor
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.scores != scores;
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Accuracy
// ─────────────────────────────────────────────────────────────────────────────

class _AccuracyCard extends StatelessWidget {
  const _AccuracyCard({required this.accuracies});

  final List<WeakSectionMetric> accuracies;

  @override
  Widget build(BuildContext context) {
    if (accuracies.isEmpty) {
      return const _EmptyState(
        icon: Icons.bar_chart_rounded,
        message: 'Complete section tests to see accuracy by division.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.separator, width: 0.5),
      ),
      child: Column(
        children: [
          for (int i = 0; i < accuracies.length; i++)
            _AccuracyRow(
              metric: accuracies[i],
              showDivider: i < accuracies.length - 1,
            ),
        ],
      ),
    );
  }
}

class _AccuracyRow extends StatelessWidget {
  const _AccuracyRow({
    required this.metric,
    required this.showDivider,
  });

  final WeakSectionMetric metric;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final acc = metric.accuracy;
    final color = acc >= 70
        ? AppTheme.success
        : acc >= 50
            ? AppTheme.warning
            : AppTheme.error;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              SizedBox(
                width: 130,
                child: Text(
                  metric.section,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: acc / 100,
                    minHeight: 6,
                    backgroundColor: AppTheme.separator,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 38,
                child: Text(
                  '$acc%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Weak Spots
// ─────────────────────────────────────────────────────────────────────────────

class _WeakSpotCard extends StatelessWidget {
  const _WeakSpotCard({required this.metric});

  final WeakSectionMetric metric;

  @override
  Widget build(BuildContext context) {
    final acc = metric.accuracy;
    final color = acc >= 70
        ? AppTheme.success
        : acc >= 50
            ? AppTheme.warning
            : AppTheme.error;
    final message = acc < 50
        ? 'Needs focused review'
        : acc < 70
            ? 'Getting there — keep practicing'
            : 'On track';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
            ),
            child: Center(
              child: Text(
                '$acc%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.section,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            acc < 70
                ? Icons.arrow_forward_ios_rounded
                : Icons.check_circle_outline_rounded,
            size: 16,
            color: color.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Flashcard Mastery
// ─────────────────────────────────────────────────────────────────────────────

class _FlashcardMasteryCard extends StatelessWidget {
  const _FlashcardMasteryCard({
    required this.mastered,
    required this.learning,
    required this.fresh,
    required this.total,
  });

  final int mastered;
  final int learning;
  final int fresh;
  final int total;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : mastered / total,
              minHeight: 8,
              backgroundColor: AppTheme.separator,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppTheme.success),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$mastered of $total cards mastered',
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _MasteryTile(
                count: mastered,
                label: 'Mastered',
                color: AppTheme.success,
              ),
              const SizedBox(width: 10),
              _MasteryTile(
                count: learning,
                label: 'Learning',
                color: AppTheme.warning,
              ),
              const SizedBox(width: 10),
              _MasteryTile(
                count: fresh,
                label: 'New',
                color: AppTheme.textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MasteryTile extends StatelessWidget {
  const _MasteryTile({
    required this.count,
    required this.label,
    required this.color,
  });

  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 26,
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

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: AppTheme.textSecondary,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.separator, width: 0.5),
      ),
      child: child,
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.separator, width: 0.5),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          color: AppTheme.yellow,
          strokeWidth: 2,
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.separator, width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Could not load data',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.yellow,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Retry', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.separator, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppTheme.textSecondary),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
