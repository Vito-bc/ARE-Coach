import 'dart:async';
import 'dart:io';

import 'package:are_coach/core/providers.dart';
import 'package:are_coach/models/flashcard.dart';
import 'package:are_coach/screens/flashcard_session_screen.dart';
import 'package:are_coach/screens/paywall_screen.dart';
import 'package:are_coach/services/iap_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:are_coach/services/purchase_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mocktail/mocktail.dart';

import '../support/purchase_fakes.dart';

void main() {
  const notEntitledResponse =
      '{"valid":false,"outcome":"not_entitled",'
      '"reason":"expired","transactionFinalization":"not_safe"}';
  late MockInAppPurchase store;
  late MockHttpClient client;
  late FakeAccount account;
  late IAPService service;
  late StreamController<List<PurchaseDetails>> events;
  late ProviderContainer container;
  late int disposals;
  final product = ProductDetails(
    id: IAPService.kYearlyId,
    title: 'Yearly',
    description: 'Yearly',
    price: '\$99',
    rawPrice: 99,
    currencyCode: 'USD',
  );

  setUpAll(() async {
    registerFallbackValue(FakeUri());
    registerFallbackValue(FakePurchaseDetails());
    registerFallbackValue(PurchaseParam(productDetails: product));
    Hive.init((await Directory.systemTemp.createTemp('iap-widget-')).path);
  });
  tearDownAll(Hive.close);

  setUp(() {
    store = MockInAppPurchase();
    client = MockHttpClient();
    account = FakeAccount();
    events = StreamController<List<PurchaseDetails>>.broadcast();
    when(() => store.purchaseStream).thenAnswer((_) => events.stream);
    when(() => store.isAvailable()).thenAnswer((_) async => true);
    when(() => store.queryProductDetails(any())).thenAnswer(
      (_) async =>
          ProductDetailsResponse(productDetails: [product], notFoundIDs: []),
    );
    when(() => store.completePurchase(any())).thenAnswer((_) async {});
    when(() => store.restorePurchases()).thenAnswer((_) async {});
    when(
      () => store.buyNonConsumable(purchaseParam: any(named: 'purchaseParam')),
    ).thenAnswer((_) async => true);
    when(
      () => client.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((_) async => http.Response('{"valid":true}', 200));
    service = IAPService(
      iap: store,
      httpClient: client,
      account: account,
      validateReceiptUrlOverride: 'https://example.com/validate',
      storeTimeout: const Duration(seconds: 2),
    );
    disposals = 0;
    container = ProviderContainer(
      overrides: [
        iapServiceProvider.overrideWith((ref) {
          ref.onDispose(() {
            disposals++;
            service.dispose();
          });
          unawaited(service.initialize());
          return service;
        }),
        userRoleProvider.overrideWith((ref, uid) => Stream.value('free')),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await events.close();
    await account.events.close();
  });

  PurchaseDetails purchase(PurchaseStatus status) =>
      PurchaseDetails(
          productID: IAPService.kYearlyId,
          purchaseID: 'transaction-42',
          verificationData: PurchaseVerificationData(
            localVerificationData: '',
            serverVerificationData: 'receipt',
            source: 'app_store',
          ),
          transactionDate: '123',
          status: status,
        )
        ..pendingCompletePurchase =
            status == PurchaseStatus.purchased ||
            status == PurchaseStatus.restored;

  Future<void> app(WidgetTester tester, {Widget? home}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home:
              home ??
              Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PaywallScreen()),
                    ),
                    child: const Text('Open premium'),
                  ),
                ),
              ),
        ),
      ),
    );
    if (home != null) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
    }
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Open premium'));
    await tester.pumpAndSettle();
  }

  testWidgets('pending and cancellation leave an actionable paywall', (
    tester,
  ) async {
    await app(tester);
    await open(tester);
    await tester.tap(find.text('Subscribe Now'));
    await tester.pump();
    events.add([purchase(PurchaseStatus.pending)]);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Payment is pending'), findsOneWidget);
    events.add([purchase(PurchaseStatus.canceled)]);
    await tester.pumpAndSettle();
    expect(find.text('Purchase cancelled.'), findsOneWidget);
    expect(find.byType(PaywallScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('no callback and empty restore both terminate the spinner', (
    tester,
  ) async {
    await app(tester);
    await open(tester);
    await tester.tap(find.text('Subscribe Now'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Still waiting'), findsOneWidget);
    await tester.tap(find.text('Restore Purchases'));
    await tester.pumpAndSettle();
    expect(
      find.text('No matching purchases were returned by the store.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'expired restore can be repeated and followed by a new purchase',
    (tester) async {
      when(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response(notEntitledResponse, 200));
      when(() => store.restorePurchases()).thenAnswer((_) async {
        events.add([purchase(PurchaseStatus.restored)]);
      });
      await app(tester);
      await open(tester);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Restore Purchases'));
        await tester.pumpAndSettle();
        expect(service.flow.value.phase, PurchasePhase.failed);
      }

      await tester.tap(find.text('Subscribe Now'));
      await tester.pump();
      verify(
        () =>
            store.buyNonConsumable(purchaseParam: any(named: 'purchaseParam')),
      ).called(1);
      expect(find.text('Purchase failed. Please try again.'), findsNothing);
      expect(find.text('Premium access confirmed.'), findsNothing);
      verifyNever(() => store.completePurchase(any()));

      when(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response('{"valid":true}', 200));
      events.add([purchase(PurchaseStatus.purchased)]);
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.text('Premium access confirmed.'), findsOneWidget);
      verify(() => store.completePurchase(any())).called(1);
    },
  );

  testWidgets('unavailable validation disables Subscribe and keeps Restore', (
    tester,
  ) async {
    when(
      () => client.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((_) async => http.Response('', 503));
    await app(tester);
    await open(tester);
    events.add([purchase(PurchaseStatus.purchased)]);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Subscribe Now'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Restore Purchases'),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      find.textContaining('could not confirm your purchase'),
      findsOneWidget,
    );
    expect(find.text('Purchase failed. Please try again.'), findsNothing);
    verifyNever(
      () => store.buyNonConsumable(purchaseParam: any(named: 'purchaseParam')),
    );
  });

  for (final response in ['{"valid":false}', '{}']) {
    testWidgets('validator response $response has no false success', (
      tester,
    ) async {
      when(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => http.Response(response, 200));
      await app(tester);
      await open(tester);
      events.add([purchase(PurchaseStatus.purchased)]);
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.textContaining('could not confirm'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      verifyNever(() => store.completePurchase(any()));
    });
  }

  testWidgets(
    'leaving and reopening while validating keeps one owner and completion',
    (tester) async {
      final response = Completer<http.Response>();
      when(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) => response.future);
      await app(tester);
      await open(tester);
      events.add([purchase(PurchaseStatus.purchased)]);
      await tester.pump();
      await tester.tap(find.text('Continue with Free'));
      await tester.pumpAndSettle();
      expect(disposals, 0);
      await tester.tap(find.text('Open premium'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Confirming your purchase...'), findsOneWidget);
      response.complete(http.Response('{"valid":true}', 200));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.text('Premium access confirmed.'), findsOneWidget);
      expect(account.refreshed, ['user-a']);
      verify(() => store.purchaseStream).called(1);
      verify(() => store.completePurchase(any())).called(1);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      expect(disposals, 1);
    },
  );

  testWidgets('raw store event cannot welcome a different account', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    when(
      () => client.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      ),
    ).thenAnswer((_) => response.future);
    await app(tester);
    await open(tester);
    events.add([purchase(PurchaseStatus.restored)]);
    await tester.pump();
    account.signIn('user-b');
    await tester.pump();
    response.complete(http.Response('{"valid":true}', 200));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsOneWidget);
    expect(find.text('Premium access confirmed.'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(account.refreshed, isEmpty);
  });

  testWidgets(
    'flashcard upsell uses the already initialized application service',
    (tester) async {
      var haptics = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics++;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      // Pre-open Hive boxes outside fake time for the real flashcard screen.
      await tester.runAsync(() async {
        await Hive.openBox<String>('flashcard_progress');
        await Hive.openBox<int>('flashcard_timestamps');
      });
      await container.read(iapServiceProvider).initialize();
      await app(
        tester,
        home: FlashcardSessionScreen(
          section: 'PcM',
          cards: const [
            Flashcard(
              id: 'test',
              section: 'PcM',
              front: 'Front',
              back: 'Back',
              codeRef: 'Test source',
              examTip: 'Test tip',
            ),
          ],
          initialStatuses: const {},
          onComplete: (_) {},
        ),
      );
      await tester.tap(find.text('Front'));
      await tester.pump();
      expect(haptics, 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Back'), findsOneWidget);
      await tester.tap(find.text('Explain with Coach'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upgrade'));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      verify(() => store.queryProductDetails(any())).called(1);
      verify(() => store.purchaseStream).called(1);
      await tester.tap(find.text('Continue with Free'));
      await tester.pumpAndSettle();
      expect(disposals, 0);
    },
  );

  test('stale role, expiry and inactive status cannot grant local access', () {
    final now = DateTime.utc(2026, 9, 10);
    final future = Timestamp.fromDate(now.add(const Duration(days: 1)));
    expect(hasActiveSubscription({'role': 'premium'}, now), isFalse);
    expect(
      hasActiveSubscription({
        'role': 'premium',
        'subscriptionStatus': 'expired',
        'premiumUntil': future,
      }, now),
      isFalse,
    );
    expect(
      hasActiveSubscription({
        'subscriptionStatus': 'active',
        'premiumUntil': Timestamp.fromDate(now),
      }, now),
      isFalse,
    );
    expect(
      hasActiveSubscription({
        'subscriptionStatus': 'active',
        'premiumUntil': future,
      }, now),
      isTrue,
    );
  });
}
