import 'package:architectula_education_app/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockUserCredential extends Mock implements UserCredential {}

void main() {
  test('ensureSignedIn returns current user if already signed in', () async {
    final auth = _MockFirebaseAuth();
    final user = _MockUser();
    when(() => auth.currentUser).thenReturn(user);

    final service = AuthService(auth: auth);
    final result = await service.ensureSignedIn();

    expect(result, user);
    verifyNever(() => auth.signInAnonymously());
  });

  test('ensureSignedIn uses anonymous sign-in when no current user', () async {
    final auth = _MockFirebaseAuth();
    final credential = _MockUserCredential();
    final user = _MockUser();
    when(() => auth.currentUser).thenReturn(null);
    when(() => credential.user).thenReturn(user);
    when(() => auth.signInAnonymously()).thenAnswer((_) async => credential);

    final service = AuthService(auth: auth);
    final result = await service.ensureSignedIn();

    expect(result, user);
    verify(() => auth.signInAnonymously()).called(1);
  });
}
