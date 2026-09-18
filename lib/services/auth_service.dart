import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../core/legal_versions.dart';

typedef AppleCredentialRequest =
    Future<({AuthorizationCredentialAppleID credential, String rawNonce})>
    Function();

/// Thrown when a NEW user document could not be created with its Terms/
/// Privacy assent fields. Deliberately not swallowed the way other
/// `_ensureUserRecord` failures are: an authenticated user with no assent
/// record is exactly what this mechanism exists to prevent, so callers must
/// see this and must not treat account creation as fully successful.
class AssentRecordException implements Exception {
  const AssentRecordException(this.cause);

  final Object cause;

  @override
  String toString() => 'Could not record Terms/Privacy assent: $cause';
}

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

  /// [assent] is required because this is a guest-account-creation entry
  /// point when there is no current user yet -- see registerScreen/
  /// loginScreen's "Continue as Guest". When a session already exists this
  /// just refreshes/no-ops the existing record; the fresh assent is unused
  /// in that branch but still available should the document ever need
  /// (re)creating.
  Future<User?> ensureSignedIn({required TermsAssent assent}) async {
    if (_auth.currentUser != null) {
      await _ensureUserRecord(_auth.currentUser!, assent: assent);
      return _auth.currentUser;
    }
    return signInAnonymously(assent: assent);
  }

  Future<User?> signInAnonymously({required TermsAssent assent}) async {
    final credential = await _auth.signInAnonymously();
    if (credential.user != null) {
      await _ensureUserRecord(credential.user!, assent: assent);
    }
    return credential.user;
  }

  /// Returning sign-in of an existing account. No assent parameter: this
  /// path never creates an account, so there is no fresh checkbox to record.
  /// If the user's document is somehow missing (should not happen in
  /// practice), `_ensureUserRecord` skips creating one rather than
  /// fabricating consent that was never given on this screen.
  Future<User?> signInWithEmail(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (credential.user != null) await _ensureUserRecord(credential.user!);
    return credential.user;
  }

  Future<User?> registerWithEmail(
    String email,
    String password, {
    required TermsAssent assent,
  }) async {
    final isAnon = _auth.currentUser?.isAnonymous ?? false;
    if (isAnon) return linkAnonymousToEmail(email, password, assent: assent);
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (credential.user != null) {
      await _ensureUserRecord(credential.user!, assent: assent);
    }
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

  Future<User?> signInWithApple({required TermsAssent assent}) async {
    final isAnon = _auth.currentUser?.isAnonymous ?? false;
    if (isAnon) return linkAnonymousToApple(assent: assent);
    final (:credential, :rawNonce) =
        await (_appleCredentialRequest ?? _requestAppleCredential)();
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: credential.identityToken,
      rawNonce: rawNonce,
    );
    final result = await _auth.signInWithCredential(oauthCredential);
    if (result.user != null) {
      await _ensureUserRecord(result.user!, assent: assent);
    }
    return result.user;
  }

  Future<User?> linkAnonymousToApple({required TermsAssent assent}) async {
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
      if (result.user != null) {
        await _ensureUserRecord(result.user!, assent: assent);
      }
      return result.user;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        final result = await _auth.signInWithCredential(oauthCredential);
        if (result.user != null) {
          await _ensureUserRecord(result.user!, assent: assent);
        }
        return result.user;
      }
      rethrow;
    }
  }

  Future<User?> linkAnonymousToEmail(
    String email,
    String password, {
    required TermsAssent assent,
  }) async {
    final emailCredential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    try {
      final result = await _auth.currentUser!.linkWithCredential(
        emailCredential,
      );
      if (result.user != null) {
        await _ensureUserRecord(result.user!, assent: assent);
      }
      await _sendVerificationIfNeeded(result.user);
      return result.user;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' ||
          e.code == 'email-already-in-use') {
        final result = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        if (result.user != null) {
          await _ensureUserRecord(result.user!, assent: assent);
        }
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

  /// Creates the user's Firestore document on first sign-in only, and — the
  /// entire legal point of this method — records their Terms/Privacy assent
  /// in that same write. [assent] is null only for paths that can never
  /// legitimately create an account (see [signInWithEmail]).
  Future<void> _ensureUserRecord(User user, {TermsAssent? assent}) async {
    final doc = _firestore.collection('users').doc(user.uid);

    bool exists;
    try {
      exists = (await doc.get()).exists;
    } catch (error) {
      // Can't tell whether this is a genuinely new or a returning user from
      // a failed existence check. Assume returning: a transient read error
      // must never block or duplicate account creation for an existing
      // user. (Unlike the write below, there is no assent at risk here —
      // nothing has been written yet.)
      debugPrint('AuthService._ensureUserRecord: existence check failed: $error');
      return;
    }

    // Returning user: there is nothing the client may write here.
    // firestore.rules makes `email` and `lastActiveAt` server-owned (only
    // `name` and `targetExamDate` are user-editable), and the Cloud Functions
    // already refresh `lastActiveAt` on every request. The old code wrote
    // them anyway, so every returning login was rejected by the rules — and
    // the failure was swallowed by a bare `catch (_)`, so nobody ever saw it.
    // Re-consent (comparing the stored *AcceptedVersion against
    // kTermsVersion/kPrivacyVersion) is intentionally not checked here — see
    // lib/core/legal_versions.dart.
    if (exists) return;

    if (assent == null) {
      // No fresh assent is available on this path (a returning-login call
      // whose Firestore document is unexpectedly missing). Recording assent
      // is this method's entire reason for existing; writing a user document
      // without it would be worse than not writing one at all, since it
      // would look like a valid account with no record anyone ever agreed to
      // the Terms or Privacy Policy. Skip creation rather than fabricate
      // consent that was never given on this screen.
      debugPrint(
        'AuthService._ensureUserRecord: no document for ${user.uid} and no '
        'assent available to record; skipping creation.',
      );
      return;
    }

    try {
      await doc.set({
        'email': user.email,
        'name': user.displayName,
        'role': 'free',
        'createdAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
        'termsAcceptedVersion': assent.termsVersion,
        'termsAcceptedAt': FieldValue.serverTimestamp(),
        'privacyAcceptedVersion': assent.privacyVersion,
        'privacyAcceptedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      // Unlike the read above, this failure must surface: an unrecorded
      // assent is the one thing this whole mechanism exists to prevent, so
      // it must never be swallowed the way the old bare `catch (_)` did.
      throw AssentRecordException(error);
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
