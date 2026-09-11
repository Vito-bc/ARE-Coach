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

  static const String _envValidateReceiptUrl = String.fromEnvironment(
    'VALIDATE_RECEIPT_URL',
  );

  /// Whether this build is allowed to sell on Android.
  ///
  /// The server can now verify Play purchases, but only once it has been given
  /// a Play service account (`GOOGLE_PLAY_SERVICE_ACCOUNT`). This flag is what
  /// ties the storefront to that configuration: the release workflow sets it
  /// from the `ANDROID_PURCHASES_ENABLED` repo variable, and it defaults to
  /// false so a build that predates the server setup cannot take money.
  static const bool androidPurchasesEnabled = bool.fromEnvironment(
    'ANDROID_PURCHASES_ENABLED',
  );

  /// Whether this platform can complete a purchase end-to-end.
  ///
  /// One rule: **we only sell where the server can verify the sale.** Taking
  /// money and delivering nothing is the worst failure this app has — it is
  /// what closed Android in the first place, back when `validateReceipt` spoke
  /// only to Apple.
  static bool get purchasesSupported => computePurchasesSupported(
    platform: defaultTargetPlatform,
    isWeb: kIsWeb,
    androidEnabled: androidPurchasesEnabled,
    canValidate: !kReleaseMode || _envValidateReceiptUrl.isNotEmpty,
  );

  /// The rule behind [purchasesSupported], pulled out so every combination can
  /// be unit-tested without building for each platform.
  ///
  /// [canValidate] is false in a release build compiled without a
  /// `VALIDATE_RECEIPT_URL`: such a build would complete purchases locally and
  /// never tell the server, leaving the buyer un-upgraded. Debug builds are
  /// allowed through so the flow can be exercised without a deployed backend.
  @visibleForTesting
  static bool computePurchasesSupported({
    required TargetPlatform platform,
    required bool isWeb,
    required bool androidEnabled,
    required bool canValidate,
  }) {
    if (isWeb) return false;
    if (!canValidate) return false;
    switch (platform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return true;
      case TargetPlatform.android:
        return androidEnabled;
      default:
        return false;
    }
  }

  final InAppPurchase _iap;
  final http.Client _httpClient;
  final String? _validateReceiptUrlOverride;

  String get _validateReceiptUrl =>
      _validateReceiptUrlOverride ?? _envValidateReceiptUrl;

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
    if (!purchasesSupported) return [];
    final available = await _iap.isAvailable();
    if (!available) return [];

    final response = await _iap.queryProductDetails(_productIds);
    return response.productDetails;
  }

  Future<void> purchaseSubscription(ProductDetails product) async {
    // Guarded here rather than at the call sites so no screen — present or
    // future — can start a purchase we cannot validate.
    if (!purchasesSupported) {
      throw StateError('Purchases are not available on this platform yet.');
    }
    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> restorePurchases() async {
    if (!purchasesSupported) return;
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

    // An empty endpoint only happens in a debug build — [purchasesSupported]
    // refuses to sell in release without one — so this is the local dev path,
    // not a way for a shipped build to skip verification.
    if (endpoint.isNotEmpty) {
      // `source` is "app_store" on iOS and "google_play" on Android; the server
      // routes on it, and on Android `serverVerificationData` is the Play
      // purchase token rather than a receipt blob.
      final outcome = await _validateWithServer(
        endpoint: endpoint,
        receiptData: purchase.verificationData.serverVerificationData,
        platform: purchase.verificationData.source,
      );
      if (outcome != _Validation.verified) {
        // Either way the purchase is NOT completed. An unacknowledged Play
        // purchase is auto-refunded after three days, and both stores
        // re-deliver an unfinished transaction on the next launch, so the
        // retry below is real rather than a hopeful phrase.
        _purchaseController.addError(
          outcome == _Validation.unavailable
              // Our backend or the store API is down. The buyer did nothing
              // wrong and their money is not stuck, so sending them to support
              // would be both useless and untrue.
              ? IAPError(
                  source: purchase.verificationData.source,
                  code: 'validation_unavailable',
                  message:
                      'We could not confirm your purchase right now — that is '
                      'a problem on our side, not with your payment. Reopen '
                      'the app in a few minutes and it will finish.',
                )
              : IAPError(
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

  /// Asks our server to verify the purchase with the store.
  ///
  /// The gap between [_Validation.rejected] and [_Validation.unavailable] is
  /// the whole point of this returning three states instead of a bool:
  /// `rejected` is the *store* saying this purchase entitles nobody, while
  /// `unavailable` is our own function being unreachable or unconfigured (503)
  /// or the store API being down (502). Collapsing them tells a paying
  /// customer their receipt was bad because our server had a bad day.
  Future<_Validation> _validateWithServer({
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

      // Only an explicit `valid: false` is a verdict on the purchase. A 4xx
      // means this client sent something the server refused — our bug, not a
      // bad receipt — so from the buyer's side it is still an outage.
      if (response.statusCode != 200) return _Validation.unavailable;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['valid'] == true
          ? _Validation.verified
          : _Validation.rejected;
    } catch (_) {
      // No network, a timeout, or a body that isn't the JSON we expect.
      return _Validation.unavailable;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _purchaseController.close();
  }
}

/// What our server said about a purchase.
///
/// [rejected] means the store does not honour it; [unavailable] means we never
/// got an answer. Never treat the second as the first — see
/// `_validateWithServer`.
enum _Validation { verified, rejected, unavailable }
