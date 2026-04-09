import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/quiz_question.dart';
import '../services/progress_repository.dart';
import '../services/question_repository.dart';

class TestsScreen extends StatefulWidget {
  const TestsScreen({super.key, required this.firebaseReady});
  final bool firebaseReady;

  @override
  State<TestsScreen> createState() => _TestsScreenState();
}

// ── Modes ─────────────────────────────────────────────────────────────────────
enum _TestMode { quick, section, timed }

class _TestsScreenState extends State<TestsScreen> {
  // Config state
  _TestMode _mode = _TestMode.quick;
  String _selectedSection = 'All Divisions';
  int _questionCount = 20;
  bool _configuring = true; // show config vs test

  // Test state
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

  static const _sections = [
    'All Divisions',
    'Practice Management',
    'Project Management',
    'Programming & Analysis',
    'Project Planning & Design',
    'Project Docs & Delivery',
    'Construction & Evaluation',
    'NYC Building Codes',
  ];

  static const _sectionIcons = {
    'All Divisions': Icons.apps_rounded,
    'Practice Management': Icons.business_center_outlined,
    'Project Management': Icons.assignment_outlined,
    'Programming & Analysis': Icons.analytics_outlined,
    'Project Planning & Design': Icons.architecture_outlined,
    'Project Docs & Delivery': Icons.draw_outlined,
    'Construction & Evaluation': Icons.construction_outlined,
    'NYC Building Codes': Icons.location_city_outlined,
  };

