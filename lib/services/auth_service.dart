import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _providedAuth = auth,
      _providedFirestore = firestore;

  final FirebaseAuth? _providedAuth;
  final FirebaseFirestore? _providedFirestore;
  FirebaseAuth get _auth => _providedAuth ?? FirebaseAuth.instance;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get userStream => _auth.authStateChanges();

  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? true;

  Future<User?> ensureSignedIn() async {
    if (_auth.currentUser != null) {
      await _ensureUserRecord(_auth.currentUser!);
      return _auth.currentUser;
    }
    return signInAnonymously();
  }

  Future<User?> signInAnonymously() async {
    final credential = await _auth.signInAnonymously();
    if (credential.user != null) await _ensureUserRecord(credential.user!);
    return credential.user;
  }

  Future<User?> signInWithEmail(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (credential.user != null) await _ensureUserRecord(credential.user!);
    return credential.user;
  }

  Future<User?> registerWithEmail(String email, String password) async {
    final isAnon = _auth.currentUser?.isAnonymous ?? false;
    if (isAnon) return linkAnonymousToEmail(email, password);
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (credential.user != null) await _ensureUserRecord(credential.user!);
    return credential.user;
  }

  Future<User?> signInWithApple() async {
    final isAnon = _auth.currentUser?.isAnonymous ?? false;
    if (isAnon) return linkAnonymousToApple();
    final appleCredential = await _requestAppleCredential();
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: appleCredential.authorizationCode,
    );
    final result = await _auth.signInWithCredential(oauthCredential);
    if (result.user != null) await _ensureUserRecord(result.user!);
    return result.user;
  }

  Future<User?> linkAnonymousToApple() async {
    final appleCredential = await _requestAppleCredential();
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: appleCredential.authorizationCode,
    );
    try {
      final result = await _auth.currentUser!.linkWithCredential(
        oauthCredential,
      );
      if (result.user != null) await _ensureUserRecord(result.user!);
      return result.user;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        final result = await _auth.signInWithCredential(oauthCredential);
        if (result.user != null) await _ensureUserRecord(result.user!);
        return result.user;
      }
      rethrow;
    }
  }

  Future<User?> linkAnonymousToEmail(String email, String password) async {
    final emailCredential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    try {
      final result = await _auth.currentUser!.linkWithCredential(
        emailCredential,
      );
      if (result.user != null) await _ensureUserRecord(result.user!);
      return result.user;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' ||
          e.code == 'email-already-in-use') {
        final result = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        if (result.user != null) await _ensureUserRecord(result.user!);
        return result.user;
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<void> _ensureUserRecord(User user) async {
    try {
      final doc = _firestore.collection('users').doc(user.uid);
      final snapshot = await doc.get();
      final data = <String, dynamic>{
        'email': user.email,
        'name': user.displayName,
        'lastActiveAt': FieldValue.serverTimestamp(),
      };
      if (!snapshot.exists) {
        data['role'] = 'free';
        data['createdAt'] = FieldValue.serverTimestamp();
      }

      await doc.set(data, SetOptions(merge: true));
    } catch (_) {
      // Keep auth flow resilient in local/dev modes.
    }
  }

  Future<AuthorizationCredentialAppleID> _requestAppleCredential() async {
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);
    return SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
