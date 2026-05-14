import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/quiz_question.dart';
import '../widgets/flag_question_sheet.dart';

class MockExamResultScreen extends StatelessWidget {
  const MockExamResultScreen({
    super.key,
    required this.questions,
    required this.answers,
    required this.score,
    required this.usedSec,
    required this.firebaseReady,
    required this.onNewConfig,
    required this.onRetry,
  });

  final List<QuizQuestion> questions;
  final Map<String, String> answers;
  final int score;
  final int usedSec;
  final bool firebaseReady;
  final VoidCallback onNewConfig;
  final VoidCallback onRetry;

  static const _canonicalOrder = [
    'Practice Management',
    'Project Management',
    'Programming & Analysis',
    'Project Planning & Design',
    'Project Docs & Delivery',
    'Construction & Evaluation',
    'NYC Building Codes',
  ];

  static const _abbr = {
    'Practice Management': 'PcM',
    'Project Management': 'PjM',
    'Programming & Analysis': 'PA',
    'Project Planning & Design': 'PPD',
    'Project Docs & Delivery': 'PDD',
    'Construction & Evaluation': 'CE',
    'NYC Building Codes': 'NYC',
  };

  @override
  Widget build(BuildContext context) {
    final passed = score >= 70;
    final statusColor = passed ? AppTheme.success : AppTheme.error;

    final correct =
        questions.where((q) => answers[q.id] == q.correctOption).length;
    final wrong = questions
        .where(
          (q) =>
              answers.containsKey(q.id) && answers[q.id] != q.correctOption,
        )
        .toList();
    final skipped = questions.length - answers.length;

    // Per-section breakdown
    final bySection = <String, _SectionStats>{};
    for (final q in questions) {
      final stats = bySection.putIfAbsent(q.section, () => _SectionStats(q.section));
      stats.total++;
      if (answers[q.id] == q.correctOption) stats.correct++;
    }
    final sections = bySection.values.toList()
      ..sort((a, b) {
        final ai = _canonicalOrder.indexOf(a.section);
        final bi = _canonicalOrder.indexOf(b.section);
        if (ai < 0 && bi < 0) return 0;
        if (ai < 0) return 1;
        if (bi < 0) return -1;
        return ai.compareTo(bi);
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
      children: [
        // ── Verdict card ────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                statusColor.withValues(alpha: 0.15),
                statusColor.withValues(alpha: 0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: statusColor.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    passed
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    size: 26,
                    color: statusColor,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    passed ? 'PASS' : 'FAIL',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: statusColor,
                      letterSpacing: 2.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '$score%',
                style: TextStyle(
                  fontSize: 68,
                  fontWeight: FontWeight.w900,
                  color: statusColor,
                  letterSpacing: -3,
                  height: 1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                passed
                    ? 'Passing score achieved — great work!'
                    : 'Passing threshold is 70%',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _StatBox('Correct', '$correct', AppTheme.success),
                  _StatBox('Wrong', '${wrong.length}', AppTheme.error),
                  _StatBox('Skipped', '$skipped', AppTheme.textSecondary),
                  _StatBox('Time', _fmtTime(usedSec), AppTheme.yellow),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        // ── Division breakdown ───────────────────────────────────────
        const _Label('Division Breakdown'),
        const SizedBox(height: 12),
        if (sections.isEmpty)
          const _EmptySection()
        else
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF374151),
                width: 0.5,
              ),
            ),
            child: Column(
              children: [
                for (int i = 0; i < sections.length; i++)
                  _DivisionRow(
                    stats: sections[i],
                    abbr: _abbr[sections[i].section] ?? '??',
                    showDivider: i < sections.length - 1,
                  ),
              ],
            ),
          ),

        const SizedBox(height: 28),

        // ── Actions ──────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onNewConfig,
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('New Config'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry Exam'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.yellow,
                  foregroundColor: AppTheme.navy,
                ),
              ),
            ),
          ],
        ),

        // ── Wrong answers review ─────────────────────────────────────
        if (wrong.isNotEmpty) ...[
          const SizedBox(height: 32),
          const _Label('Review Wrong Answers'),
          const SizedBox(height: 12),
          for (final q in wrong)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.error.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    q.section,
                    style: const TextStyle(
                      color: AppTheme.yellow,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    q.question,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ReviewRow(
                    icon: Icons.close_rounded,
                    label: 'Your answer',
                    value: answers[q.id] ?? '—',
                    color: AppTheme.error,
                  ),
                  const SizedBox(height: 4),
                  _ReviewRow(
                    icon: Icons.check_rounded,
                    label: 'Correct',
                    value: q.correctOption,
                    color: AppTheme.success,
                  ),
                  if (q.explanation.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      q.explanation,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                  if (q.codeReference.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      q.codeReference,
                      style: const TextStyle(
                        color: AppTheme.yellow,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => showFlagQuestionSheet(
                        context,
                        question: q,
                        firebaseReady: firebaseReady,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.flag_outlined,
                            size: 13,
                            color: AppTheme.textSecondary,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Flag question',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  static String _fmtTime(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-section stats model
// ─────────────────────────────────────────────────────────────────────────────

class _SectionStats {
  _SectionStats(this.section);

  final String section;
  int total = 0;
  int correct = 0;

  int get accuracy => total == 0 ? 0 : ((correct / total) * 100).round();
  bool get passed => accuracy >= 70;
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: AppTheme.textSecondary,
      ),
    );
  }
}

class _DivisionRow extends StatelessWidget {
  const _DivisionRow({
    required this.stats,
    required this.abbr,
    required this.showDivider,
  });

  final _SectionStats stats;
  final String abbr;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final acc = stats.accuracy;
    final color = acc >= 70
        ? AppTheme.success
        : acc >= 50
            ? AppTheme.warning
            : AppTheme.error;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.12),
                ),
                child: Center(
                  child: Text(
                    abbr,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  stats.section,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${stats.correct}/${stats.total}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 36,
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
              const SizedBox(width: 8),
              Icon(
                stats.passed
                    ? Icons.check_circle_outline_rounded
                    : Icons.highlight_off_rounded,
                size: 16,
                color: color,
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(
            height: 0,
            indent: 16,
            color: Color(0xFF374151),
            thickness: 0.5,
          ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: Text(
          'No section data',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
      ),
    );
  }
}
