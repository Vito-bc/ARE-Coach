// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'dart:convert';

import 'package:are_coach/services/iap_service.dart';
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
  }) {
    final verificationData = MockPurchaseVerificationData();
    when(
      () => verificationData.serverVerificationData,
    ).thenReturn(receiptData);
    when(() => verificationData.source).thenReturn(platform);

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
