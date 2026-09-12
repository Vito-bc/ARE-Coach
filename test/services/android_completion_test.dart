import 'dart:async';

import 'package:are_coach/services/iap_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:mocktail/mocktail.dart';

import '../support/purchase_fakes.dart';

class _Manager extends Mock implements BillingClientManager {}

class _AndroidStore extends InAppPurchaseAndroidPlatform {
  _AndroidStore(BillingClientManager manager, this.events)
    : super(manager: manager);

  final Stream<List<PurchaseDetails>> events;
  BillingResponse result = BillingResponse.error;
  int completions = 0;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => events;

  @override
  Future<BillingResultWrapper> completePurchase(
    PurchaseDetails purchase,
  ) async {
    completions++;
    return BillingResultWrapper(responseCode: result);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android non-OK acknowledgment cannot report success; retry can recover',
    () async {
      registerFallbackValue(FakeUri());
      // Instantiate the generic facade on a platform with no registration, then
      // install a real Android-platform subclass backed entirely by local fakes.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      InAppPurchase.instance;
      final manager = _Manager();
      when(
        () => manager.purchasesUpdatedStream,
      ).thenAnswer((_) => const Stream.empty());
      when(
        () => manager.userChoiceDetailsStream,
      ).thenAnswer((_) => const Stream.empty());
      final events = StreamController<List<PurchaseDetails>>.broadcast();
      final platform = _AndroidStore(manager, events.stream);
      InAppPurchasePlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final account = FakeAccount();
      final client = MockHttpClient();
      when(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('{"valid":true}', 200));
      final service = IAPService(
        account: account,
        httpClient: client,
        validateReceiptUrlOverride: 'https://example.com/validate',
      );
      final updates = <PurchaseDetails>[];
      final errors = <Object>[];
      service.purchaseUpdates.listen(updates.add, onError: errors.add);
      addTearDown(() async {
        service.dispose();
        await events.close();
        await account.events.close();
        debugDefaultTargetPlatformOverride = null;
      });

      await service.initialize();
      final purchase = GooglePlayPurchaseDetails.fromPurchase(
        const PurchaseWrapper(
          orderId: 'order-1',
          packageName: 'test.example',
          purchaseTime: 123,
          purchaseToken: 'token',
          signature: '',
          products: [IAPService.kMonthlyId],
          isAutoRenewing: true,
          originalJson: '{}',
          isAcknowledged: false,
          purchaseState: PurchaseStateWrapper.purchased,
        ),
      ).single;
      events.add([purchase]);
      await Future<void>.delayed(Duration.zero);
      expect(errors.single, isA<IAPError>());
      expect(service.flow.value.phase, PurchasePhase.failed);
      expect(updates, isEmpty);
      expect(platform.completions, 1);

      platform.result = BillingResponse.ok;
      await service.retryPendingPurchases();
      await Future<void>.delayed(Duration.zero);
      expect(platform.completions, 2);
      expect(updates, hasLength(1));
      expect(service.flow.value.phase, PurchasePhase.verified);
      expect(IAPService.androidPurchasesEnabled, isFalse);
      expect(service.canPurchase, isFalse);
      expect(service.canRestore, isTrue);
    },
  );
}
