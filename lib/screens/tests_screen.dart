import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/theme/app_theme.dart';
import '../models/quiz_question.dart';
import '../services/progress_repository.dart';
import '_test_result_screen.dart';

import '_test_session_screen.dart';

class TestsScreen extends ConsumerStatefulWidget {
  const TestsScreen({super.key, required this.firebaseReady});
  final bool firebaseReady;

  @override
  ConsumerState<TestsScreen> createState() => _TestsScreenState();
}

enum TestMode { quick, section, timed }

class _TestsScreenState extends ConsumerState<TestsScreen> {
  TestMode _mode = TestMode.quick;
  String _selectedSection = 'All Divisions';
  int _questionCount = 20;
  bool _configuring = true;

  List<QuizQuestion> _questions = [];
  bool _loading = false;
  final _answers = <String, String>{};
  final _progressRepository = ProgressRepository();

  Timer? _timer;
  int _elapsedSec = 0;
  int _index = 0;
  bool _saving = false;
  bool _showResult = false;
  int _lastScore = 0;

  static const sections = [
    'All Divisions',
    'Practice Management',
    'Project Management',
    'Programming & Analysis',
    'Project Planning & Design',
    'Project Docs & Delivery',
    'Construction & Evaluation',
    'NYC Building Codes',
  ];

  static const sectionIcons = {
    'All Divisions': Icons.apps_rounded,
    'Practice Management': Icons.business_center_outlined,
    'Project Management': Icons.assignment_outlined,
    'Programming & Analysis': Icons.analytics_outlined,
    'Project Planning & Design': Icons.architecture_outlined,
    'Project Docs & Delivery': Icons.draw_outlined,
    'Construction & Evaluation': Icons.construction_outlined,
    'NYC Building Codes': Icons.location_city_outlined,
  };

  Future<void> _startTest() async {
    setState(() {
      _loading = true;
      _configuring = false;
    });

    var questions = await ref.read(allQuestionsProvider.future);

    if (_selectedSection != 'All Divisions') {
      questions = questions.where((q) => q.section == _selectedSection).toList();
    }

    questions.shuffle();
    if (questions.length > _questionCount) {
      questions = questions.take(_questionCount).toList();
    }

    if (!mounted) return;
    setState(() {
      _questions = questions;
      _loading = false;
      _index = 0;
      _answers.clear();
      _showResult = false;
      _elapsedSec = 0;
    });
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (_mode == TestMode.timed) {
      final limit = _questionCount * 90;
      _elapsedSec = limit;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsedSec--);
        if (_elapsedSec <= 0) {
          _submitTest();
        }
      });
      return;
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _showResult) return;
      setState(() => _elapsedSec++);
    });
  }

  void _goBackToConfig() {
    _timer?.cancel();
    setState(() {
      _configuring = true;
      _questions = [];
      _answers.clear();
      _showResult = false;
      _elapsedSec = 0;
      _index = 0;
    });
  }

  Future<void> _submitTest() async {
    if (_saving || _questions.isEmpty) return;
    _timer?.cancel();

    final correct = _questions.where((q) => _answers[q.id] == q.correctOption).length;
    final score = (correct / _questions.length * 100).round();

    setState(() {
      _saving = true;
      _showResult = true;
      _lastScore = score;
    });

    if (widget.firebaseReady) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await _progressRepository.saveAttempt(
          uid: uid,
          questions: _questions,
          answersByQuestionId: _answers,
          timeSpentSec: _elapsedSec,
          mode: _mode.name,
        );
        ref.invalidate(dashboardMetricsProvider);
      }
    }

    if (mounted) {
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: SafeArea(
        child: _configuring
            ? _TestsConfigView(
                mode: _mode,
                selectedSection: _selectedSection,
                questionCount: _questionCount,
                onModeChanged: (mode) => setState(() => _mode = mode),
                onSectionChanged: (section) => setState(() => _selectedSection = section),
                onQuestionCountChanged: (count) => setState(() => _questionCount = count),
                onStart: _startTest,
              )
            : _loading
                ? const _TestsLoadingView()
                : _showResult
                    ? TestResultScreen(
                        questions: _questions,
                        answers: _answers,
                        score: _lastScore,
                        elapsedSec: _elapsedSec,
                        mode: _mode,
                        firebaseReady: widget.firebaseReady,
                        onNewConfig: _goBackToConfig,
                        onRetry: _startTest,
                      )
                    : TestSessionScreen(
                        questions: _questions,
                        answers: _answers,
                        index: _index,
                        elapsedSec: _elapsedSec,
                        mode: _mode,
                        saving: _saving,
                        firebaseReady: widget.firebaseReady,
                        onAnswerSelected: (questionId, option) =>
                            setState(() => _answers[questionId] = option),
                        onPrevious: _index == 0 ? null : () => setState(() => _index--),
                        onNext: _index < _questions.length - 1
                            ? () => setState(() => _index++)
                            : null,
                        onSubmit: _answers.isEmpty || _saving ? null : _submitTest,
                        onExit: _goBackToConfig,
                      ),
      ),
    );
  }
}

