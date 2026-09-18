import 'package:are_coach/core/legal_versions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('checkConsentStatus', () {
    test('returns reconsentNeeded for an older stored version', () {
      final result = checkConsentStatus(
        storedVersion: '2025-01-01',
        currentVersion: kTermsVersion,
      );

      expect(result, ConsentStatus.reconsentNeeded);
    });

    test('returns current for a matching version', () {
      final result = checkConsentStatus(
        storedVersion: kTermsVersion,
        currentVersion: kTermsVersion,
      );

      expect(result, ConsentStatus.current);
    });

    test('returns reconsentNeeded when nothing was ever stored', () {
      final result = checkConsentStatus(
        storedVersion: null,
        currentVersion: kTermsVersion,
      );

      expect(result, ConsentStatus.reconsentNeeded);
    });
  });

  test('kTermsVersion and kPrivacyVersion are non-empty', () {
    expect(kTermsVersion, isNotEmpty);
    expect(kPrivacyVersion, isNotEmpty);
  });

  test('TermsAssent defaults to the current versions', () {
    const assent = TermsAssent();
    expect(assent.termsVersion, kTermsVersion);
    expect(assent.privacyVersion, kPrivacyVersion);
  });
}
