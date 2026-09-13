import 'package:are_coach/services/purchase_environment.dart';
import 'package:flutter_test/flutter_test.dart';

PurchaseEnvironment sandbox({
  String firebaseEnvironment = 'Sandbox',
  String source = 'apple_sandbox',
  String project = 'are-coach-sandbox',
  String? endpoint,
}) => PurchaseEnvironment(
  apple: ApplePurchaseEnvironment.sandbox,
  firebaseEnvironment: firebaseEnvironment,
  entitlementSource: source,
  firebaseProjectId: project,
  validationEndpoint: endpoint ??
      'https://us-central1-$project.cloudfunctions.net/validateReceipt',
  firebaseApiKey: 'configured-by-operator',
  firebaseAppId: 'configured-by-operator',
  firebaseMessagingSenderId: 'configured-by-operator',
  firebaseStorageBucket: 'configured-by-operator',
);

void main() {
  test('complete sandbox configuration is coherent', () {
    expect(sandbox().configurationError, isNull);
  });

  test('mixed or incomplete build contracts block purchases', () {
    for (final config in [
      sandbox(firebaseEnvironment: 'Production'),
      sandbox(source: 'production'),
      sandbox(project: PurchaseEnvironment.productionProjectId),
      sandbox(endpoint: 'https://example.com/validateReceipt'),
      const PurchaseEnvironment(
        apple: ApplePurchaseEnvironment.sandbox,
        firebaseEnvironment: 'Sandbox',
        entitlementSource: 'apple_sandbox',
        firebaseProjectId: 'are-coach-sandbox',
        validationEndpoint:
            'https://us-central1-are-coach-sandbox.cloudfunctions.net/validateReceipt',
      ),
    ]) {
      expect(config.configurationError, isNotNull);
    }
  });

  test('production is the build default and cannot point at sandbox', () {
    expect(PurchaseEnvironment.current.apple,
        ApplePurchaseEnvironment.production);
    const mixed = PurchaseEnvironment(
      apple: ApplePurchaseEnvironment.production,
      firebaseEnvironment: 'Production',
      entitlementSource: 'production',
      firebaseProjectId: 'are-coach-sandbox',
      validationEndpoint:
          'https://us-central1-are-coach-sandbox.cloudfunctions.net/validateReceipt',
    );
    expect(mixed.isCoherent, isFalse);
  });
}
