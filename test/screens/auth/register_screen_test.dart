import 'package:are_coach/core/legal_versions.dart';
import 'package:are_coach/screens/auth/register_screen.dart';
import 'package:are_coach/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthService extends Mock implements AuthService {}
class MockUser extends Mock implements User {}
class FakeTermsAssent extends Fake implements TermsAssent {}

Widget _buildSubject(AuthService authService) {
  return MaterialApp(
    home: RegisterScreen(firebaseReady: true, authService: authService),
  );
}

Future<void> _tickAssent(WidgetTester tester) async {
  await tester.tap(find.byType(Checkbox));
  await tester.pump();
}

void main() {
  late MockAuthService mockAuthService;
  late MockUser mockUser;

  setUpAll(() {
    registerFallbackValue(FakeTermsAssent());
  });

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

    testWidgets('shows the Terms/Privacy checkbox with tappable-link wording', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.textContaining('I have read and agree to the'), findsOneWidget);
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
    });
  });

  group('RegisterScreen Terms/Privacy assent gate', () {
    testWidgets('checkbox defaults to unticked', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isFalse);
    });

    testWidgets('Create Account is disabled while unticked, enabled once ticked', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      var button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      await _tickAssent(tester);

      button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('tapping Create Account while unticked explains why, not silently', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      expect(
        find.textContaining('agree to the Terms of Service and Privacy Policy'),
        findsOneWidget,
      );
      verifyNever(() => mockAuthService.registerWithEmail(any(), any(), assent: any(named: 'assent')));
    });

    testWidgets('sign-up is blocked while unticked even via keyboard submit — auth service not called', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'new@example.com');
      await tester.enterText(fields.at(1), 'password123');
      if (fields.evaluate().length >= 3) {
        await tester.enterText(fields.at(2), 'password123');
      }
      // The confirm-password field's onFieldSubmitted calls _handleRegister
      // directly, bypassing the button entirely -- must still be blocked.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      verifyNever(() => mockAuthService.registerWithEmail(any(), any(), assent: any(named: 'assent')));
      expect(
        find.textContaining('agree to the Terms of Service and Privacy Policy'),
        findsOneWidget,
      );
    });

    testWidgets('checkbox stays unticked (and gate stays active) after a failed attempt', (tester) async {
      when(() => mockAuthService.registerWithEmail(any(), any(), assent: any(named: 'assent')))
          .thenThrow(FirebaseAuthException(code: 'email-already-in-use'));

      await tester.pumpWidget(_buildSubject(mockAuthService));
      await _tickAssent(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'taken@example.com');
      await tester.enterText(fields.at(1), 'password123');
      if (fields.evaluate().length >= 3) {
        await tester.enterText(fields.at(2), 'password123');
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      // The attempt actually reached the auth service (box was ticked) and
      // failed; the gate itself is unaffected by that failure -- it neither
      // auto-unticks nor silently bypasses on retry.
      verify(() => mockAuthService.registerWithEmail(any(), any(), assent: any(named: 'assent'))).called(1);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    });

    testWidgets('a brand new instance of this screen always starts unticked, never inheriting a prior tick', (tester) async {
      // Full teardown/remount (not a rebuild of the same element) -- the
      // most direct proof that nothing makes this default sticky across
      // screen instances, e.g. across a pop-and-reopen of Create Account.
      await tester.pumpWidget(_buildSubject(mockAuthService));
      await _tickAssent(tester);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_buildSubject(mockAuthService));

      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    });
  });

  group('RegisterScreen validation', () {
    testWidgets('shows error when email is empty', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));
      await _tickAssent(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      expect(find.textContaining('email', findRichText: true), findsAtLeast(1));
    });

    testWidgets('shows error when email format is invalid', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));
      await _tickAssent(tester);

      await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      expect(find.textContaining('email', findRichText: true), findsAtLeast(1));
    });

    testWidgets('shows error when passwords do not match', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));
      await _tickAssent(tester);

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
      await _tickAssent(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'test@example.com');
      await tester.enterText(fields.at(1), 'abc');
      if (fields.evaluate().length >= 3) {
        await tester.enterText(fields.at(2), 'abc');
      }

      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      expect(
        find.textContaining('Use at least 8', findRichText: true),
        findsAtLeast(1),
      );
    });

    testWidgets('shows error when password lacks a letter and number', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));
      await _tickAssent(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'test@example.com');
      // 8+ chars but letters only → must fail the letter+number rule.
      await tester.enterText(fields.at(1), 'abcdefgh');
      if (fields.evaluate().length >= 3) {
        await tester.enterText(fields.at(2), 'abcdefgh');
      }

      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      expect(
        find.textContaining('Include at least', findRichText: true),
        findsAtLeast(1),
      );
    });
  });

  group('RegisterScreen registration flow', () {
    testWidgets('calls registerWithEmail with correct values and the current terms version', (tester) async {
      when(() => mockAuthService.registerWithEmail(any(), any(), assent: any(named: 'assent')))
          .thenAnswer((_) async => mockUser);

      await tester.pumpWidget(_buildSubject(mockAuthService));
      await _tickAssent(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'new@example.com');
      await tester.enterText(fields.at(1), 'password123');
      if (fields.evaluate().length >= 3) {
        await tester.enterText(fields.at(2), 'password123');
      }

      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      final captured = verify(() => mockAuthService.registerWithEmail(
            'new@example.com',
            'password123',
            assent: captureAny(named: 'assent'),
          )).captured;
      final assent = captured.single as TermsAssent;
      expect(assent.termsVersion, kTermsVersion);
      expect(assent.privacyVersion, kPrivacyVersion);
    });

    testWidgets('shows error message on FirebaseAuthException', (tester) async {
      when(() => mockAuthService.registerWithEmail(any(), any(), assent: any(named: 'assent')))
          .thenThrow(FirebaseAuthException(code: 'email-already-in-use'));

      await tester.pumpWidget(_buildSubject(mockAuthService));
      await _tickAssent(tester);

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

    testWidgets('a failed assent write surfaces an error instead of being swallowed', (tester) async {
      when(() => mockAuthService.registerWithEmail(any(), any(), assent: any(named: 'assent')))
          .thenThrow(const AssentRecordException('firestore permission denied'));

      await tester.pumpWidget(_buildSubject(mockAuthService));
      await _tickAssent(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'new@example.com');
      await tester.enterText(fields.at(1), 'password123');
      if (fields.evaluate().length >= 3) {
        await tester.enterText(fields.at(2), 'password123');
      }

      await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
      await tester.pump();

      expect(
        find.textContaining('could not save', findRichText: true),
        findsOneWidget,
      );
    });
  });
}
