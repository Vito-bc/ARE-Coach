import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/quiz_question.dart';
import '../widgets/flag_question_sheet.dart';
import 'coach_screen.dart';
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
    required this.studyMode,
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
  final bool studyMode;
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
                _OptionTile(
                  option: option,
                  selected: selected,
                  question: question,
                  studyMode: studyMode,
                  locked: studyMode && selected != null,
                  onTap: () {
                    if (studyMode && selected != null) return;
                    onAnswerSelected(question.id, option);
                  },
                ),
              if (studyMode && selected != null) ...[
                const SizedBox(height: 8),
                _StudyFeedbackPanel(
                  question: question,
                  selectedOption: selected,
                  onAskCoach: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CoachScreen(
                        initialMessage:
                            'Explain this ARE question: "${question.question}" — '
                            'The correct answer is "${question.correctOption}". '
                            '${question.explanation}',
                      ),
                    ),
                  ),
                ),
              ],
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

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.selected,
    required this.question,
    required this.studyMode,
    required this.locked,
    required this.onTap,
  });

  final String option;
  final String? selected;
  final QuizQuestion question;
  final bool studyMode;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == option;
    final isCorrect = option == question.correctOption;

    Color borderColor = isSelected ? AppTheme.yellow : const Color(0xFF374151);
    Color bgColor = isSelected ? const Color(0xFF2D2400) : const Color(0xFF1F2937);
    Color dotColor = isSelected ? AppTheme.yellow : Colors.transparent;
    Color dotBorder = isSelected ? AppTheme.yellow : const Color(0xFF6B7280);

    if (studyMode && locked) {
      if (isCorrect) {
        borderColor = AppTheme.success;
        bgColor = AppTheme.success.withValues(alpha: 0.08);
        dotColor = AppTheme.success;
        dotBorder = AppTheme.success;
      } else if (isSelected) {
        borderColor = AppTheme.error;
        bgColor = AppTheme.error.withValues(alpha: 0.08);
        dotColor = AppTheme.error;
        dotBorder = AppTheme.error;
      } else {
        borderColor = const Color(0xFF374151);
        bgColor = const Color(0xFF1F2937);
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: isSelected || (studyMode && locked && isCorrect) ? 1.5 : 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
                border: Border.all(color: dotBorder, width: 1.5),
              ),
              child: studyMode && locked && isCorrect
                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                  : studyMode && locked && isSelected && !isCorrect
                      ? const Icon(Icons.close_rounded, size: 14, color: Colors.white)
                      : isSelected && !studyMode
                          ? const Icon(Icons.check_rounded, size: 14, color: Color(0xFF0D1117))
                          : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                option,
                style: TextStyle(
                  color: isSelected || (studyMode && locked && isCorrect)
                      ? Colors.white
                      : const Color(0xFF8B9CB6),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudyFeedbackPanel extends StatelessWidget {
  const _StudyFeedbackPanel({
    required this.question,
    required this.selectedOption,
    required this.onAskCoach,
  });

  final QuizQuestion question;
  final String selectedOption;
  final VoidCallback onAskCoach;

  bool get _isCorrect => selectedOption == question.correctOption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isCorrect
            ? AppTheme.success.withValues(alpha: 0.06)
            : AppTheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isCorrect
              ? AppTheme.success.withValues(alpha: 0.3)
              : AppTheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
                size: 18,
                color: _isCorrect ? AppTheme.success : AppTheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                _isCorrect ? 'Correct!' : 'Incorrect',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _isCorrect ? AppTheme.success : AppTheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            question.explanation,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          if (question.codeReference.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              question.codeReference,
              style: const TextStyle(
                color: AppTheme.yellow,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onAskCoach,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.yellow.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.yellow.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline_rounded, size: 14, color: AppTheme.yellow),
                  SizedBox(width: 6),
                  Text(
                    'Ask Coach about this',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.yellow,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
