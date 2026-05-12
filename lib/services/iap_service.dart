import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';

class IAPService {
  IAPService({
    @visibleForTesting InAppPurchase? iap,
    @visibleForTesting http.Client? httpClient,
    @visibleForTesting String? validateReceiptUrlOverride,
  }) : _iap = iap ?? InAppPurchase.instance,
       _httpClient = httpClient ?? http.Client(),
       _validateReceiptUrlOverride = validateReceiptUrlOverride;

  static const String kMonthlyId = 'are_coach_monthly';
  static const String kYearlyId = 'are_coach_yearly';

  static const Set<String> _productIds = {kMonthlyId, kYearlyId};

  final InAppPurchase _iap;
  final http.Client _httpClient;
  final String? _validateReceiptUrlOverride;

  String get _validateReceiptUrl =>
      _validateReceiptUrlOverride ??
      const String.fromEnvironment('VALIDATE_RECEIPT_URL');

  final StreamController<PurchaseDetails> _purchaseController =
      StreamController<PurchaseDetails>.broadcast();

  Stream<PurchaseDetails> get purchaseUpdates => _purchaseController.stream;

  StreamSubscription<List<PurchaseDetails>>? _subscription;

  Future<void> initialize() async {
    if (_subscription != null) return;
    final available = await _iap.isAvailable();
    if (!available) return;

    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (Object error) {
        _purchaseController.addError(error);
      },
    );
  }

  Future<List<ProductDetails>> loadProducts() async {
    final available = await _iap.isAvailable();
    if (!available) return [];

    final response = await _iap.queryProductDetails(_productIds);
    return response.productDetails;
  }

  Future<void> purchaseSubscription(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        _validateAndComplete(purchase);
      } else if (purchase.status == PurchaseStatus.error) {
        _purchaseController.addError(
          purchase.error ??
              IAPError(
                source: 'app_store',
                code: 'purchase_error',
                message: 'An unknown purchase error occurred.',
              ),
        );
      } else {
        _purchaseController.add(purchase);
      }
    }
  }

  Future<void> _validateAndComplete(PurchaseDetails purchase) async {
    final endpoint = _validateReceiptUrl;

    if (endpoint.isNotEmpty) {
      final valid = await _validateWithServer(
        endpoint: endpoint,
        receiptData: purchase.verificationData.serverVerificationData,
        platform: purchase.verificationData.source,
      );
      if (!valid) {
        _purchaseController.addError(
          IAPError(
            source: purchase.verificationData.source,
            code: 'receipt_invalid',
            message: 'Receipt could not be verified. Contact support.',
          ),
        );
        return;
      }
    }

    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
    _purchaseController.add(purchase);
  }

  Future<bool> _validateWithServer({
    required String endpoint,
    required String receiptData,
    required String platform,
  }) async {
    try {
      String? idToken;
      String? appCheckToken;
      try {
        idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
      try {
        appCheckToken = await FirebaseAppCheck.instance.getToken();
      } catch (_) {}

      final headers = <String, String>{'Content-Type': 'application/json'};
      if (idToken != null) headers['Authorization'] = 'Bearer $idToken';
      if (appCheckToken != null) headers['X-Firebase-AppCheck'] = appCheckToken;

      final response = await _httpClient.post(
        Uri.parse(endpoint),
        headers: headers,
        body: jsonEncode({'receiptData': receiptData, 'platform': platform}),
      );

      if (response.statusCode != 200) return false;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['valid'] == true;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _purchaseController.close();
  }
}
