// ignore_for_file: subtype_of_sealed_class
import 'package:architectula_education_app/services/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}
class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}
class MockUserCredential extends Mock implements UserCredential {}
class MockUser extends Mock implements User {}
class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}
class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}
class FakeAuthCredential extends Fake implements AuthCredential {}

void _stubFirestore(
  MockFirebaseFirestore mockFirestore,
  MockCollectionReference mockCollection,
  MockDocumentReference mockDoc,
) {
  when(() => mockFirestore.collection('users')).thenReturn(mockCollection);
  when(() => mockCollection.doc(any())).thenReturn(mockDoc);
  when(() => mockDoc.set(any(), any())).thenAnswer((_) async {});
}

void main() {
  late MockFirebaseAuth mockAuth;
  late MockFirebaseFirestore mockFirestore;
  late MockCollectionReference mockCollection;
  late MockDocumentReference mockDoc;
  late MockUser mockUser;
  late AuthService sut;

  setUpAll(() {
    registerFallbackValue(SetOptions(merge: true));
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(FakeAuthCredential());
  });

  setUp(() {
    mockAuth = MockFirebaseAuth();
    mockFirestore = MockFirebaseFirestore();
    mockCollection = MockCollectionReference();
    mockDoc = MockDocumentReference();
    mockUser = MockUser();

    when(() => mockUser.uid).thenReturn('test-uid');
    when(() => mockUser.email).thenReturn('test@example.com');
    when(() => mockUser.displayName).thenReturn(null);

    _stubFirestore(mockFirestore, mockCollection, mockDoc);

    sut = AuthService(auth: mockAuth, firestore: mockFirestore);
  });

  group('currentUser', () {
    test('returns null when no user is signed in', () {
      when(() => mockAuth.currentUser).thenReturn(null);
      expect(sut.currentUser, isNull);
    });

    test('returns the current user when signed in', () {
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      expect(sut.currentUser, equals(mockUser));
    });
  });

  group('isAnonymous', () {
    test('returns true when currentUser is null', () {
      when(() => mockAuth.currentUser).thenReturn(null);
      expect(sut.isAnonymous, isTrue);
    });

    test('returns true when currentUser is anonymous', () {
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.isAnonymous).thenReturn(true);
      expect(sut.isAnonymous, isTrue);
    });

    test('returns false when currentUser is not anonymous', () {
      when(() => mockAuth.currentUser).thenReturn(mockUser);
      when(() => mockUser.isAnonymous).thenReturn(false);
      expect(sut.isAnonymous, isFalse);
    });
  });

  group('ensureSignedIn', () {
    test('returns existing user without signing in again', () async {
      when(() => mockAuth.currentUser).thenReturn(mockUser);

      final result = await sut.ensureSignedIn();

      expect(result, equals(mockUser));
      verifyNever(() => mockAuth.signInAnonymously());
    });

    test('calls signInAnonymously when no user is signed in', () async {
      final mockCredential = MockUserCredential();
      when(() => mockAuth.currentUser).thenReturn(null);
      when(() => mockAuth.signInAnonymously()).thenAnswer((_) async => mockCredential);
      when(() => mockCredential.user).thenReturn(mockUser);

      final result = await sut.ensureSignedIn();

      expect(result, equals(mockUser));
      verify(() => mockAuth.signInAnonymously()).called(1);
    });
  });

  group('signInAnonymously', () {
    test('returns user and writes user record', () async {
      final mockCredential = MockUserCredential();
      when(() => mockAuth.signInAnonymously()).thenAnswer((_) async => mockCredential);
      when(() => mockCredential.user).thenReturn(mockUser);

      final result = await sut.signInAnonymously();

      expect(result, equals(mockUser));
      verify(() => mockDoc.set(any(), any())).called(1);
    });

    test('returns null when credential has no user', () async {
      final mockCredential = MockUserCredential();
      when(() => mockAuth.signInAnonymously()).thenAnswer((_) async => mockCredential);
      when(() => mockCredential.user).thenReturn(null);

      final result = await sut.signInAnonymously();

      expect(result, isNull);
      verifyNever(() => mockDoc.set(any(), any()));
    });
  });

  group('signInWithEmail', () {
    test('returns user on success', () async {
      final mockCredential = MockUserCredential();
      when(() => mockAuth.signInWithEmailAndPassword(
            email: 'test@example.com',
            password: 'password123',
          )).thenAnswer((_) async => mockCredential);
      when(() => mockCredential.user).thenReturn(mockUser);

      final result = await sut.signInWithEmail('test@example.com', 'password123');

      expect(result, equals(mockUser));
      verify(() => mockDoc.set(any(), any())).called(1);
    });

    test('propagates FirebaseAuthException on failure', () {
      when(() => mockAuth.signInWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(FirebaseAuthException(code: 'user-not-found'));

      expect(
        () => sut.signInWithEmail('bad@example.com', 'wrong'),
        throwsA(isA<FirebaseAuthException>()),
      );
    });
  });

  group('registerWithEmail', () {
    test('creates new account when not anonymous', () async {
      final mockCredential = MockUserCredential();
      when(() => mockAuth.currentUser).thenReturn(null);
      when(() => mockAuth.createUserWithEmailAndPassword(
            email: 'new@example.com',
            password: 'password123',
          )).thenAnswer((_) async => mockCredential);
      when(() => mockCredential.user).thenReturn(mockUser);

      final result = await sut.registerWithEmail('new@example.com', 'password123');

      expect(result, equals(mockUser));
    });

    test('links anonymous account when user is anonymous', () async {
      final anonUser = MockUser();
      final mockCredential = MockUserCredential();
      when(() => anonUser.uid).thenReturn('anon-uid');
      when(() => anonUser.email).thenReturn(null);
      when(() => anonUser.displayName).thenReturn(null);
      when(() => anonUser.isAnonymous).thenReturn(true);
      when(() => mockAuth.currentUser).thenReturn(anonUser);
      when(() => anonUser.linkWithCredential(any())).thenAnswer((_) async => mockCredential);
      when(() => mockCredential.user).thenReturn(mockUser);

      final result = await sut.registerWithEmail('anon@example.com', 'password123');

      expect(result, equals(mockUser));
      verify(() => anonUser.linkWithCredential(any())).called(1);
    });
  });

  group('linkAnonymousToEmail', () {
    late MockUser anonUser;

    setUp(() {
      anonUser = MockUser();
      when(() => anonUser.uid).thenReturn('anon-uid');
      when(() => anonUser.email).thenReturn(null);
      when(() => anonUser.displayName).thenReturn(null);
      when(() => mockAuth.currentUser).thenReturn(anonUser);
    });

    test('links successfully and returns user', () async {
      final mockCredential = MockUserCredential();
      when(() => anonUser.linkWithCredential(any())).thenAnswer((_) async => mockCredential);
      when(() => mockCredential.user).thenReturn(mockUser);

      final result = await sut.linkAnonymousToEmail('user@example.com', 'password123');

      expect(result, equals(mockUser));
    });

    test('falls back to signIn on credential-already-in-use', () async {
      final mockSignInCredential = MockUserCredential();
      when(() => anonUser.linkWithCredential(any()))
          .thenThrow(FirebaseAuthException(code: 'credential-already-in-use'));
      when(() => mockAuth.signInWithEmailAndPassword(
            email: 'user@example.com',
            password: 'password123',
          )).thenAnswer((_) async => mockSignInCredential);
      when(() => mockSignInCredential.user).thenReturn(mockUser);

      final result = await sut.linkAnonymousToEmail('user@example.com', 'password123');

      expect(result, equals(mockUser));
    });

    test('rethrows unrecognised FirebaseAuthException', () {
      when(() => anonUser.linkWithCredential(any()))
          .thenThrow(FirebaseAuthException(code: 'network-request-failed'));

      expect(
        () => sut.linkAnonymousToEmail('user@example.com', 'password123'),
        throwsA(isA<FirebaseAuthException>()),
      );
    });
  });

  group('signOut', () {
    test('delegates to FirebaseAuth.signOut', () async {
      when(() => mockAuth.signOut()).thenAnswer((_) async {});

      await sut.signOut();

      verify(() => mockAuth.signOut()).called(1);
    });
  });
}
