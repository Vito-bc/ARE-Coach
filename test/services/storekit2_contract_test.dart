import 'dart:async';
import 'dart:convert';

import 'package:are_coach/services/iap_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:mocktail/mocktail.dart';

import '../support/purchase_fakes.dart';

void main() {
  late MockInAppPurchase store;
  late FakeAccount account;
  late StreamController<List<PurchaseDetails>> events;
  late IAPService service;
  late Future<http.Response> Function(http.Request) respond;
  final requests = <http.Request>[];
  final product = ProductDetails(
    id: IAPService.kMonthlyId,
    title: 'Monthly',
    description: 'Monthly',
    price: '\$10',
    rawPrice: 10,
    currencyCode: 'USD',
  );
  const token = '00112233-4455-4677-8899-aabbccddeeff';
  SK2PurchaseDetails purchase() => SK2PurchaseDetails(
    productID: product.id,
    purchaseID: '123',
    verificationData: PurchaseVerificationData(
      localVerificationData: '',
      serverVerificationData: 'signed.fixture.jws',
      source: 'app_store',
    ),
    transactionDate: '123',
    status: PurchaseStatus.purchased,
  );
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  setUpAll(() {
    registerFallbackValue(FakePurchaseDetails());
    registerFallbackValue(PurchaseParam(productDetails: product));
  });
  setUp(() async {
    requests.clear();
    account = FakeAccount();
    store = MockInAppPurchase();
    events = StreamController<List<PurchaseDetails>>.broadcast();
    when(() => store.purchaseStream).thenAnswer((_) => events.stream);
    when(() => store.isAvailable()).thenAnswer((_) async => true);
    when(() => store.completePurchase(any())).thenAnswer((_) async {});
    when(() => store.restorePurchases()).thenAnswer((_) async {});
    when(
      () => store.buyNonConsumable(purchaseParam: any(named: 'purchaseParam')),
    ).thenAnswer((_) async => true);
    respond = (_) async => http.Response(appleResponse(), 200);
    service = IAPService(
      iap: store,
      account: account,
      validateReceiptUrlOverride: 'https://example.com/validate',
      httpClient: MockClient((request) {
        requests.add(request);
        return respond(request);
      }),
    );
    service.purchaseUpdates.listen((_) {}, onError: (_) {});
    await service.initialize();
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    service.dispose();
    await events.close();
    await account.events.close();
  });
  test(
    'server UUID reaches the actual PurchaseParam used by StoreKit adapter',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      respond = (request) async {
        expect(jsonDecode(request.body), {
          'platform': 'app_store',
          'action': 'prepare_apple_purchase',
        });
        expect(request.headers['authorization'], 'Bearer user-a');
        return http.Response(
          jsonEncode({
            'uid': 'user-a',
            'appAccountToken': token,
            'environment': 'Production',
          }),
          200,
        );
      };
      await service.purchaseSubscription(product);
      final param =
          verify(
                () => store.buyNonConsumable(
                  purchaseParam: captureAny(named: 'purchaseParam'),
                ),
              ).captured.single
              as PurchaseParam;
      expect(param.applicationUserName, token);
    },
  );
  test(
    'late token preparation never starts purchase for another account',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final response = Completer<http.Response>();
      respond = (_) => response.future;
      final starting = service.purchaseSubscription(product);
      await settle();
      account.signIn('user-b');
      await settle();
      response.complete(
        http.Response(
          jsonEncode({'uid': 'user-a', 'appAccountToken': token}),
          200,
        ),
      );
      await starting;
      verifyNever(
        () =>
            store.buyNonConsumable(purchaseParam: any(named: 'purchaseParam')),
      );
      expect(service.flow.value.uid, 'user-b');
    },
  );
  for (final patch in <Map<String, dynamic>>[
    {'uid': 'user-b'},
    {'transactionId': '999'},
    {'productId': IAPService.kYearlyId},
    {'transactionFinalization': 'not_safe'},
    {'outcome': null},
    {'expiresAt': '9999999999999'},
    {'environment': 'Sandbox', 'entitlementScope': 'sandbox'},
  ]) {
    test(
      'transaction acknowledgment rejects mismatched proof $patch',
      () async {
        respond = (_) async => http.Response(
          jsonEncode({
            ...jsonDecode(appleResponse()) as Map<String, dynamic>,
            ...patch,
          }),
          200,
        );
        events.add([purchase()]);
        await settle();
        verifyNever(() => store.completePurchase(any()));
        expect(account.refreshed, isEmpty);
        expect(service.canStartPurchase, isFalse);
      },
    );
  }
  test(
    'cold start probes ownership; foreign login cannot bind; owner return recovers',
    () async {
      account.signIn(null);
      await settle();
      final transaction = purchase();
      events.add([transaction]);
      await settle();
      expect(requests, isEmpty);
      respond = (request) async =>
          request.headers['authorization'] == 'Bearer user-a'
          ? http.Response(appleResponse(), 200)
          : http.Response(
              '{"outcome":"unavailable","code":"apple_ownership_recovery_required"}',
              503,
            );
      account.signIn('user-b');
      await settle();
      await service.restorePurchases();
      verifyNever(() => store.completePurchase(any()));
      expect(service.canStartPurchase, isTrue);
      expect(account.refreshed, isEmpty);
      account.signIn('user-a');
      await settle();
      verify(() => store.completePurchase(transaction)).called(1);
      expect(account.refreshed, ['user-a']);
      expect(service.flow.value.phase, PurchasePhase.verified);
      final body = jsonDecode(requests.last.body);
      expect(body['receiptFormat'], 'storekit2_jws');
      expect(body['transactionId'], '123');
      expect(body['productId'], product.id);
      await service.restorePurchases();
      verifyNever(() => store.completePurchase(any()));
    },
  );
  test(
    'late ownership proof leaves cold-start transaction recoverable for owner',
    () async {
      account.signIn(null);
      await settle();
      events.add([purchase()]);
      await settle();
      final response = Completer<http.Response>();
      respond = (_) => response.future;
      account.signIn('user-a');
      await settle();
      account.signIn('user-b');
      await settle();
      response.complete(http.Response(appleResponse(), 200));
      await settle();
      verifyNever(() => store.completePurchase(any()));
      expect(account.refreshed, isEmpty);
      respond = (_) async => http.Response(appleResponse(), 200);
      account.signIn('user-a');
      await settle();
      verify(() => store.completePurchase(any())).called(1);
    },
  );
  for (final switchDuringRequest in [false, true]) {
    test(
      'first JWS delivery to B recovers for A (in-flight switch: $switchDuringRequest)',
      () async {
        account.signIn('user-b');
        await settle();
        final declined = Completer<http.Response>();
        var ownerAvailable = false;
        respond = (request) async =>
            request.headers['authorization'] == 'Bearer user-b'
            ? declined.future
            : ownerAvailable
            ? http.Response(appleResponse(), 200)
            : http.Response('', 503);
        final transaction = purchase();
        events.add([transaction]);
        await settle();
        expect(service.canStartPurchase, isFalse);
        final recovery = http.Response(
          '{"outcome":"unavailable","code":"apple_ownership_recovery_required","transactionFinalization":"not_safe"}',
          503,
        );
        if (!switchDuringRequest) {
          declined.complete(recovery);
          await settle();
        }
        verifyNever(() => store.completePurchase(any()));
        account.signIn('user-a');
        await settle();
        ownerAvailable = true;
        final restore = service.restorePurchases();
        if (switchDuringRequest) declined.complete(recovery);
        await restore;
        await settle();
        verify(() => store.completePurchase(transaction)).called(1);
        expect(account.refreshed, isNot(contains('user-b')));
        expect(service.flow.value.phase, PurchasePhase.verified);
        expect(service.flow.value.uid, 'user-a');
        expect(
          requests.map((r) => r.headers['authorization']),
          containsAllInOrder(['Bearer user-b', 'Bearer user-a']),
        );
      },
    );
  }

  test(
    'proven ownership stays bound while entitlement delivery is pending',
    () async {
      account.entitled = false;
      final transaction = purchase();
      events.add([transaction]);
      await settle();
      expect(service.canStartPurchase, isFalse);
      verifyNever(() => store.completePurchase(any()));
      account.signIn('user-b');
      await settle();
      await service.restorePurchases();
      expect(service.canStartPurchase, isTrue);
      expect(requests, hasLength(1));
      verifyNever(() => store.completePurchase(any()));
      account.entitled = true;
      account.signIn('user-a');
      await settle();
      verify(() => store.completePurchase(transaction)).called(1);
      expect(
        requests.map((r) => r.headers['authorization']),
        everyElement('Bearer user-a'),
      );
    },
  );

  test(
    'definitive rejection releases retry gate without finishing transaction',
    () async {
      respond = (_) async => http.Response(appleResponse(valid: false), 200);
      events.add([purchase()]);
      await settle();
      verifyNever(() => store.completePurchase(any()));
      expect(service.canStartPurchase, isTrue);
    },
  );
}
