import 'package:flutter/material.dart';

import '../data/seed_questions.dart';

class TestsScreen extends StatefulWidget {
  const TestsScreen({super.key});

  @override
  State<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends State<TestsScreen> {
  String? _selected;
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    final q = seedQuestions.first;
    final isCorrect = _submitted && _selected == q.correctOption;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Practice Tests',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
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
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    q.section,
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(height: 8),
                  Text(q.question, style: const TextStyle(fontSize: 17)),
                  const SizedBox(height: 10),
                  ...q.options.map((option) {
                    return RadioListTile<String>(
                      value: option,
                      groupValue: _selected,
                      title: Text(option),
                      onChanged: (value) => setState(() => _selected = value),
                      contentPadding: EdgeInsets.zero,
                    );
                  }),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _selected == null
                        ? null
                        : () => setState(() => _submitted = true),
                    child: const Text('Submit'),
                  ),
                  if (_submitted) ...[
                    const SizedBox(height: 12),
                    Text(
                      isCorrect ? 'Correct' : 'Review needed',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isCorrect ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Code: ${q.codeReference}'),
                    const SizedBox(height: 4),
                    Text('Exam value: ${q.examWeight} points'),
                    const SizedBox(height: 8),
                    Text(q.explanation),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
