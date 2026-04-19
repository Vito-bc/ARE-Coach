import 'package:architectula_education_app/screens/auth/login_screen.dart';
import 'package:architectula_education_app/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthService extends Mock implements AuthService {}
class MockUser extends Mock implements User {}

Widget _buildSubject(AuthService authService) {
  return MaterialApp(
    home: LoginScreen(firebaseReady: true, authService: authService),
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

  group('LoginScreen rendering', () {
    testWidgets('shows title, email, password fields and buttons', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      expect(find.text('ArchiEd'), findsOneWidget);
      expect(find.byType(TextFormField), findsAtLeast(2));
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.text('Continue as Guest'), findsOneWidget);
    });
  });

  group('LoginScreen validation', () {
    testWidgets('shows error when submitting with empty email', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      await tester.tap(find.text('Sign In'));
      await tester.pump();

      expect(find.textContaining('email', findRichText: true), findsAtLeast(1));
    });

    testWidgets('shows error when email format is invalid', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
      await tester.tap(find.text('Sign In'));
      await tester.pump();

      expect(find.textContaining('email', findRichText: true), findsAtLeast(1));
    });

    testWidgets('shows error when password is empty', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      await tester.enterText(find.byType(TextFormField).first, 'test@example.com');
      await tester.tap(find.text('Sign In'));
      await tester.pump();

      expect(find.textContaining('password', findRichText: true), findsAtLeast(1));
    });
  });

  group('LoginScreen sign-in flow', () {
    testWidgets('calls signInWithEmail with correct credentials', (tester) async {
      when(() => mockAuthService.signInWithEmail(any(), any()))
          .thenAnswer((_) async => mockUser);

      await tester.pumpWidget(_buildSubject(mockAuthService));

      await tester.enterText(find.byType(TextFormField).first, 'test@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await tester.tap(find.text('Sign In'));
      await tester.pump();

      verify(() => mockAuthService.signInWithEmail('test@example.com', 'password123'))
          .called(1);
    });

    testWidgets('shows error message on FirebaseAuthException', (tester) async {
      when(() => mockAuthService.signInWithEmail(any(), any()))
          .thenThrow(FirebaseAuthException(code: 'user-not-found'));

      await tester.pumpWidget(_buildSubject(mockAuthService));

      await tester.enterText(find.byType(TextFormField).first, 'test@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await tester.tap(find.text('Sign In'));
      await tester.pump();

      expect(
        find.textContaining('Incorrect email or password', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('calls ensureSignedIn on Continue as Guest tap', (tester) async {
      when(() => mockAuthService.ensureSignedIn()).thenAnswer((_) async => mockUser);

      await tester.pumpWidget(_buildSubject(mockAuthService));

      await tester.tap(find.text('Continue as Guest'));
      await tester.pump();

      verify(() => mockAuthService.ensureSignedIn()).called(1);
    });
  });
}
