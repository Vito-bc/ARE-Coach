import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/quiz_question.dart';
import '../widgets/flag_question_sheet.dart';
import 'package:architectula_education_app/screens/tests_screen.dart';

class TestSessionScreen extends StatelessWidget {
  const TestSessionScreen({
    super.key,
    required this.questions,
    required this.answers,
    required this.index,
    required this.elapsedSec,
    required this.mode,
    required this.saving,
    required this.firebaseReady,
    required this.onAnswerSelected,
    required this.onPrevious,
    required this.onNext,
    required this.onSubmit,
    required this.onExit,
  });

  final List<QuizQuestion> questions;
  final Map<String, String> answers;
  final int index;
  final int elapsedSec;
  final TestMode mode;
  final bool saving;
  final bool firebaseReady;
  final void Function(String questionId, String option) onAnswerSelected;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onSubmit;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No questions found for this selection.',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onExit, child: const Text('Back to Config')),
          ],
        ),
      );
    }

    final question = questions[index];
    final selected = answers[question.id];
    final progress = (index + 1) / questions.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              IconButton(
                onPressed: onExit,
                icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF1F2937),
                  padding: const EdgeInsets.all(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: const Color(0xFF374151),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.yellow),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${index + 1} of ${questions.length}',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: mode == TestMode.timed && elapsedSec < 60
                      ? const Color(0xFF3D0000)
                      : const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatTime(),
                  style: TextStyle(
                    color: mode == TestMode.timed && elapsedSec < 60
                        ? Colors.red
                        : AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => showFlagQuestionSheet(
                  context,
                  question: questions[index],
                  firebaseReady: firebaseReady,
                ),
                icon: const Icon(Icons.flag_outlined, size: 18),
                color: AppTheme.textSecondary,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF1F2937),
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.yellow.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  question.section,
                  style: const TextStyle(
                    color: AppTheme.yellow,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                question.question,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              for (final option in question.options)
                GestureDetector(
                  onTap: () => onAnswerSelected(question.id, option),
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: selected == option ? const Color(0xFF2D2400) : const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected == option ? AppTheme.yellow : const Color(0xFF374151),
                        width: selected == option ? 1.5 : 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected == option ? AppTheme.yellow : Colors.transparent,
                            border: Border.all(
                              color: selected == option ? AppTheme.yellow : const Color(0xFF6B7280),
                              width: 1.5,
                            ),
                          ),
                          child: selected == option
                              ? const Icon(Icons.check_rounded, size: 14, color: Color(0xFF0D1117))
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            option,
                            style: TextStyle(
                              color: selected == option ? Colors.white : const Color(0xFF8B9CB6),
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(
            color: Color(0xFF161B22),
            border: Border(top: BorderSide(color: Color(0xFF21262D), width: 0.5)),
          ),
          child: Row(
            children: [
              OutlinedButton(onPressed: onPrevious, child: const Text('Previous')),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(onPressed: onNext, child: const Text('Next')),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1F2937),
                  foregroundColor: AppTheme.yellow,
                  side: const BorderSide(color: AppTheme.yellow, width: 1),
                ),
                child: Text(saving ? '...' : 'Submit'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatTime() {
    final minutes = (elapsedSec ~/ 60).toString().padLeft(2, '0');
    final seconds = (elapsedSec % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
