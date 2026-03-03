import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/seed_questions.dart';
import '../models/quiz_question.dart';
import '../services/progress_repository.dart';
import '../services/question_repository.dart';

class TestsScreen extends StatefulWidget {
  const TestsScreen({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends State<TestsScreen> {
  late final Future<List<QuizQuestion>> _questionsFuture;
  final _answersByQuestionId = <String, String>{};
  final _progressRepository = ProgressRepository();

  Timer? _timer;
  int _elapsedSec = 0;
  int _index = 0;
  bool _saving = false;
  bool _showResult = false;
  int _lastScore = 0;

  @override
  void initState() {
    super.initState();
    _questionsFuture = widget.firebaseReady
        ? QuestionRepository().loadNyQuestions(limit: 20)
        : Future.value(seedQuestions);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _showResult) return;
      setState(() => _elapsedSec++);
    });
  }

  void _resetTest() {
    setState(() {
      _answersByQuestionId.clear();
      _index = 0;
      _showResult = false;
      _lastScore = 0;
      _elapsedSec = 0;
    });
    _startTimer();
  }

  Future<void> _submitTest(List<QuizQuestion> questions) async {
    if (_saving) return;
    final answered = _answersByQuestionId.length;
    if (questions.isEmpty || answered == 0) return;

    final correct = questions.where((q) => _answersByQuestionId[q.id] == q.correctOption).length;
    final score = ((correct / questions.length) * 100).round();

    setState(() {
      _saving = true;
      _showResult = true;
      _lastScore = score;
    });
    _timer?.cancel();

    if (widget.firebaseReady) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await _progressRepository.saveAttempt(
          uid: uid,
          questions: questions,
          answersByQuestionId: _answersByQuestionId,
          timeSpentSec: _elapsedSec,
          mode: 'section',
        );
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Practice Tests',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            _showResult
                ? 'Completed in ${_formatDuration(_elapsedSec)}'
                : 'Time: ${_formatDuration(_elapsedSec)}',
            style: const TextStyle(color: Color(0xFF4B5563)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              Chip(label: Text('Section Practice')),
              Chip(label: Text('3h Full Simulator')),
              Chip(label: Text('Random 20')),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.firebaseReady
                          ? 'Question set from Firestore (NY collection)'
                          : 'Demo question set loaded locally (NYC starter pack)',
                    ),
                  ),
                  TextButton(
                    onPressed: _resetTest,
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<QuizQuestion>>(
            future: _questionsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final questions = snapshot.data ?? const <QuizQuestion>[];
              if (questions.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No questions found. Import seed set to Firestore.'),
                  ),
                );
              }

              if (_showResult) {
                return _buildResultCard(questions);
              }

              final question = questions[_index];
              final selected = _answersByQuestionId[question.id];

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            question.section,
                            style: TextStyle(color: Theme.of(context).colorScheme.primary),
                          ),
                          const Spacer(),
                          Text('Q ${_index + 1}/${questions.length}'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(question.question, style: const TextStyle(fontSize: 17)),
                      const SizedBox(height: 10),
                      ...question.options.map((option) {
                        return RadioListTile<String>(
                          value: option,
                          groupValue: selected,
                          title: Text(option),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _answersByQuestionId[question.id] = value);
                          },
                          contentPadding: EdgeInsets.zero,
                        );
                      }),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          OutlinedButton(
                            onPressed: _index == 0
                                ? null
                                : () => setState(() => _index = _index - 1),
                            child: const Text('Previous'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _index == questions.length - 1
                                ? null
                                : () => setState(() => _index = _index + 1),
                            child: const Text('Next'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: _answersByQuestionId.isEmpty || _saving
                            ? null
                            : () => _submitTest(questions),
                        child: Text(_saving ? 'Saving...' : 'Submit Test'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(List<QuizQuestion> questions) {
    final answered = _answersByQuestionId.length;
    final incorrectQuestions = questions
        .where((q) => _answersByQuestionId[q.id] != null)
        .where((q) => _answersByQuestionId[q.id] != q.correctOption)
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Score: $_lastScore%',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text('Answered: $answered / ${questions.length}'),
            const SizedBox(height: 6),
            Text('Time: ${_formatDuration(_elapsedSec)}'),
            const SizedBox(height: 12),
            const Text(
              'Review',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (incorrectQuestions.isEmpty)
              const Text('No wrong answers in submitted items.')
            else
              ...incorrectQuestions.map(
                (q) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        q.question,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text('Correct: ${q.correctOption}'),
                      Text('Code: ${q.codeReference}'),
                      Text(q.explanation),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _resetTest,
              child: const Text('Start New Attempt'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int sec) {
    final min = (sec ~/ 60).toString().padLeft(2, '0');
    final rem = (sec % 60).toString().padLeft(2, '0');
    return '$min:$rem';
  }
}
