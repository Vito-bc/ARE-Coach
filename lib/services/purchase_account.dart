import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Account operations are captured separately from store events so a response
/// for a previous sign-in cannot be delivered to the next account.
abstract class PurchaseAccount {
  String? get uid;
  Stream<String?> get changes;
  Future<Map<String, String>> headers(String uid);
  Future<bool> refreshEntitlement(String uid);
}

bool hasActiveSubscription(Map<String, dynamic>? data, DateTime now) {
  final expiry = data?['premiumUntil'];
  return data?['subscriptionStatus'] == 'active' &&
      expiry is Timestamp &&
      expiry.toDate().isAfter(now);
}

class FirebasePurchaseAccount implements PurchaseAccount {
  @override
  String? get uid {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<String?> get changes {
    try {
      return FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);
    } catch (_) {
      return Stream.value(null);
    }
  }

  @override
  Future<Map<String, String>> headers(String uid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid) throw StateError('Account changed');
    final token = await user.getIdToken();
    if (token == null) throw StateError('Sign in required');
    final appCheck = await FirebaseAppCheck.instance.getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      if (appCheck != null) 'X-Firebase-AppCheck': appCheck,
    };
  }

  @override
  Future<bool> refreshEntitlement(String uid) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    return !snapshot.metadata.isFromCache &&
        !snapshot.metadata.hasPendingWrites &&
        hasActiveSubscription(snapshot.data(), DateTime.now());
  }
}
