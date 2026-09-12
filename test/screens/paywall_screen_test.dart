import 'dart:async';

import 'package:are_coach/core/theme/app_theme.dart';
import 'package:are_coach/screens/paywall_screen.dart';
import 'package:are_coach/services/iap_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mocktail/mocktail.dart';

class MockIAPService extends Mock implements IAPService {}

void main() {
  late MockIAPService iap;
  late StreamController<PurchaseDetails> purchases;

  setUp(() {
    iap = MockIAPService();
    final flow = ValueNotifier<PurchaseFlow>(
      const PurchaseFlow(PurchasePhase.idle),
    );
    when(() => iap.flow).thenReturn(flow);
    when(() => iap.canPurchase).thenReturn(false);
    when(() => iap.canStartPurchase).thenReturn(false);
    when(() => iap.canRestore).thenReturn(true);
    when(() => iap.initialize()).thenAnswer((_) async {});
    purchases = StreamController<PurchaseDetails>.broadcast();
    when(() => iap.purchaseUpdates).thenAnswer((_) => purchases.stream);
    when(() => iap.loadProducts()).thenAnswer((_) async => <ProductDetails>[]);
  });

  tearDown(() => purchases.close());

  Future<void> pumpPaywall(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: PaywallScreen(iapService: iap),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // IAPService reports failures as stream *errors*. The paywall subscribed
  // without an onError, so each one escaped to the zone's unhandled-error hook
  // instead: no message, and a purchase spinner that never stopped. On the
  // money path, "say nothing to someone who was just charged" is the worst
  // possible answer.
  testWidgets('a validation failure is shown to the buyer, not swallowed', (
    tester,
  ) async {
    await pumpPaywall(tester);

    purchases.addError(
      IAPError(
        source: 'google_play',
        code: 'validation_unavailable',
        message: 'We could not confirm your purchase right now.',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('We could not confirm your purchase right now.'),
      findsOneWidget,
    );
  });

  testWidgets('an unrecognized error still gets a message', (tester) async {
    await pumpPaywall(tester);

    purchases.addError(StateError('something unexpected'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Purchase failed. Please try again.'), findsOneWidget);
  });
}