  // ── Load & start ────────────────────────────────────────────────────────────
  Future<void> _startTest() async {
    setState(() {
      _loading = true;
      _configuring = false;
    });

    var questions = await QuestionRepository().loadFromAsset(limit: 0);

    // Filter by section
    if (_selectedSection != 'All Divisions') {
      questions = questions
          .where((q) => q.section == _selectedSection)
          .toList();
    }

    // Shuffle and limit
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
    if (_mode == _TestMode.timed) {
      // countdown
      final limit = _questionCount * 90; // 90 sec per question
      _elapsedSec = limit;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsedSec--);
        if (_elapsedSec <= 0) _submitTest();
      });
    } else {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _showResult) return;
        setState(() => _elapsedSec++);
      });
    }
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

    final correct =
        _questions.where((q) => _answers[q.id] == q.correctOption).length;
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
      }
    }

    if (mounted) setState(() => _saving = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: SafeArea(
        child: _configuring
            ? _buildConfig()
            : _loading
                ? _buildLoading()
                : _showResult
                    ? _buildResult()
                    : _buildTest(),
      ),
    );
  }

  // ── Config screen ───────────────────────────────────────────────────────────
  Widget _buildConfig() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        const Text('Practice Tests',
            style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -1)),
        const SizedBox(height: 4),
        const Text('Configure your session',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
        const SizedBox(height: 28),

        // ── Mode selector ──────────────────────────────────────────────────
        _sectionHeader('Test Mode'),
        const SizedBox(height: 10),
        Row(
          children: [
            _modeChip(_TestMode.quick, Icons.bolt_rounded, 'Quick Quiz'),
            const SizedBox(width: 8),
            _modeChip(_TestMode.section, Icons.menu_book_rounded, 'By Division'),
            const SizedBox(width: 8),
            _modeChip(_TestMode.timed, Icons.timer_outlined, 'Timed Exam'),
          ],
        ),
        const SizedBox(height: 24),

        // ── Division picker ────────────────────────────────────────────────
        _sectionHeader('Division'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _sections.map((s) {
            final selected = _selectedSection == s;
            return GestureDetector(
              onTap: () => setState(() => _selectedSection = s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.yellow.withValues(alpha: 0.15)
                      : const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? AppTheme.yellow
                        : const Color(0xFF374151),
                    width: selected ? 1.5 : 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _sectionIcons[s] ?? Icons.circle_outlined,
                      size: 14,
                      color: selected ? AppTheme.yellow : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(s,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: selected ? AppTheme.yellow : AppTheme.textSecondary,
                        )),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),

        // ── Question count ─────────────────────────────────────────────────
        _sectionHeader('Number of Questions'),
        const SizedBox(height: 10),
        Row(
          children: [10, 20, 40, 60].map((n) {
            final selected = _questionCount == n;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _questionCount = n),
                child: Container(
                  width: 56,
                  height: 48,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.yellow
                        : const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? AppTheme.yellow
                          : const Color(0xFF374151),
                    ),
                  ),
                  child: Center(
                    child: Text('$n',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: selected ? AppTheme.navy : AppTheme.textSecondary,
                        )),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        if (_mode == _TestMode.timed)
          Text(
            '≈ ${(_questionCount * 1.5).round()} minutes',
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 12),
          ),
        const SizedBox(height: 32),

        // ── Summary card ───────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF374151), width: 0.5),
          ),
          child: Column(
            children: [
              _summaryRow(Icons.quiz_outlined, 'Questions', '$_questionCount'),
              const Divider(color: Color(0xFF374151), height: 16),
              _summaryRow(
                  Icons.category_outlined, 'Division', _selectedSection),
              const Divider(color: Color(0xFF374151), height: 16),
              _summaryRow(
                Icons.timer_outlined,
                'Mode',
                _mode == _TestMode.quick
                    ? 'Quick Quiz'
                    : _mode == _TestMode.section
                        ? 'By Division'
                        : 'Timed Exam',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Start button ───────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            onPressed: _startTest,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start Test',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _modeChip(_TestMode mode, IconData icon, String label) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = mode),
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
              Icon(icon,
                  color: selected ? AppTheme.yellow : AppTheme.textSecondary,
                  size: 22),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
                    color:
                        selected ? AppTheme.yellow : AppTheme.textSecondary,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Text(title,
      style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600));

  Widget _summaryRow(IconData icon, String label, String value) => Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      );

  // ── Loading ─────────────────────────────────────────────────────────────────
  Widget _buildLoading() => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.yellow),
            SizedBox(height: 16),
            Text('Loading questions...',
                style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );

  // ── Test screen ─────────────────────────────────────────────────────────────
  Widget _buildTest() {
    if (_questions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No questions found for this selection.',
                style: TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: _goBackToConfig,
                child: const Text('Back to Config')),
          ],
        ),
      );
    }

    final q = _questions[_index];
    final selected = _answers[q.id];
    final progress = (_index + 1) / _questions.length;

    return Column(
      children: [
        // Top bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              IconButton(
                onPressed: _goBackToConfig,
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
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(AppTheme.yellow),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_index + 1} of ${_questions.length}',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _mode == _TestMode.timed && _elapsedSec < 60
                      ? const Color(0xFF3D0000)
                      : const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatTime(),
                  style: TextStyle(
                    color: _mode == _TestMode.timed && _elapsedSec < 60
                        ? Colors.red
                        : AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Question content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              // Division tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.yellow.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(q.section,
                    style: const TextStyle(
                        color: AppTheme.yellow,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 12),

              // Question
              Text(q.question,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.5)),
              const SizedBox(height: 20),

              // Options
              for (final option in q.options)
                GestureDetector(
                  onTap: () => setState(() => _answers[q.id] = option),
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: selected == option
                          ? const Color(0xFF2D2400)
                          : const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected == option
                            ? AppTheme.yellow
                            : const Color(0xFF374151),
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
                            color: selected == option
                                ? AppTheme.yellow
                                : Colors.transparent,
                            border: Border.all(
                              color: selected == option
                                  ? AppTheme.yellow
                                  : const Color(0xFF6B7280),
                              width: 1.5,
                            ),
                          ),
                          child: selected == option
                              ? const Icon(Icons.check_rounded,
                                  size: 14, color: Color(0xFF0D1117))
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(option,
                              style: TextStyle(
                                color: selected == option
                                    ? Colors.white
                                    : const Color(0xFF8B9CB6),
                                fontSize: 14,
                                height: 1.4,
                              )),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),

        // Bottom nav
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(
            color: Color(0xFF161B22),
            border: Border(top: BorderSide(color: Color(0xFF21262D), width: 0.5)),
          ),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: _index == 0 ? null : () => setState(() => _index--),
                child: const Text('Previous'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _index < _questions.length - 1
                      ? () => setState(() => _index++)
                      : null,
                  child: const Text('Next'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _answers.isEmpty || _saving ? null : _submitTest,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1F2937),
                  foregroundColor: AppTheme.yellow,
                  side: const BorderSide(color: AppTheme.yellow, width: 1),
                ),
                child: Text(_saving ? '...' : 'Submit'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Result screen ───────────────────────────────────────────────────────────
  Widget _buildResult() {
    final correct =
        _questions.where((q) => _answers[q.id] == q.correctOption).length;
    final incorrect = _questions
        .where((q) =>
            _answers.containsKey(q.id) && _answers[q.id] != q.correctOption)
        .toList();
    final unanswered = _questions.length - _answers.length;

    final scoreColor = _lastScore >= 70
        ? AppTheme.success
        : _lastScore >= 50
            ? AppTheme.warning
            : AppTheme.error;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        // Score hero
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scoreColor.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Text('$_lastScore%',
                  style: TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.w900,
                      color: scoreColor,
                      letterSpacing: -2)),
              Text(
                _lastScore >= 70
                    ? 'Passing — great work!'
                    : _lastScore >= 50
                        ? 'Almost there — keep studying'
                        : 'Needs more practice',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _statBox('Correct', '$correct', AppTheme.success),
                  _statBox('Wrong', '${incorrect.length}', AppTheme.error),
                  _statBox('Skipped', '$unanswered', AppTheme.textSecondary),
                  _statBox('Time', _formatTime(), AppTheme.yellow),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Actions
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _goBackToConfig,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('New Config'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _startTest,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Wrong answers review
        if (incorrect.isNotEmpty) ...[
          const Text('Review Wrong Answers',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          for (final q in incorrect)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppTheme.error.withValues(alpha: 0.25), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(q.section,
                      style: const TextStyle(
                          color: AppTheme.yellow,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(q.question,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.4)),
                  const SizedBox(height: 10),
                  _reviewRow(
                      Icons.close_rounded, 'Your answer',
                      _answers[q.id] ?? '—', AppTheme.error),
                  const SizedBox(height: 4),
                  _reviewRow(
                      Icons.check_rounded, 'Correct',
                      q.correctOption, AppTheme.success),
                  const SizedBox(height: 8),
                  Text(q.explanation,
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          height: 1.5)),
                  const SizedBox(height: 4),
                  Text(q.codeReference,
                      style: const TextStyle(
                          color: AppTheme.yellow,
                          fontSize: 11,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _statBox(String label, String value, Color color) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color)),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 11)),
        ],
      );

  Widget _reviewRow(IconData icon, String label, String value, Color color) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text('$label: ',
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12))),
        ],
      );

  String _formatTime() {
    if (_mode == _TestMode.timed) {
      final m = (_elapsedSec ~/ 60).toString().padLeft(2, '0');
      final s = (_elapsedSec % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }
    final m = (_elapsedSec ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
