import 'package:are_coach/core/providers.dart';
import 'package:are_coach/services/purchase_account.dart';
import 'package:are_coach/services/purchase_environment.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/purchase_fakes.dart';

const sandbox = PurchaseEnvironment(
  apple: ApplePurchaseEnvironment.sandbox,
  firebaseEnvironment: 'Sandbox', entitlementSource: 'apple_sandbox',
  firebaseProjectId: 'are-coach-sandbox',
  validationEndpoint:
      'https://us-central1-are-coach-sandbox.cloudfunctions.net/validateReceipt',
  firebaseApiKey: 'key', firebaseAppId: 'app',
  firebaseMessagingSenderId: 'sender', firebaseStorageBucket: 'bucket',
);

void main() {
  test('sandbox role survives refresh outage, expires, and reloads on restart', () async {
    final account = FakeAccount();
    account.entitlementProof = PurchaseEntitlement(
      active: true, uid: 'user-a', environment: 'Sandbox', scope: 'sandbox',
      expiresAt: DateTime.now().add(const Duration(seconds: 1)),
    );
    ProviderContainer create() => ProviderContainer(overrides: [
      purchaseEnvironmentProvider.overrideWithValue(sandbox),
      purchaseAccountProvider.overrideWithValue(account),
    ]);
    var container = create();
    final subscription = container.listen(userRoleProvider('user-a'), (_, __) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(userRoleProvider('user-a')).value, 'premium');
    account.entitlementError = StateError('outage');
    account.notifyEntitlementChanged('user-a');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(userRoleProvider('user-a')).value, 'premium');
    await Future<void>.delayed(const Duration(milliseconds: 1050));
    expect(container.read(userRoleProvider('user-a')).value, 'free');
    subscription.close(); container.dispose();

    container = create();
    final restarted = container.listen(userRoleProvider('user-a'), (_, __) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(userRoleProvider('user-a')).value, 'free');
    restarted.close(); container.dispose(); account.dispose();
  });

  test('account switch fetches only the newly signed-in uid', () async {
    final account = FakeAccount();
    final container = ProviderContainer(overrides: [
      purchaseEnvironmentProvider.overrideWithValue(sandbox),
      purchaseAccountProvider.overrideWithValue(account),
    ]);
    final first = container.listen(userRoleProvider('user-a'), (_, __) {});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    account.signIn('user-b');
    final second = container.listen(userRoleProvider('user-b'), (_, __) {});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(account.refreshed, containsAllInOrder(['user-a', 'user-b']));
    first.close(); second.close(); container.dispose(); account.dispose();
  });
}
