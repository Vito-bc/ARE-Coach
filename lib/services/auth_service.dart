import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService({FirebaseAuth? auth}) : _providedAuth = auth;

  final FirebaseAuth? _providedAuth;
  FirebaseAuth get _auth => _providedAuth ?? FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  Future<User?> ensureSignedIn() async {
    if (_auth.currentUser != null) {
      return _auth.currentUser;
    }
    final credential = await _auth.signInAnonymously();
    return credential.user;
  }
}
