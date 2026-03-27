import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

class IAPService {
  static const String kMonthlyId = 'are_coach_monthly';
  static const String kYearlyId = 'are_coach_yearly';

  static const Set<String> _productIds = {kMonthlyId, kYearlyId};

  final InAppPurchase _iap = InAppPurchase.instance;

  final StreamController<PurchaseDetails> _purchaseController =
      StreamController<PurchaseDetails>.broadcast();

  Stream<PurchaseDetails> get purchaseUpdates => _purchaseController.stream;

  StreamSubscription<List<PurchaseDetails>>? _subscription;

  Future<void> initialize() async {
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
        if (purchase.pendingCompletePurchase) {
          _iap.completePurchase(purchase);
        }
        _purchaseController.add(purchase);
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

  void dispose() {
    _subscription?.cancel();
    _purchaseController.close();
  }
}
