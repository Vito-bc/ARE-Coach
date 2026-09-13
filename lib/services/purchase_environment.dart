import 'package:firebase_core/firebase_core.dart';

enum ApplePurchaseEnvironment { production, sandbox }

/// One build-time contract for StoreKit, Firebase and entitlement reads.
/// Production is the default; sandbox must be configured explicitly and fully.
class PurchaseEnvironment {
  const PurchaseEnvironment({
    required this.apple,
    required this.firebaseEnvironment,
    required this.entitlementSource,
    required this.firebaseProjectId,
    required this.validationEndpoint,
    this.firebaseApiKey = '',
    this.firebaseAppId = '',
    this.firebaseMessagingSenderId = '',
    this.firebaseStorageBucket = '',
    this.declaredAppleEnvironment,
  });

  static const productionProjectId = 'architect-study-app';
  static const bundleId = 'com.archedu.architectulaEducationApp';

  static const current = PurchaseEnvironment(
    apple: String.fromEnvironment('APPLE_IAP_ENVIRONMENT', defaultValue: 'Production') == 'Sandbox'
        ? ApplePurchaseEnvironment.sandbox
        : ApplePurchaseEnvironment.production,
    firebaseEnvironment: String.fromEnvironment('FIREBASE_ENVIRONMENT', defaultValue: 'Production'),
    entitlementSource: String.fromEnvironment('IAP_ENTITLEMENT_SOURCE', defaultValue: 'production'),
    firebaseProjectId: String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: productionProjectId),
    validationEndpoint: String.fromEnvironment('VALIDATE_RECEIPT_URL'),
    firebaseApiKey: String.fromEnvironment('FIREBASE_API_KEY'),
    firebaseAppId: String.fromEnvironment('FIREBASE_APP_ID'),
    firebaseMessagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
    firebaseStorageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
    declaredAppleEnvironment: String.fromEnvironment(
      'APPLE_IAP_ENVIRONMENT',
      defaultValue: 'Production',
    ),
  );

  final ApplePurchaseEnvironment apple;
  final String firebaseEnvironment;
  final String entitlementSource;
  final String firebaseProjectId;
  final String validationEndpoint;
  final String firebaseApiKey;
  final String firebaseAppId;
  final String firebaseMessagingSenderId;
  final String firebaseStorageBucket;
  final String? declaredAppleEnvironment;

  bool get isSandbox => apple == ApplePurchaseEnvironment.sandbox;
  String get appleName => isSandbox ? 'Sandbox' : 'Production';
  String get scope => isSandbox ? 'sandbox' : 'production';

  String? get configurationError {
    if (declaredAppleEnvironment != null &&
        declaredAppleEnvironment != appleName) {
      return 'The Apple purchase environment is invalid.';
    }
    final expectedFirebase = isSandbox ? 'Sandbox' : 'Production';
    final expectedSource = isSandbox ? 'apple_sandbox' : 'production';
    if (firebaseEnvironment != expectedFirebase || entitlementSource != expectedSource) {
      return 'Store, Firebase, and entitlement environments do not match.';
    }
    if (!_validProject(firebaseProjectId) ||
        (!isSandbox && firebaseProjectId != productionProjectId) ||
        (isSandbox && firebaseProjectId == productionProjectId)) {
      return 'The Firebase project does not match this purchase environment.';
    }
    final uri = Uri.tryParse(validationEndpoint);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.query.isNotEmpty ||
        uri.host != 'us-central1-$firebaseProjectId.cloudfunctions.net' ||
        uri.path != '/validateReceipt') {
      return 'The purchase validation endpoint does not match the Firebase project.';
    }
    if (isSandbox && [
      firebaseApiKey,
      firebaseAppId,
      firebaseMessagingSenderId,
      firebaseStorageBucket,
    ]
        .any((value) => value.trim().isEmpty)) {
      return 'The sandbox Firebase app configuration is incomplete.';
    }
    return null;
  }

  bool get isCoherent => configurationError == null;

  FirebaseOptions firebaseOptions(FirebaseOptions production) {
    if (!isSandbox) return production;
    return FirebaseOptions(
      apiKey: firebaseApiKey,
      appId: firebaseAppId,
      messagingSenderId: firebaseMessagingSenderId,
      projectId: firebaseProjectId,
      storageBucket: firebaseStorageBucket.isEmpty ? null : firebaseStorageBucket,
      iosBundleId: bundleId,
    );
  }

  static bool _validProject(String value) =>
      RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$').hasMatch(value);
}
