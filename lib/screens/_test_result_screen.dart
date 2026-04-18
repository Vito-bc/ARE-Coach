import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/quiz_question.dart';
import 'package:architectula_education_app/screens/tests_screen.dart';

class TestResultScreen extends StatelessWidget {
  const TestResultScreen({
    super.key,
    required this.questions,
    required this.answers,
    required this.score,
    required this.elapsedSec,
    required this.mode,
    required this.onNewConfig,
    required this.onRetry,
  });

  final List<QuizQuestion> questions;
  final Map<String, String> answers;
  final int score;
  final int elapsedSec;
  final TestMode mode;
  final VoidCallback onNewConfig;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final correct = questions.where((q) => answers[q.id] == q.correctOption).length;
    final incorrect = questions
        .where((q) => answers.containsKey(q.id) && answers[q.id] != q.correctOption)
        .toList();
    final unanswered = questions.length - answers.length;

    final scoreColor = score >= 70
        ? AppTheme.success
        : score >= 50
            ? AppTheme.warning
            : AppTheme.error;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scoreColor.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Text(
                '$score%',
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w900,
                  color: scoreColor,
                  letterSpacing: -2,
                ),
              ),
              Text(
                score >= 70
                    ? 'Passing � great work!'
                    : score >= 50
                        ? 'Almost there � keep studying'
                        : 'Needs more practice',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _StatBox('Correct', '$correct', AppTheme.success),
                  _StatBox('Wrong', '${incorrect.length}', AppTheme.error),
                  _StatBox('Skipped', '$unanswered', AppTheme.textSecondary),
                  _StatBox('Time', _formatTime(), AppTheme.yellow),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onNewConfig,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('New Config'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (incorrect.isNotEmpty) ...[
          const Text(
            'Review Wrong Answers',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          for (final question in incorrect)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.error.withValues(alpha: 0.25), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    question.section,
                    style: const TextStyle(
                      color: AppTheme.yellow,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    question.question,
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
                    value: answers[question.id] ?? '�',
                    color: AppTheme.error,
                  ),
                  const SizedBox(height: 4),
                  _ReviewRow(
                    icon: Icons.check_rounded,
                    label: 'Correct',
                    value: question.correctOption,
                    color: AppTheme.success,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    question.explanation,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    question.codeReference,
                    style: const TextStyle(
                      color: AppTheme.yellow,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  String _formatTime() {
    final displaySeconds = mode == TestMode.timed ? elapsedSec : elapsedSec;
    final minutes = (displaySeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (displaySeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color),
        ),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
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
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
      ],
    );
  }
}
