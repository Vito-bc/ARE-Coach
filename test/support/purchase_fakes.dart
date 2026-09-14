// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'dart:convert';
import 'package:are_coach/services/purchase_account.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mocktail/mocktail.dart';

class MockInAppPurchase extends Mock implements InAppPurchase {}

class MockHttpClient extends Mock implements http.Client {}

class MockPurchaseDetails extends Mock implements PurchaseDetails {}

class MockPurchaseVerificationData extends Mock
    implements PurchaseVerificationData {}

class FakeAccount implements PurchaseAccount {
  @override
  String? uid = 'user-a';
  final events = StreamController<String?>.broadcast();
  @override
  Stream<String?> get changes => events.stream;
  final entitlementEvents = StreamController<String>.broadcast();
  @override
  Stream<String> get entitlementChanges => entitlementEvents.stream;
  bool entitled = true;
  PurchaseEntitlement? entitlementProof;
  Object? entitlementError;
  final refreshed = <String>[];
  @override
  Future<Map<String, String>> headers(String uid) async => {
    'Authorization': 'Bearer $uid',
  };
  @override
  Future<bool> refreshEntitlement(String uid) async {
    refreshed.add(uid);
    return entitled;
  }
  @override
  Future<PurchaseEntitlement> refreshAppleEntitlement(
    String uid, {
    String? transactionId,
    String? productId,
  }) async {
    refreshed.add(uid);
    if (entitlementError != null) throw entitlementError!;
    return entitlementProof ?? PurchaseEntitlement(
      active: entitled,
      uid: uid,
      environment: 'Sandbox',
      scope: 'sandbox',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
      transactionId: transactionId,
      productId: productId,
      processedTransaction: transactionId != null,
    );
  }
  @override
  void notifyEntitlementChanged(String uid) => entitlementEvents.add(uid);
  @override
  void dispose() {
    events.close();
    entitlementEvents.close();
  }

  void signIn(String? value) {
    uid = value;
    events.add(value);
  }
}

class FakeUri extends Fake implements Uri {}

class FakePurchaseDetails extends Fake implements PurchaseDetails {}

String appleResponse({
  String uid = 'user-a',
  String transactionId = '123',
  String productId = 'are_coach_monthly',
  bool valid = true,
}) => jsonEncode({
  'valid': valid,
  'outcome': valid ? 'verified' : 'not_entitled',
  'uid': uid,
  'transactionId': transactionId,
  'originalTransactionId': '100',
  'productId': productId,
  'environment': 'Production',
  'firebaseProjectId': 'architect-study-app',
  'entitlementScope': 'production',
  'expiresAt': DateTime.now()
      .add(const Duration(days: 30))
      .millisecondsSinceEpoch,
  'transactionFinalization': valid ? 'verified_transaction' : 'not_safe',
  if (!valid) 'reason': 'expired',
});
