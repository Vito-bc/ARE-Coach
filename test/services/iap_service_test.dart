// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:are_coach/services/iap_service.dart';
import '../support/purchase_fakes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  late MockInAppPurchase mockIap;
  late MockHttpClient mockHttpClient;
  late StreamController<List<PurchaseDetails>> purchaseStreamController;
  late IAPService sut;
  late FakeAccount account;

  const testEndpoint = 'https://test.example.com/validateReceipt';
  const receiptData = 'base64-receipt-data';
  const platform = 'app_store';
  final product = ProductDetails(
    id: IAPService.kMonthlyId,
    title: 'Monthly',
    description: 'Monthly subscription',
    price: '\$10',
    rawPrice: 10,
    currencyCode: 'USD',
  );

  setUpAll(() {
    registerFallbackValue(FakeUri());
    registerFallbackValue(FakePurchaseDetails());
    registerFallbackValue(PurchaseParam(productDetails: product));
  });

  setUp(() {
    account = FakeAccount();
    mockIap = MockInAppPurchase();
    mockHttpClient = MockHttpClient();
    purchaseStreamController =
        StreamController<List<PurchaseDetails>>.broadcast();

    when(() => mockIap.isAvailable()).thenAnswer((_) async => true);
    when(
      () => mockIap.purchaseStream,
    ).thenAnswer((_) => purchaseStreamController.stream);
    when(() => mockIap.completePurchase(any())).thenAnswer((_) async {});
    when(
      () =>
          mockIap.buyNonConsumable(purchaseParam: any(named: 'purchaseParam')),
    ).thenAnswer((_) async => true);
  });

  tearDown(() {
    purchaseStreamController.close();
    sut.dispose();
    account.events.close();
  });

  MockPurchaseDetails makePurchase({
    PurchaseStatus status = PurchaseStatus.purchased,
    bool pendingComplete = true,
    String source = platform,
  }) {
    final verificationData = MockPurchaseVerificationData();
    when(() => verificationData.serverVerificationData).thenReturn(receiptData);
    when(() => verificationData.source).thenReturn(source);

    final purchase = MockPurchaseDetails();
    when(() => purchase.productID).thenReturn(IAPService.kMonthlyId);
    when(() => purchase.purchaseID).thenReturn('transaction-1');
    when(() => purchase.transactionDate).thenReturn('123');
    when(() => purchase.status).thenReturn(status);
    when(() => purchase.pendingCompletePurchase).thenReturn(pendingComplete);
    when(() => purchase.verificationData).thenReturn(verificationData);
    return purchase;
  }

  http.Response validResponse() =>
      http.Response(jsonEncode({'valid': true}), 200);

  http.Response invalidResponse() => http.Response(
    jsonEncode({
      'valid': false,
      'outcome': 'not_entitled',
      'reason': 'expired',
      'transactionFinalization': 'not_safe',
    }),
    200,
  );

  Future<void> initAndEmit(List<PurchaseDetails> purchases) async {
    await sut.initialize();
    purchaseStreamController.add(purchases);
    // Allow microtasks from _validateAndComplete to run.
    await Future<void>.delayed(Duration.zero);
  }

  group('_validateAndComplete — server returns valid: true', () {
    setUp(() {
      when(
        () => mockHttpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => validResponse());

      sut = IAPService(
        account: account,
        iap: mockIap,
        httpClient: mockHttpClient,
        validateReceiptUrlOverride: testEndpoint,
      );
    });

    test('calls completePurchase after successful validation', () async {
      final purchase = makePurchase();
      await initAndEmit([purchase]);
      verify(() => mockIap.completePurchase(purchase)).called(1);
    });

    test('emits purchase to purchaseUpdates stream', () async {
      final purchase = makePurchase();
      final updates = <PurchaseDetails>[];
      sut.purchaseUpdates.listen(updates.add);

      await initAndEmit([purchase]);

      expect(updates, contains(purchase));
    });

    test('posts receiptData and platform to the endpoint', () async {
      final purchase = makePurchase();
      await initAndEmit([purchase]);

      final captured = verify(
        () => mockHttpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;
      final body =
          jsonDecode(captured.single as String) as Map<String, dynamic>;
      expect(body['receiptData'], equals(receiptData));
      expect(body['platform'], equals(platform));
    });
  });

  group('_validateAndComplete — server returns valid: false', () {
    setUp(() {
      when(
        () => mockHttpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => invalidResponse());

      sut = IAPService(
        account: account,
        iap: mockIap,
        httpClient: mockHttpClient,
        validateReceiptUrlOverride: testEndpoint,
      );
    });

    test('does NOT call completePurchase', () async {
      final purchase = makePurchase();
      await initAndEmit([purchase]);
      verifyNever(() => mockIap.completePurchase(any()));
    });

    test('emits an IAPError to purchaseUpdates', () async {
      final purchase = makePurchase();
      final errors = <Object>[];
      sut.purchaseUpdates.listen((_) {}, onError: errors.add);

      await initAndEmit([purchase]);

      expect(errors, hasLength(1));
      expect(errors.first, isA<IAPError>());
      final err = errors.first as IAPError;
      expect(err.code, equals('receipt_invalid'));
    });
  });

  // A failure to REACH the verdict is not the same as a verdict of "no". The
  // server answers 503 when the Play service account isn't configured and 502
  // when Play itself is down; in both cases the buyer's payment is fine and
  // telling them their receipt was bad would be a lie.
  group('_validateAndComplete — the server never returned a verdict', () {
    void arrange(Future<http.Response> Function() answer) {
      when(
        () => mockHttpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) => answer());

      sut = IAPService(
        account: account,
        iap: mockIap,
        httpClient: mockHttpClient,
        validateReceiptUrlOverride: testEndpoint,
      );
    }

    Future<List<Object>> errorsFrom(
      Future<http.Response> Function() answer,
    ) async {
      arrange(answer);
      final errors = <Object>[];
      sut.purchaseUpdates.listen((_) {}, onError: errors.add);
      await initAndEmit([makePurchase()]);
      return errors;
    }

    test(
      'a 503 (Play account not configured) is an outage, not a bad receipt',
      () async {
        final errors = await errorsFrom(
          () async =>
              http.Response(jsonEncode({'error': 'not configured'}), 503),
        );

        expect(errors, hasLength(1));
        expect(
          (errors.first as IAPError).code,
          equals('validation_unavailable'),
        );
        // The buyer must never be sent to support for our own downtime.
        expect(
          (errors.first as IAPError).message.toLowerCase(),
          isNot(contains('contact support')),
        );
      },
    );

    test('a 502 (Play API down) is an outage too', () async {
      final errors = await errorsFrom(
        () async => http.Response(jsonEncode({'error': 'bad gateway'}), 502),
      );

      expect(
        (errors.single as IAPError).code,
        equals('validation_unavailable'),
      );
    });

    test('a dropped connection is an outage', () async {
      final errors = await errorsFrom(
        () async => throw const SocketException('no route to host'),
      );

      expect(
        (errors.single as IAPError).code,
        equals('validation_unavailable'),
      );
    });

    test('an unreadable 200 body is an outage, not an entitlement', () async {
      final errors = await errorsFrom(
        () async => http.Response('<html>gateway timeout</html>', 200),
      );

      expect(
        (errors.single as IAPError).code,
        equals('validation_unavailable'),
      );
    });

    for (final body in [
      '{}',
      '{"valid":null}',
      '{"valid":"false"}',
      '{"valid":"true"}',
      '{"valid":false}',
      '{"valid":false,"outcome":"not_entitled"}',
      '[]',
    ]) {
      test('protocol failure: $body', () async {
        final errors = await errorsFrom(() async => http.Response(body, 200));
        expect((errors.single as IAPError).code, 'validation_unavailable');
      });
    }

    test('an outage NEVER completes the purchase', () async {
      // Preserve the transaction for explicit retry or store redelivery.
      arrange(() async => http.Response('', 503));
      sut.purchaseUpdates.listen((_) {}, onError: (_) {});

      await initAndEmit([makePurchase()]);

      verifyNever(() => mockIap.completePurchase(any()));
    });
  });

  group('_validateAndComplete — no VALIDATE_RECEIPT_URL', () {
    setUp(() {
      // No endpoint: redelivered transactions must fail closed too.
      sut = IAPService(
        account: account,
        iap: mockIap,
        httpClient: mockHttpClient,
      );
    });

    test('missing endpoint never verifies a redelivered purchase', () async {
      final errors = <Object>[];
      sut.purchaseUpdates.listen((_) {}, onError: errors.add);
      final purchase = makePurchase();
      await initAndEmit([purchase]);

      verifyNever(
        () => mockHttpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
      verifyNever(() => mockIap.completePurchase(any()));
      expect((errors.single as IAPError).code, 'validation_unavailable');
    });
  });

  group('purchasesSupported — we only sell where the server can verify', () {
    // Not a mocked service: the rule itself, one row per real build config.
    bool supported({
      required TargetPlatform platform,
      bool isWeb = false,
      bool androidEnabled = true,
      bool canValidate = true,
    }) => IAPService.computePurchasesSupported(
      platform: platform,
      isWeb: isWeb,
      androidEnabled: androidEnabled,
      canValidate: canValidate,
    );

    setUp(() {
      sut = IAPService(
        account: account,
        iap: mockIap,
        httpClient: mockHttpClient,
      );
    });

    test('Android sells once the build enables it', () {
      expect(supported(platform: TargetPlatform.android), isTrue);
    });

    test('Android does NOT sell when the build has not enabled it', () {
      // ANDROID_PURCHASES_ENABLED is off until GOOGLE_PLAY_SERVICE_ACCOUNT is
      // configured server-side — otherwise a buyer pays and stays free.
      expect(
        supported(platform: TargetPlatform.android, androidEnabled: false),
        isFalse,
      );
    });

    test('the Android switch never affects iOS or macOS', () {
      for (final p in [TargetPlatform.iOS, TargetPlatform.macOS]) {
        expect(supported(platform: p, androidEnabled: false), isTrue);
      }
    });

    test('no store sells when the build cannot reach validation', () {
      // A release build compiled without VALIDATE_RECEIPT_URL would complete
      // purchases locally and never upgrade the account server-side.
      for (final p in [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.android,
      ]) {
        expect(supported(platform: p, canValidate: false), isFalse);
      }
    });

    test('web never sells, whatever else is set', () {
      expect(supported(platform: TargetPlatform.iOS, isWeb: true), isFalse);
      expect(supported(platform: TargetPlatform.android, isWeb: true), isFalse);
    });

    test('desktop platforms without a store never sell', () {
      for (final p in [
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        expect(supported(platform: p), isFalse);
      }
    });

    test('the default build ships with Android sales off', () {
      // Guards the default: turning Android on is a deliberate build-time act.
      expect(IAPService.androidPurchasesEnabled, isFalse);
    });
  });

  group('_validateAndComplete — Android sends the Play purchase token', () {
    setUp(() {
      when(
        () => mockHttpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => validResponse());

      sut = IAPService(
        account: account,
        iap: mockIap,
        httpClient: mockHttpClient,
        validateReceiptUrlOverride: testEndpoint,
      );
    });

    test('posts platform google_play so the server routes to Play', () async {
      final purchase = makePurchase(source: 'google_play');
      await initAndEmit([purchase]);

      final captured = verify(
        () => mockHttpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: captureAny(named: 'body'),
        ),
      ).captured;
      final body =
          jsonDecode(captured.single as String) as Map<String, dynamic>;
      expect(body['platform'], equals('google_play'));
      expect(body['receiptData'], equals(receiptData));
    });

    test('an unverified Play purchase is never acknowledged', () async {
      // Preserve an unverified transaction for recovery; never report a
      // successful acknowledgment without a positive server verdict.
      when(
        () => mockHttpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => invalidResponse());

      await initAndEmit([makePurchase(source: 'google_play')]);

      verifyNever(() => mockIap.completePurchase(any()));
    });
  });

  group('lifecycle recovery', () {
    late List<Object> errors;
    late List<PurchaseDetails> updates;
    setUp(() {
      sut = IAPService(
        account: account,
        iap: mockIap,
        httpClient: mockHttpClient,
        validateReceiptUrlOverride: testEndpoint,
        requestTimeout: const Duration(milliseconds: 25),
        storeTimeout: const Duration(milliseconds: 50),
      );
      errors = [];
      updates = [];
      sut.purchaseUpdates.listen(updates.add, onError: errors.add);
      when(
        () => mockHttpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => validResponse());
      when(() => mockIap.restorePurchases()).thenAnswer((_) async {});
    });

    for (final status in [PurchaseStatus.purchased, PurchaseStatus.restored]) {
      test(
        'rejected $status allows a new subscription after redelivery',
        () async {
          when(
            () => mockHttpClient.post(
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            ),
          ).thenAnswer((_) async => invalidResponse());
          await initAndEmit([makePurchase(status: status)]);
          await initAndEmit([makePurchase(status: status)]);
          await sut.retryPendingPurchases();
          verify(
            () => mockHttpClient.post(
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            ),
          ).called(2);
          expect(updates, isEmpty);
          expect(account.refreshed, isEmpty);
          verifyNever(() => mockIap.completePurchase(any()));

          await sut.purchaseSubscription(product);

          verify(
            () => mockIap.buyNonConsumable(
              purchaseParam: any(named: 'purchaseParam'),
            ),
          ).called(1);
        },
      );
    }

    test(
      'an unavailable verdict blocks a new charge and can be retried',
      () async {
        when(
          () => mockHttpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => http.Response('', 503));
        await initAndEmit([makePurchase()]);

        await expectLater(
          sut.purchaseSubscription(product),
          throwsA(
            isA<IAPError>().having(
              (error) => error.message,
              'message',
              contains('Restore Purchases'),
            ),
          ),
        );
        verifyNever(
          () => mockIap.buyNonConsumable(
            purchaseParam: any(named: 'purchaseParam'),
          ),
        );
        when(
          () => mockHttpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) async => validResponse());
        await sut.retryPendingPurchases();
        await Future<void>.delayed(Duration.zero);
        expect(updates, hasLength(1));
        verify(() => mockIap.completePurchase(any())).called(1);
      },
    );

    for (final status in [PurchaseStatus.canceled, PurchaseStatus.error]) {
      test('unknown StoreKit product with $status is finished once', () async {
        final purchase = makePurchase(status: status);
        when(() => purchase.productID).thenReturn('retired_product');
        await initAndEmit([purchase, purchase]);
        verify(() => mockIap.completePurchase(purchase)).called(1);
        expect(updates, isEmpty);
        expect(account.refreshed, isEmpty);
      });
    }

    for (final status in [PurchaseStatus.purchased, PurchaseStatus.restored]) {
      test(
        'unknown paid product with $status is reported without granting',
        () async {
          final purchase = makePurchase(status: status);
          when(() => purchase.productID).thenReturn('retired_product');
          await initAndEmit([purchase]);
          expect((errors.single as IAPError).code, 'unsupported_product');
          expect(sut.flow.value.busy, isFalse);
          expect(updates, isEmpty);
          expect(account.refreshed, isEmpty);
          verifyNever(() => mockIap.completePurchase(any()));
          verifyNever(
            () => mockHttpClient.post(
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            ),
          );
        },
      );
    }

    test(
      'duplicate and redelivered events validate, complete and emit once',
      () async {
        final purchase = makePurchase();
        await initAndEmit([purchase, purchase]);
        await initAndEmit([makePurchase()]);
        expect(updates, hasLength(1));
        expect(account.refreshed, ['user-a']);
        verify(() => mockIap.completePurchase(any())).called(1);
        verify(
          () => mockHttpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).called(1);
      },
    );

    test('a never-resolving HTTP request times out without success', () async {
      final response = Completer<http.Response>();
      when(
        () => mockHttpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) => response.future);
      await initAndEmit([makePurchase()]);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect((errors.single as IAPError).code, 'validation_unavailable');
      expect(sut.flow.value.busy, isFalse);
      response.complete(validResponse());
      await Future<void>.delayed(Duration.zero);
      expect(updates, isEmpty);
      verifyNever(() => mockIap.completePurchase(any()));
    });

    test(
      'account switch during validation cannot refresh or grant the new account',
      () async {
        final response = Completer<http.Response>();
        when(
          () => mockHttpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) => response.future);
        await initAndEmit([makePurchase()]);
        account.signIn('user-b');
        await Future<void>.delayed(Duration.zero);
        response.complete(validResponse());
        await Future<void>.delayed(Duration.zero);
        expect(updates, isEmpty);
        expect(account.refreshed, isEmpty);
        expect(sut.flow.value.phase, PurchasePhase.idle);
        verifyNever(() => mockIap.completePurchase(any()));
      },
    );

    test(
      'dispose during HTTP response never completes or writes closed streams',
      () async {
        final response = Completer<http.Response>();
        when(
          () => mockHttpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer((_) => response.future);
        await initAndEmit([makePurchase()]);
        sut.dispose();
        response.complete(validResponse());
        await Future<void>.delayed(Duration.zero);
        expect(updates, isEmpty);
        expect(errors, isEmpty);
        verifyNever(() => mockIap.completePurchase(any()));
        verifyNever(() => mockHttpClient.close());
      },
    );

    test(
      'server verdict alone cannot grant without authoritative entitlement',
      () async {
        account.entitled = false;
        await initAndEmit([makePurchase()]);
        expect(updates, isEmpty);
        expect((errors.single as IAPError).code, 'entitlement_unavailable');
        verifyNever(() => mockIap.completePurchase(any()));
      },
    );

    test(
      'completion exception is visible and explicit retry can recover',
      () async {
        when(
          () => mockIap.completePurchase(any()),
        ).thenThrow(StateError('store offline'));
        await initAndEmit([makePurchase()]);
        expect((errors.single as IAPError).code, 'purchase_unfinished');
        expect(updates, isEmpty);
        when(() => mockIap.completePurchase(any())).thenAnswer((_) async {});
        await sut.retryPendingPurchases();
        await Future<void>.delayed(Duration.zero);
        expect(updates, hasLength(1));
      },
    );

    test('cancellation and pending do not grant or spin forever', () async {
      await initAndEmit([makePurchase(status: PurchaseStatus.pending)]);
      expect(sut.flow.value.phase, PurchasePhase.pending);
      expect(sut.flow.value.busy, isFalse);
      await initAndEmit([
        makePurchase(status: PurchaseStatus.canceled, pendingComplete: false),
      ]);
      expect(sut.flow.value.phase, PurchasePhase.cancelled);
      expect(sut.flow.value.busy, isFalse);
      verifyNever(() => mockIap.completePurchase(any()));
    });

    test(
      'restore with no matching purchase has an explicit final state',
      () async {
        await sut.restorePurchases();
        expect(sut.flow.value.phase, PurchasePhase.empty);
        expect(sut.flow.value.busy, isFalse);
      },
    );

    test('restore waits for server verification before success', () async {
      when(() => mockIap.restorePurchases()).thenAnswer((_) async {
        purchaseStreamController.add([
          makePurchase(status: PurchaseStatus.restored),
        ]);
      });
      await sut.restorePurchases();
      expect(sut.flow.value.phase, PurchasePhase.verified);
      expect(account.refreshed, ['user-a']);
      expect(updates, hasLength(1));
    });

    for (final endpoint in [
      '',
      'not a url',
      'http://example.com',
      'https://',
    ]) {
      test(
        'invalid configuration $endpoint cannot verify incoming transactions',
        () async {
          sut.dispose();
          sut = IAPService(
            account: account,
            iap: mockIap,
            httpClient: mockHttpClient,
            validateReceiptUrlOverride: endpoint,
          );
          sut.purchaseUpdates.listen(updates.add, onError: errors.add);
          await initAndEmit([makePurchase()]);
          expect(updates, isEmpty);
          expect((errors.single as IAPError).code, 'validation_unavailable');
          verifyNever(() => mockIap.completePurchase(any()));
        },
      );
    }
  });

  group('initialize', () {
    setUp(() {
      sut = IAPService(
        account: account,
        iap: mockIap,
        httpClient: mockHttpClient,
      );
    });

    test('concurrent initialization has one store listener', () async {
      await Future.wait([sut.initialize(), sut.initialize(), sut.initialize()]);
      verify(() => mockIap.purchaseStream).called(1);
    });

    test(
      'does not register a second listener on repeated initialize calls',
      () async {
        await sut.initialize();
        await sut.initialize();

        // Only one subscription should exist — verify by ensuring the stream
        // is only listened to once (second initialize returns early).
        verify(() => mockIap.purchaseStream).called(1);
      },
    );
  });
}
