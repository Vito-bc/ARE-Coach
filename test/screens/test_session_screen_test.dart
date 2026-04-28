import 'package:architectula_education_app/core/theme/app_theme.dart';
import 'package:architectula_education_app/models/quiz_question.dart';
import 'package:architectula_education_app/screens/_test_session_screen.dart';
import 'package:architectula_education_app/screens/tests_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders questions and keeps session controls tappable', (
    tester,
  ) async {
    final elapsed = ValueNotifier<int>(90);
    var selectedAnswer = '';
    var nextTapped = false;
    var exitTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: TestSessionScreen(
            questions: const [
              QuizQuestion(
                id: 'q1',
                section: 'Practice Management',
                question:
                    'Which agreement is used between architect and owner?',
                options: ['AIA B101', 'AIA A201', 'AIA C401', 'AIA G702'],
                correctOption: 'AIA B101',
                explanation: 'B101 is a standard owner-architect agreement.',
                codeReference: 'AIA B101',
                examWeight: 10,
              ),
            ],
            answers: const {},
            index: 0,
            elapsedListenable: elapsed,
            mode: TestMode.quick,
            saving: false,
            firebaseReady: false,
            studyMode: false,
            onAnswerSelected: (_, option) => selectedAnswer = option,
            onPrevious: null,
            onNext: () => nextTapped = true,
            onSubmit: () {},
            onExit: () => exitTapped = true,
          ),
        ),
      ),
    );

    expect(
      find.text('Which agreement is used between architect and owner?'),
      findsOneWidget,
    );
    expect(find.text('AIA B101'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    await tester.tap(find.text('AIA B101'));
    await tester.tap(find.text('Next'));
    await tester.tap(find.byIcon(Icons.close_rounded));

    expect(selectedAnswer, 'AIA B101');
    expect(nextTapped, isTrue);
    expect(exitTapped, isTrue);

    elapsed.dispose();
  });
}
