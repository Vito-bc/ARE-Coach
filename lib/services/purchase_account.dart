import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'purchase_environment.dart';

class PurchaseEntitlement {
  const PurchaseEntitlement({
    required this.active,
    required this.uid,
    required this.environment,
    required this.scope,
    this.expiresAt,
    this.transactionId,
    this.productId,
    this.processedTransaction = false,
  });
  final bool active;
  final String uid;
  final String environment;
  final String scope;
  final DateTime? expiresAt;
  final String? transactionId;
  final String? productId;
  final bool processedTransaction;
}

/// Account operations are captured separately from store events so a response
/// for a previous sign-in cannot be delivered to the next account.
abstract class PurchaseAccount {
  String? get uid;
  Stream<String?> get changes;
  Stream<String> get entitlementChanges;
  Future<Map<String, String>> headers(String uid);
  Future<bool> refreshEntitlement(String uid);
  Future<PurchaseEntitlement> refreshAppleEntitlement(
    String uid, {
    String? transactionId,
    String? productId,
  });
  void notifyEntitlementChanged(String uid);
  void dispose();
}

bool hasActiveSubscription(Map<String, dynamic>? data, DateTime now) {
  final expiry = data?['premiumUntil'];
  return data?['subscriptionStatus'] == 'active' &&
      expiry is Timestamp &&
      expiry.toDate().isAfter(now);
}

class FirebasePurchaseAccount implements PurchaseAccount {
  FirebasePurchaseAccount({PurchaseEnvironment? environment, http.Client? client})
      : environment = environment ?? PurchaseEnvironment.current,
        _client = client ?? http.Client();

  final PurchaseEnvironment environment;
  final http.Client _client;
  final _entitlementEvents = StreamController<String>.broadcast();

  @override
  Stream<String> get entitlementChanges => _entitlementEvents.stream;

  @override
  void notifyEntitlementChanged(String uid) => _entitlementEvents.add(uid);
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
    if (environment.isSandbox) {
      return (await refreshAppleEntitlement(uid)).active;
    }
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    return !snapshot.metadata.isFromCache &&
        !snapshot.metadata.hasPendingWrites &&
        hasActiveSubscription(snapshot.data(), DateTime.now());
  }

  @override
  Future<PurchaseEntitlement> refreshAppleEntitlement(
    String uid, {
    String? transactionId,
    String? productId,
  }) async {
    if (!environment.isSandbox || !environment.isCoherent) {
      throw StateError('Sandbox entitlement source is unavailable');
    }
    final response = await _client.post(
      Uri.parse(environment.validationEndpoint),
      headers: await headers(uid),
      body: jsonEncode({
        'platform': 'app_store',
        'action': 'get_apple_entitlement',
        'appleEnvironment': environment.appleName,
        'firebaseProjectId': environment.firebaseProjectId,
        'entitlementSource': environment.entitlementSource,
        if (transactionId != null) 'transactionId': transactionId,
        if (productId != null) 'productId': productId,
      }),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw StateError('Entitlement unavailable');
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic> ||
        body['uid'] != uid ||
        body['environment'] != environment.appleName ||
        body['firebaseProjectId'] != environment.firebaseProjectId ||
        body['entitlementScope'] != environment.scope ||
        body['active'] is! bool ||
        body['processedTransaction'] is! bool ||
        body['checkedAt'] is! int) {
      throw StateError('Invalid entitlement response');
    }
    final checkedAt = body['checkedAt'] as int;
    if ((DateTime.now().millisecondsSinceEpoch - checkedAt).abs() > 60000) {
      throw StateError('Stale entitlement response');
    }
    final expiry = body['expiresAt'];
    if (expiry != null && expiry is! int) throw StateError('Invalid expiry');
    if (body['active'] == true &&
        (expiry is! int || expiry <= DateTime.now().millisecondsSinceEpoch)) {
      throw StateError('Invalid active entitlement');
    }
    return PurchaseEntitlement(
      active: body['active'] as bool,
      uid: uid,
      environment: body['environment'] as String,
      scope: body['entitlementScope'] as String,
      expiresAt: expiry == null ? null : DateTime.fromMillisecondsSinceEpoch(expiry),
      transactionId: body['transactionId'] as String?,
      productId: body['productId'] as String?,
      processedTransaction: body['processedTransaction'] as bool,
    );
  }

  @override
  void dispose() {
    _entitlementEvents.close();
    _client.close();
  }
}
