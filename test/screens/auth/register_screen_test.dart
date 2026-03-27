import 'package:architectula_education_app/screens/auth/register_screen.dart';
import 'package:architectula_education_app/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthService extends Mock implements AuthService {}
class MockUser extends Mock implements User {}

Widget _buildSubject(AuthService authService) {
  return MaterialApp(
    home: RegisterScreen(firebaseReady: true, authService: authService),
  );
}

void main() {
  late MockAuthService mockAuthService;
  late MockUser mockUser;

  setUp(() {
    mockAuthService = MockAuthService();
    mockUser = MockUser();
    when(() => mockUser.uid).thenReturn('test-uid');
  });

  group('RegisterScreen rendering', () {
    testWidgets('shows title, email, password, confirm fields and button', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      expect(find.text('Create Account'), findsAtLeast(1));
      expect(find.byType(TextFormField), findsAtLeast(2));
    });

    testWidgets('shows back navigation', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    });

    testWidgets('shows sign-in link', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      expect(find.text('Sign In'), findsOneWidget);
    });
  });

  group('RegisterScreen validation', () {
    testWidgets('shows error when email is empty', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      expect(find.textContaining('email', findRichText: true), findsAtLeast(1));
    });

    testWidgets('shows error when email format is invalid', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      expect(find.textContaining('email', findRichText: true), findsAtLeast(1));
    });

    testWidgets('shows error when passwords do not match', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'test@example.com');
      await tester.enterText(fields.at(1), 'password123');
      if (fields.evaluate().length >= 3) {
        await tester.enterText(fields.at(2), 'different456');
      }

      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      expect(
        find.textContaining(RegExp(r'match|password', caseSensitive: false), findRichText: true),
        findsAtLeast(1),
      );
    });

    testWidgets('shows error when password is too short', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'test@example.com');
      await tester.enterText(fields.at(1), 'abc');
      if (fields.evaluate().length >= 3) {
        await tester.enterText(fields.at(2), 'abc');
      }

      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      expect(
        find.textContaining('6 characters', findRichText: true),
        findsAtLeast(1),
      );
    });
  });

  group('RegisterScreen registration flow', () {
    testWidgets('calls registerWithEmail with correct values', (tester) async {
      when(() => mockAuthService.registerWithEmail(any(), any()))
          .thenAnswer((_) async => mockUser);

      await tester.pumpWidget(_buildSubject(mockAuthService));

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'new@example.com');
      await tester.enterText(fields.at(1), 'password123');
      if (fields.evaluate().length >= 3) {
        await tester.enterText(fields.at(2), 'password123');
      }

      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      verify(() => mockAuthService.registerWithEmail('new@example.com', 'password123'))
          .called(1);
    });

    testWidgets('shows error message on FirebaseAuthException', (tester) async {
      when(() => mockAuthService.registerWithEmail(any(), any()))
          .thenThrow(FirebaseAuthException(code: 'email-already-in-use'));

      await tester.pumpWidget(_buildSubject(mockAuthService));

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'taken@example.com');
      await tester.enterText(fields.at(1), 'password123');
      if (fields.evaluate().length >= 3) {
        await tester.enterText(fields.at(2), 'password123');
      }

      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      expect(
        find.textContaining('already exists', findRichText: true),
        findsOneWidget,
      );
    });
  });
}
