import 'dart:async';
import 'dart:convert';

import 'package:are_coach/services/iap_service.dart';
import 'package:are_coach/services/purchase_environment.dart';
import 'package:are_coach/screens/paywall_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:mocktail/mocktail.dart';

import '../support/purchase_fakes.dart';

const environment = PurchaseEnvironment(
  apple: ApplePurchaseEnvironment.sandbox,
  firebaseEnvironment: 'Sandbox',
  entitlementSource: 'apple_sandbox',
  firebaseProjectId: 'are-coach-sandbox',
  validationEndpoint:
      'https://us-central1-are-coach-sandbox.cloudfunctions.net/validateReceipt',
  firebaseApiKey: 'key',
  firebaseAppId: 'app',
  firebaseMessagingSenderId: 'sender',
  firebaseStorageBucket: 'bucket',
);

void main() {
  setUpAll(() {
    registerFallbackValue(FakePurchaseDetails());
    registerFallbackValue(PurchaseParam(productDetails: ProductDetails(
      id: IAPService.kMonthlyId, title: '', description: '', price: '',
      rawPrice: 0, currencyCode: 'USD')));
  });

  test('sandbox purchase requires matching validation and fresh transaction proof', () async {
    final store = MockInAppPurchase();
    final account = FakeAccount();
    final events = StreamController<List<PurchaseDetails>>.broadcast();
    final bodies = <Map<String, dynamic>>[];
    when(() => store.purchaseStream).thenAnswer((_) => events.stream);
    when(() => store.completePurchase(any())).thenAnswer((_) async {});
    final service = IAPService(
      iap: store,
      account: account,
      environment: environment,
      httpClient: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({
          ...jsonDecode(appleResponse()) as Map<String, dynamic>,
          'environment': 'Sandbox',
          'firebaseProjectId': 'are-coach-sandbox',
          'entitlementScope': 'sandbox',
        }), 200);
      }),
    );
    service.purchaseUpdates.listen((_) {}, onError: (_) {});
    await service.initialize();
    final transaction = SK2PurchaseDetails(
      productID: IAPService.kMonthlyId,
      purchaseID: '123',
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: 'signed.fixture.jws',
        source: 'app_store',
      ),
      transactionDate: '1',
      status: PurchaseStatus.purchased,
    );
    events.add([transaction]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    verify(() => store.completePurchase(transaction)).called(1);
    expect(service.flow.value.phase, PurchasePhase.verified);
    expect(bodies.single['appleEnvironment'], 'Sandbox');
    expect(bodies.single['firebaseProjectId'], 'are-coach-sandbox');
    expect(account.refreshed, ['user-a']);
    service.dispose();
    await events.close();
    account.dispose();
  });

  test('mixed configuration blocks checkout before StoreKit', () async {
    final store = MockInAppPurchase();
    final account = FakeAccount();
    when(() => store.purchaseStream).thenAnswer((_) => const Stream.empty());
    final service = IAPService(
      iap: store,
      account: account,
      environment: PurchaseEnvironment(
        apple: ApplePurchaseEnvironment.sandbox,
        firebaseEnvironment: 'Production',
        entitlementSource: 'apple_sandbox',
        firebaseProjectId: 'are-coach-sandbox',
        validationEndpoint: environment.validationEndpoint,
        firebaseApiKey: 'key', firebaseAppId: 'app',
        firebaseMessagingSenderId: 'sender', firebaseStorageBucket: 'bucket',
      ),
      httpClient: MockClient((_) async => throw StateError('must not run')),
    );
    final product = ProductDetails(id: IAPService.kMonthlyId, title: '',
      description: '', price: '', rawPrice: 0, currencyCode: 'USD');
    await expectLater(service.purchaseSubscription(product),
      throwsA(isA<IAPError>().having((e) => e.code, 'code',
        'purchase_configuration_invalid')));
    verifyNever(() => store.buyNonConsumable(
      purchaseParam: any(named: 'purchaseParam')));
    service.dispose();
    account.dispose();
  });

  test('production build rejects otherwise valid sandbox proof', () async {
    final store = MockInAppPurchase();
    final account = FakeAccount();
    final events = StreamController<List<PurchaseDetails>>.broadcast();
    when(() => store.purchaseStream).thenAnswer((_) => events.stream);
    when(() => store.completePurchase(any())).thenAnswer((_) async {});
    const production = PurchaseEnvironment(
      apple: ApplePurchaseEnvironment.production,
      firebaseEnvironment: 'Production', entitlementSource: 'production',
      firebaseProjectId: PurchaseEnvironment.productionProjectId,
      validationEndpoint:
        'https://us-central1-architect-study-app.cloudfunctions.net/validateReceipt');
    final service = IAPService(iap: store, account: account,
      environment: production,
      httpClient: MockClient((_) async => http.Response(jsonEncode({
        ...jsonDecode(appleResponse()) as Map<String, dynamic>,
        'environment': 'Sandbox', 'entitlementScope': 'sandbox',
      }), 200)));
    service.purchaseUpdates.listen((_) {}, onError: (_) {});
    await service.initialize();
    events.add([SK2PurchaseDetails(productID: IAPService.kMonthlyId,
      purchaseID: '123', verificationData: PurchaseVerificationData(
        localVerificationData: '', serverVerificationData: 'a.b.c',
        source: 'app_store'), transactionDate: '1',
      status: PurchaseStatus.purchased)]);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    verifyNever(() => store.completePurchase(any()));
    expect(service.flow.value.phase, PurchasePhase.failed);
    service.dispose(); await events.close(); account.dispose();
  });

  test('empty sandbox Restore finishes with an actionable empty state', () async {
    final store = MockInAppPurchase();
    final account = FakeAccount();
    when(() => store.purchaseStream).thenAnswer((_) => const Stream.empty());
    when(() => store.restorePurchases()).thenAnswer((_) async {});
    final service = IAPService(iap: store, account: account,
      environment: environment, httpClient: MockClient((_) async =>
        throw StateError('no validation expected')));
    service.purchaseUpdates.listen((_) {}, onError: (_) {});
    await service.initialize();
    await service.restorePurchases();
    expect(service.flow.value.phase, PurchasePhase.empty);
    expect(service.canStartPurchase, isTrue);
    service.dispose(); account.dispose();
  });

  test('sandbox response for the previous account cannot complete after a switch', () async {
    final store = MockInAppPurchase();
    final account = FakeAccount();
    final events = StreamController<List<PurchaseDetails>>.broadcast();
    final response = Completer<http.Response>();
    when(() => store.purchaseStream).thenAnswer((_) => events.stream);
    when(() => store.completePurchase(any())).thenAnswer((_) async {});
    final service = IAPService(iap: store, account: account,
      environment: environment, httpClient: MockClient((_) => response.future));
    service.purchaseUpdates.listen((_) {}, onError: (_) {});
    await service.initialize();
    final transaction = SK2PurchaseDetails(productID: IAPService.kMonthlyId,
      purchaseID: '123', verificationData: PurchaseVerificationData(
        localVerificationData: '', serverVerificationData: 'a.b.c',
        source: 'app_store'), transactionDate: '1',
      status: PurchaseStatus.purchased);
    events.add([transaction]);
    await Future<void>.delayed(Duration.zero);
    account.signIn('user-b');
    response.complete(http.Response(jsonEncode({
      ...jsonDecode(appleResponse()) as Map<String, dynamic>,
      'environment': 'Sandbox', 'firebaseProjectId': 'are-coach-sandbox',
      'entitlementScope': 'sandbox',
    }), 200));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    verifyNever(() => store.completePurchase(any()));
    expect(account.refreshed, isEmpty);
    account.signIn('user-a');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    verify(() => store.completePurchase(transaction)).called(1);
    service.dispose(); await events.close(); account.dispose();
  });

  testWidgets('real paywall completes sandbox purchase and reports success',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final store = MockInAppPurchase();
    final account = FakeAccount();
    final events = StreamController<List<PurchaseDetails>>.broadcast();
    final product = ProductDetails(id: IAPService.kMonthlyId, title: 'Monthly',
      description: 'Monthly', price: r'$10', rawPrice: 10,
      currencyCode: 'USD');
    when(() => store.purchaseStream).thenAnswer((_) => events.stream);
    when(() => store.isAvailable()).thenAnswer((_) async => true);
    when(() => store.queryProductDetails(any())).thenAnswer((_) async =>
      ProductDetailsResponse(productDetails: [product], notFoundIDs: []));
    when(() => store.buyNonConsumable(
      purchaseParam: any(named: 'purchaseParam'))).thenAnswer((_) async => true);
    when(() => store.completePurchase(any())).thenAnswer((_) async {});
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['action'] == 'prepare_apple_purchase') {
        return http.Response(jsonEncode({
          'uid': 'user-a',
          'appAccountToken': '00112233-4455-4677-8899-aabbccddeeff',
          'environment': 'Sandbox', 'firebaseProjectId': 'are-coach-sandbox',
          'entitlementScope': 'sandbox',
        }), 200);
      }
      return http.Response(jsonEncode({
        ...jsonDecode(appleResponse()) as Map<String, dynamic>,
        'environment': 'Sandbox', 'firebaseProjectId': 'are-coach-sandbox',
        'entitlementScope': 'sandbox',
      }), 200);
    });
    final service = IAPService(iap: store, account: account,
      environment: environment, httpClient: client);
    service.purchaseUpdates.listen((_) {}, onError: (_) {});
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PaywallScreen(iapService: service),
                  ),
                ),
                child: const Text('Open premium'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open premium'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subscribe Now'));
    await tester.pumpAndSettle();
    events.add([SK2PurchaseDetails(productID: IAPService.kMonthlyId,
      purchaseID: '123', verificationData: PurchaseVerificationData(
        localVerificationData: '', serverVerificationData: 'a.b.c',
        source: 'app_store'), transactionDate: '1',
      status: PurchaseStatus.purchased)]);
    await tester.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsNothing);
    expect(find.text('Premium access confirmed.'), findsOneWidget);
    verify(() => store.completePurchase(any())).called(1);
    await tester.pumpWidget(const SizedBox());
    service.dispose(); await events.close(); account.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
