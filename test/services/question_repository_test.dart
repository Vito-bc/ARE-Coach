import 'package:architectula_education_app/data/seed_questions.dart';
import 'package:architectula_education_app/services/question_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loadNyQuestions returns mapped rows from loader', () async {
    final repository = QuestionRepository(
      loader: (limit) async => [
        MapEntry('qa', {
          'section': 'PA',
          'question': 'What?',
          'options': ['A', 'B'],
          'correctOption': 'A',
          'explanation': 'X',
          'codeReference': 'IBC',
          'examWeight': 5,
        }),
      ],
    );

    final result = await repository.loadNyQuestions(limit: 10);
    expect(result.length, 1);
    expect(result.first.id, 'qa');
    expect(result.first.correctOption, 'A');
  });

  test('loadNyQuestions falls back to seedQuestions on empty loader', () async {
    final repository = QuestionRepository(
      loader: (limit) async => [],
    );

    final result = await repository.loadNyQuestions();
    expect(result, seedQuestions);
  });

  test('loadNyQuestions falls back to seedQuestions on loader error', () async {
    final repository = QuestionRepository(
      loader: (limit) async => throw Exception('network'),
    );

    final result = await repository.loadNyQuestions();
    expect(result, seedQuestions);
  });
}
