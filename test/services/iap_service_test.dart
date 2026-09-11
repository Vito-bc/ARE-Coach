// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:are_coach/services/iap_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mocktail/mocktail.dart';

class MockInAppPurchase extends Mock implements InAppPurchase {}

class MockHttpClient extends Mock implements http.Client {}

class MockPurchaseDetails extends Mock implements PurchaseDetails {}

class MockPurchaseVerificationData extends Mock
    implements PurchaseVerificationData {}

class FakeUri extends Fake implements Uri {}

class FakePurchaseDetails extends Fake implements PurchaseDetails {}

void main() {
  late MockInAppPurchase mockIap;
  late MockHttpClient mockHttpClient;
  late StreamController<List<PurchaseDetails>> purchaseStreamController;
  late IAPService sut;

  const testEndpoint = 'https://test.example.com/validateReceipt';
  const receiptData = 'base64-receipt-data';
  const platform = 'app_store';

  setUpAll(() {
    registerFallbackValue(FakeUri());
    registerFallbackValue(FakePurchaseDetails());
  });

  setUp(() {
    mockIap = MockInAppPurchase();
    mockHttpClient = MockHttpClient();
    purchaseStreamController =
        StreamController<List<PurchaseDetails>>.broadcast();

    when(() => mockIap.isAvailable()).thenAnswer((_) async => true);
    when(
      () => mockIap.purchaseStream,
    ).thenAnswer((_) => purchaseStreamController.stream);
    when(
      () => mockIap.completePurchase(any()),
    ).thenAnswer((_) async {});
  });

  tearDown(() {
    purchaseStreamController.close();
    sut.dispose();
  });

  MockPurchaseDetails makePurchase({
    PurchaseStatus status = PurchaseStatus.purchased,
    bool pendingComplete = true,
    String source = platform,
  }) {
    final verificationData = MockPurchaseVerificationData();
    when(
      () => verificationData.serverVerificationData,
    ).thenReturn(receiptData);
    when(() => verificationData.source).thenReturn(source);

    final purchase = MockPurchaseDetails();
    when(() => purchase.status).thenReturn(status);
    when(() => purchase.pendingCompletePurchase).thenReturn(pendingComplete);
    when(() => purchase.verificationData).thenReturn(verificationData);
    return purchase;
  }

  http.Response validResponse() =>
      http.Response(jsonEncode({'valid': true}), 200);

  http.Response invalidResponse() =>
      http.Response(jsonEncode({'valid': false}), 200);

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
      final body = jsonDecode(captured.single as String) as Map<String, dynamic>;
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
        iap: mockIap,
        httpClient: mockHttpClient,
        validateReceiptUrlOverride: testEndpoint,
      );
    }

    Future<List<Object>> errorsFrom(Future<http.Response> Function() answer) async {
      arrange(answer);
      final errors = <Object>[];
      sut.purchaseUpdates.listen((_) {}, onError: errors.add);
      await initAndEmit([makePurchase()]);
      return errors;
    }

    test('a 503 (Play account not configured) is an outage, not a bad receipt',
        () async {
      final errors = await errorsFrom(
        () async => http.Response(
          jsonEncode({'error': 'not configured'}),
          503,
        ),
      );

      expect(errors, hasLength(1));
      expect((errors.first as IAPError).code, equals('validation_unavailable'));
      // The buyer must never be sent to support for our own downtime.
      expect(
        (errors.first as IAPError).message.toLowerCase(),
        isNot(contains('contact support')),
      );
    });

    test('a 502 (Play API down) is an outage too', () async {
      final errors = await errorsFrom(
        () async => http.Response(jsonEncode({'error': 'bad gateway'}), 502),
      );

      expect((errors.single as IAPError).code, equals('validation_unavailable'));
    });

    test('a dropped connection is an outage', () async {
      final errors = await errorsFrom(
        () async => throw const SocketException('no route to host'),
      );

      expect((errors.single as IAPError).code, equals('validation_unavailable'));
    });

    test('an unreadable 200 body is an outage, not an entitlement', () async {
      final errors = await errorsFrom(
        () async => http.Response('<html>gateway timeout</html>', 200),
      );

      expect((errors.single as IAPError).code, equals('validation_unavailable'));
    });

    test('an outage NEVER completes the purchase', () async {
      // This is what makes the outage recoverable: an unacknowledged Play
      // purchase is refunded automatically, and both stores re-deliver an
      // unfinished transaction on the next launch.
      arrange(() async => http.Response('', 503));
      sut.purchaseUpdates.listen((_) {}, onError: (_) {});

      await initAndEmit([makePurchase()]);

      verifyNever(() => mockIap.completePurchase(any()));
    });
  });

  group('_validateAndComplete — no VALIDATE_RECEIPT_URL (dev mode)', () {
    setUp(() {
      // No validateReceiptUrlOverride → endpoint is empty → skip validation.
      sut = IAPService(iap: mockIap, httpClient: mockHttpClient);
    });

    test('skips server call and completes purchase directly', () async {
      final purchase = makePurchase();
      await initAndEmit([purchase]);

      verifyNever(
        () => mockHttpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      );
      verify(() => mockIap.completePurchase(purchase)).called(1);
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
      sut = IAPService(iap: mockIap, httpClient: mockHttpClient);
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
      final body = jsonDecode(captured.single as String) as Map<String, dynamic>;
      expect(body['platform'], equals('google_play'));
      expect(body['receiptData'], equals(receiptData));
    });

    test('an unverified Play purchase is never acknowledged', () async {
      // Not calling completePurchase is what makes Google auto-refund an
      // unacknowledged purchase after three days — the buyer gets their money
      // back instead of paying for nothing.
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

  group('initialize', () {
    setUp(() {
      sut = IAPService(iap: mockIap, httpClient: mockHttpClient);
    });

    test('does not register a second listener on repeated initialize calls',
        () async {
      await sut.initialize();
      await sut.initialize();

      // Only one subscription should exist — verify by ensuring the stream
      // is only listened to once (second initialize returns early).
      verify(() => mockIap.purchaseStream).called(1);
    });
  });
}
