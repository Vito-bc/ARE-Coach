import 'package:are_coach/core/legal_versions.dart';
import 'package:are_coach/screens/auth/login_screen.dart';
import 'package:are_coach/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class MockAuthService extends Mock implements AuthService {}
class MockUser extends Mock implements User {}
class FakeTermsAssent extends Fake implements TermsAssent {}

Widget _buildSubject(AuthService authService) {
  return MaterialApp(
    home: LoginScreen(firebaseReady: true, authService: authService),
  );
}

Future<void> _tickAssent(WidgetTester tester) async {
  await tester.tap(find.byType(Checkbox).first);
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

  group('LoginScreen rendering', () {
    testWidgets('shows title, email, password fields and buttons', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      expect(find.text('ARE Coach'), findsOneWidget);
      expect(find.byType(TextFormField), findsAtLeast(2));
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.text('Continue as Guest'), findsOneWidget);
    });

    testWidgets('shows exactly one Terms/Privacy checkbox when Apple sign-in is not shown', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      // Default test platform is not iOS/macOS, so only the Guest checkbox
      // renders.
      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
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

  group('LoginScreen existing-account sign-in is unaffected by the assent gate', () {
    testWidgets('calls signInWithEmail with correct credentials while unticked', (tester) async {
      when(() => mockAuthService.signInWithEmail(any(), any()))
          .thenAnswer((_) async => mockUser);

      await tester.pumpWidget(_buildSubject(mockAuthService));
      // Deliberately NOT ticking the checkbox: returning sign-in of an
      // existing account must never be gated by it.

      await tester.enterText(find.byType(TextFormField).first, 'test@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await tester.tap(find.text('Sign In'));
      await tester.pump();

      verify(() => mockAuthService.signInWithEmail('test@example.com', 'password123'))
          .called(1);
    });

    testWidgets('Sign In button is never disabled by the assent checkbox', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Sign In'));
      expect(button.onPressed, isNotNull);
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
  });

  group('LoginScreen Guest assent gate', () {
    testWidgets('checkbox defaults to unticked', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isFalse);
    });

    testWidgets('Continue as Guest is disabled while unticked, enabled once ticked', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      var button = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Continue as Guest'));
      expect(button.onPressed, isNull);

      await _tickAssent(tester);

      button = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Continue as Guest'));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('tapping Continue as Guest while unticked explains why, not silently', (tester) async {
      await tester.pumpWidget(_buildSubject(mockAuthService));

      await tester.tap(find.text('Continue as Guest'));
      await tester.pump();

      expect(
        find.textContaining('agree to the Terms of Service and Privacy Policy'),
        findsOneWidget,
      );
      verifyNever(() => mockAuthService.ensureSignedIn(assent: any(named: 'assent')));
    });

    testWidgets('calls ensureSignedIn with the current terms version once ticked', (tester) async {
      when(() => mockAuthService.ensureSignedIn(assent: any(named: 'assent')))
          .thenAnswer((_) async => mockUser);

      await tester.pumpWidget(_buildSubject(mockAuthService));
      await _tickAssent(tester);

      await tester.tap(find.text('Continue as Guest'));
      await tester.pump();

      final captured = verify(
        () => mockAuthService.ensureSignedIn(assent: captureAny(named: 'assent')),
      ).captured;
      final assent = captured.single as TermsAssent;
      expect(assent.termsVersion, kTermsVersion);
      expect(assent.privacyVersion, kPrivacyVersion);
    });

    testWidgets('a failed assent write surfaces an error and does not proceed as guest', (tester) async {
      when(() => mockAuthService.ensureSignedIn(assent: any(named: 'assent')))
          .thenThrow(const AssentRecordException('firestore permission denied'));
      var guestContinued = false;

      await tester.pumpWidget(MaterialApp(
        home: LoginScreen(
          firebaseReady: true,
          authService: mockAuthService,
          onGuestContinue: () => guestContinued = true,
        ),
      ));
      await _tickAssent(tester);

      await tester.tap(find.text('Continue as Guest'));
      await tester.pump();

      expect(find.textContaining('Could not save your agreement', findRichText: true), findsOneWidget);
      expect(guestContinued, isFalse);
    });

    testWidgets('a bare (non-assent) guest sign-in failure still proceeds, unchanged from before', (tester) async {
      when(() => mockAuthService.ensureSignedIn(assent: any(named: 'assent')))
          .thenThrow(Exception('offline'));
      var guestContinued = false;

      await tester.pumpWidget(MaterialApp(
        home: LoginScreen(
          firebaseReady: true,
          authService: mockAuthService,
          onGuestContinue: () => guestContinued = true,
        ),
      ));
      await _tickAssent(tester);

      await tester.tap(find.text('Continue as Guest'));
      await tester.pump();

      expect(guestContinued, isTrue);
    });
  });

  group('LoginScreen Apple sign-in assent gate (iOS)', () {
    // Reset INSIDE each test body, as its literal last action (not via
    // tearDown/addTearDown): flutter_test's end-of-test invariant check runs
    // synchronously right after the testWidgets callback returns, before
    // package:test ever gets to a tearDown/addTearDown callback -- so those
    // are always too late here and fail with "a foundation debug variable
    // was changed by the test".

    testWidgets('renders two checkboxes (above Apple and above Guest), both unticked', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await tester.pumpWidget(_buildSubject(mockAuthService));

        final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
        expect(checkboxes, hasLength(2));
        expect(checkboxes.every((c) => c.value == false), isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('ticking either checkbox enables both the Apple and Guest actions', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        when(() => mockAuthService.signInWithApple(assent: any(named: 'assent')))
            .thenAnswer((_) async => mockUser);

        await tester.pumpWidget(_buildSubject(mockAuthService));
        await _tickAssent(tester); // ticks the first (Apple) instance

        final guestButton = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Continue as Guest'));
        expect(guestButton.onPressed, isNotNull);

        await tester.tap(find.byType(SignInWithAppleButton));
        await tester.pump();

        verify(() => mockAuthService.signInWithApple(assent: any(named: 'assent'))).called(1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('tapping Apple sign-in while unticked explains why instead of signing in', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await tester.pumpWidget(_buildSubject(mockAuthService));

        await tester.tap(find.byType(SignInWithAppleButton));
        await tester.pump();

        expect(
          find.textContaining('agree to the Terms of Service and Privacy Policy'),
          findsOneWidget,
        );
        verifyNever(() => mockAuthService.signInWithApple(assent: any(named: 'assent')));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a failed assent write on Apple sign-in surfaces an error', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        when(() => mockAuthService.signInWithApple(assent: any(named: 'assent')))
            .thenThrow(const AssentRecordException('firestore permission denied'));

        await tester.pumpWidget(_buildSubject(mockAuthService));
        await _tickAssent(tester);

        await tester.tap(find.byType(SignInWithAppleButton));
        await tester.pump();

        expect(find.textContaining('could not save', findRichText: true), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
