import 'package:are_coach/models/quiz_question.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuizQuestion.fromMap', () {
    test('parses all required fields', () {
      final q = QuizQuestion.fromMap('q100', {
        'section': 'Programming & Analysis',
        'question': 'Sample?',
        'options': ['A', 'B'],
        'correctOption': 'A',
        'explanation': 'Because',
        'codeReference': 'IBC 1005.3.1',
        'examWeight': 12,
      });

      expect(q.id, 'q100');
      expect(q.section, 'Programming & Analysis');
      expect(q.options.length, 2);
      expect(q.correctOption, 'A');
      expect(q.examWeight, 12);
    });

    test('parses optional topic and difficulty fields', () {
      final q = QuizQuestion.fromMap('q200', {
        'section': 'Project Planning & Design',
        'question': 'Q?',
        'options': ['A', 'B', 'C', 'D'],
        'correctOption': 'C',
        'explanation': 'E',
        'codeReference': 'IBC 1017.2',
        'examWeight': 10,
        'topic': 'Egress & Life Safety',
        'difficulty': 'medium',
      });

      expect(q.topic, 'Egress & Life Safety');
      expect(q.difficulty, 'medium');
    });

    test('topic and difficulty are null when absent', () {
      final q = QuizQuestion.fromMap('q300', {
        'section': 'CE',
        'question': 'Q?',
        'options': ['A'],
        'correctOption': 'A',
        'explanation': 'E',
        'codeReference': 'AIA A201',
        'examWeight': 8,
      });

      expect(q.topic, isNull);
      expect(q.difficulty, isNull);
    });
  });

  group('QuizQuestion.toMap', () {
    test('includes baseline fields and state', () {
      const q = QuizQuestion(
        id: 'q1',
        section: 'PPD',
        question: 'Q?',
        options: ['A'],
        correctOption: 'A',
        explanation: 'E',
        codeReference: 'ADA 405.2',
        examWeight: 7,
      );

      final map = q.toMap(state: 'NY');
      expect(map['section'], 'PPD');
      expect(map['state'], 'NY');
      expect(map['correctOption'], 'A');
      expect(map.containsKey('createdAt'), true);
      expect(map['difficulty'], 'medium');
    });

    test('includes topic when set', () {
      const q = QuizQuestion(
        id: 'q2',
        section: 'PcM',
        question: 'Q?',
        options: ['A'],
        correctOption: 'A',
        explanation: 'E',
        codeReference: 'AIA B101',
        examWeight: 9,
        topic: 'Contracts & Agreements',
        difficulty: 'easy',
      );

      final map = q.toMap();
      expect(map['topic'], 'Contracts & Agreements');
      expect(map['difficulty'], 'easy');
    });

    test('omits topic key when null', () {
      const q = QuizQuestion(
        id: 'q3',
        section: 'CE',
        question: 'Q?',
        options: ['A'],
        correctOption: 'A',
        explanation: 'E',
        codeReference: 'AIA A201',
        examWeight: 8,
      );

      final map = q.toMap();
      expect(map.containsKey('topic'), false);
    });
  });
}
