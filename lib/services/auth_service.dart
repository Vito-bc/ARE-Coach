import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

typedef AppleCredentialRequest =
    Future<({AuthorizationCredentialAppleID credential, String rawNonce})>
    Function();

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    @visibleForTesting AppleCredentialRequest? appleCredentialRequest,
    @visibleForTesting http.Client? httpClient,
    @visibleForTesting String? deleteAccountUrlOverride,
  }) : _providedAuth = auth,
       _providedFirestore = firestore,
       _appleCredentialRequest = appleCredentialRequest,
       _httpClient = httpClient,
       _deleteAccountUrlOverride = deleteAccountUrlOverride;

  final FirebaseAuth? _providedAuth;
  final FirebaseFirestore? _providedFirestore;
  final AppleCredentialRequest? _appleCredentialRequest;
  final http.Client? _httpClient;
  final String? _deleteAccountUrlOverride;

  http.Client get _http => _httpClient ?? http.Client();

  String get _deleteAccountUrl =>
      _deleteAccountUrlOverride ??
      const String.fromEnvironment('DELETE_ACCOUNT_URL');

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
    await _sendVerificationIfNeeded(credential.user);
    return credential.user;
  }

  /// Sends a verification email for a freshly created email/password account.
  /// Non-fatal — the user can resend it later from the Profile screen.
  Future<void> _sendVerificationIfNeeded(User? user) async {
    if (user == null || user.emailVerified) return;
    try {
      await user.sendEmailVerification();
    } catch (_) {
      // Ignore: verification is best-effort and retryable from Profile.
    }
  }

  Future<User?> signInWithApple() async {
    final isAnon = _auth.currentUser?.isAnonymous ?? false;
    if (isAnon) return linkAnonymousToApple();
    final (:credential, :rawNonce) =
        await (_appleCredentialRequest ?? _requestAppleCredential)();
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: credential.identityToken,
      rawNonce: rawNonce,
    );
    final result = await _auth.signInWithCredential(oauthCredential);
    if (result.user != null) await _ensureUserRecord(result.user!);
    return result.user;
  }

  Future<User?> linkAnonymousToApple() async {
    final (:credential, :rawNonce) =
        await (_appleCredentialRequest ?? _requestAppleCredential)();
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: credential.identityToken,
      rawNonce: rawNonce,
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
      await _sendVerificationIfNeeded(result.user);
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

  /// Whether the signed-in user authenticated with email/password.
  bool get isPasswordUser =>
      _auth.currentUser?.providerData
          .any((p) => p.providerId == 'password') ??
      false;

  /// Whether the signed-in user's email address has been verified.
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  /// True when an email/password user still needs to verify their address —
  /// drives the "verify email" prompt on the Profile screen.
  bool get needsEmailVerification => isPasswordUser && !isEmailVerified;

  /// (Re)sends the verification email to the current user.
  Future<void> sendEmailVerification() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  /// Refreshes the cached user so [isEmailVerified] reflects the latest state.
  Future<void> reloadUser() async {
    await _auth.currentUser?.reload();
  }

  /// Permanently deletes the signed-in user's account and all associated data.
  ///
  /// Calls the `deleteAccount` Cloud Function, which removes the user's
  /// Firestore data (which the security rules forbid the client from deleting
  /// directly) and the Firebase Auth user using admin privileges. On success
  /// the local session is cleared. Required by App Store Guideline 5.1.1(v).
  ///
  /// If no `DELETE_ACCOUNT_URL` is configured (e.g. local/dev), it falls back
  /// to a client-side auth-only deletion, which may throw
  /// `requires-recent-login` and does not remove server data.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No signed-in user to delete.');
    }

    final endpoint = _deleteAccountUrl;
    if (endpoint.isEmpty) {
      // Dev/local fallback: delete the auth user only (no server data wipe).
      await user.delete();
      return;
    }

    // Force-refresh the ID token so the server receives a fresh credential.
    final idToken = await user.getIdToken(true);
    String? appCheckToken;
    try {
      appCheckToken = await FirebaseAppCheck.instance.getToken();
    } catch (_) {}

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';
    if (appCheckToken != null) headers['X-Firebase-AppCheck'] = appCheckToken;

    final response = await _http.post(Uri.parse(endpoint), headers: headers);
    if (response.statusCode != 200) {
      throw Exception(
        'Account deletion failed (${response.statusCode}). Please try again.',
      );
    }

    // The server deleted the auth user; clear any local session state.
    await _auth.signOut();
  }

  Future<void> _ensureUserRecord(User user) async {
    final doc = _firestore.collection('users').doc(user.uid);
    try {
      final snapshot = await doc.get();

      // Returning user: there is nothing the client may write here.
      // firestore.rules makes `email` and `lastActiveAt` server-owned (only
      // `name` and `targetExamDate` are user-editable), and the Cloud Functions
      // already refresh `lastActiveAt` on every request. The old code wrote
      // them anyway, so every returning login was rejected by the rules — and
      // the failure was swallowed by a bare `catch (_)`, so nobody ever saw it.
      if (snapshot.exists) return;

      await doc.set({
        'email': user.email,
        'name': user.displayName,
        'role': 'free',
        'createdAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      // Still non-fatal — a failure here must not block sign-in — but it is no
      // longer invisible the way the old bare `catch (_)` made it.
      debugPrint('AuthService._ensureUserRecord failed: $error');
    }
  }

  Future<({AuthorizationCredentialAppleID credential, String rawNonce})>
  _requestAppleCredential() async {
    final rawNonce = _generateNonce();
    final hashed = _sha256ofString(rawNonce);
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashed,
    );
    return (credential: credential, rawNonce: rawNonce);
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
