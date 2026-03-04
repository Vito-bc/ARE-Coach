import 'package:architectula_education_app/models/quiz_question.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QuizQuestion.fromMap parses fields', () {
    final question = QuizQuestion.fromMap('q100', {
      'section': 'Programming & Analysis',
      'question': 'Sample?',
      'options': ['A', 'B'],
      'correctOption': 'A',
      'explanation': 'Because',
      'codeReference': 'IBC 1005.3.1',
      'examWeight': 12,
    });

    expect(question.id, 'q100');
    expect(question.section, 'Programming & Analysis');
    expect(question.options.length, 2);
    expect(question.correctOption, 'A');
    expect(question.examWeight, 12);
  });

  test('QuizQuestion.toMap includes baseline fields', () {
    const question = QuizQuestion(
      id: 'q1',
      section: 'PPD',
      question: 'Q?',
      options: ['A'],
      correctOption: 'A',
      explanation: 'E',
      codeReference: 'ADA 405.2',
      examWeight: 7,
    );

    final map = question.toMap(state: 'NY');
    expect(map['section'], 'PPD');
    expect(map['state'], 'NY');
    expect(map['correctOption'], 'A');
    expect(map.containsKey('createdAt'), true);
  });
}