class _TestsConfigView extends StatelessWidget {
  const _TestsConfigView({
    required this.mode,
    required this.selectedSection,
    required this.questionCount,
    required this.onModeChanged,
    required this.onSectionChanged,
    required this.onQuestionCountChanged,
    required this.onStart,
  });

  final TestMode mode;
  final String selectedSection;
  final int questionCount;
  final ValueChanged<TestMode> onModeChanged;
  final ValueChanged<String> onSectionChanged;
  final ValueChanged<int> onQuestionCountChanged;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        const Text(
          'Practice Tests',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Configure your session',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 28),
        const _SectionHeader('Test Mode'),
        const SizedBox(height: 10),
        Row(
          children: [
            _ModeChip(
              selected: mode == TestMode.quick,
              icon: Icons.bolt_rounded,
              label: 'Quick Quiz',
              onTap: () => onModeChanged(TestMode.quick),
            ),
            const SizedBox(width: 8),
            _ModeChip(
              selected: mode == TestMode.section,
              icon: Icons.menu_book_rounded,
              label: 'By Division',
              onTap: () => onModeChanged(TestMode.section),
            ),
            const SizedBox(width: 8),
            _ModeChip(
              selected: mode == TestMode.timed,
              icon: Icons.timer_outlined,
              label: 'Timed Exam',
              onTap: () => onModeChanged(TestMode.timed),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _SectionHeader('Division'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: TestsScreenStateConfig.sections.map((section) {
            final isSelected = selectedSection == section;
            return GestureDetector(
              onTap: () => onSectionChanged(section),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.yellow.withValues(alpha: 0.15)
                      : const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? AppTheme.yellow : const Color(0xFF374151),
                    width: isSelected ? 1.5 : 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      TestsScreenStateConfig.sectionIcons[section] ?? Icons.circle_outlined,
                      size: 14,
                      color: isSelected ? AppTheme.yellow : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      section,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? AppTheme.yellow : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        const _SectionHeader('Number of Questions'),
        const SizedBox(height: 10),
        Row(
          children: [10, 20, 40, 60].map((count) {
            final isSelected = questionCount == count;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onQuestionCountChanged(count),
                child: Container(
                  width: 56,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.yellow : const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? AppTheme.yellow : const Color(0xFF374151),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? AppTheme.navy : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        if (mode == TestMode.timed)
          Text(
            '� ${(questionCount * 1.5).round()} minutes',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF374151), width: 0.5),
          ),
          child: Column(
            children: [
              _SummaryRow(icon: Icons.quiz_outlined, label: 'Questions', value: '$questionCount'),
              const Divider(color: Color(0xFF374151), height: 16),
              _SummaryRow(icon: Icons.category_outlined, label: 'Division', value: selectedSection),
              const Divider(color: Color(0xFF374151), height: 16),
              _SummaryRow(
                icon: Icons.timer_outlined,
                label: 'Mode',
                value: mode == TestMode.quick
                    ? 'Quick Quiz'
                    : mode == TestMode.section
                        ? 'By Division'
                        : 'Timed Exam',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text(
              'Start Test',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

class _TestsLoadingView extends StatelessWidget {
  const _TestsLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppTheme.yellow),
          SizedBox(height: 16),
          Text(
            'Loading questions...',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.yellow.withValues(alpha: 0.15)
                : const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppTheme.yellow : const Color(0xFF374151),
              width: selected ? 1.5 : 0.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected ? AppTheme.yellow : AppTheme.textSecondary,
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppTheme.yellow : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

abstract final class TestsScreenStateConfig {
  static const sections = _TestsScreenState.sections;
  static const sectionIcons = _TestsScreenState.sectionIcons;
}
