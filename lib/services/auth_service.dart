import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _providedAuth = auth,
        _providedFirestore = firestore;

  final FirebaseAuth? _providedAuth;
  final FirebaseFirestore? _providedFirestore;
  FirebaseAuth get _auth => _providedAuth ?? FirebaseAuth.instance;
  FirebaseFirestore get _firestore => _providedFirestore ?? FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  Future<User?> ensureSignedIn() async {
    if (_auth.currentUser != null) {
      await _ensureUserRecord(_auth.currentUser!);
      return _auth.currentUser;
    }
    final credential = await _auth.signInAnonymously();
    if (credential.user != null) {
      await _ensureUserRecord(credential.user!);
    }
    return credential.user;
  }

  Future<void> _ensureUserRecord(User user) async {
    try {
      await _firestore.collection('users').doc(user.uid).set({
        'email': user.email,
        'name': user.displayName,
        'role': 'free',
        'subscriptionId': null,
        'subscriptionStatus': null,
        'premiumUntil': null,
        'lastActiveAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Keep auth flow resilient in local/dev modes.
    }
  }
}
