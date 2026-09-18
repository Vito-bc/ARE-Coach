/// Single source of truth for which version of the Terms of Service and the
/// Privacy Policy a fresh acceptance refers to. Bump these when the
/// corresponding document's "Effective" date in docs/*.html changes. This
/// file does not define the legal text itself (see docs/terms-and-conditions
/// .html and docs/privacy-policy.html) -- only which version a stored
/// acceptance points at.
const kTermsVersion = '2026-06-03';
const kPrivacyVersion = '2026-06-03';

/// A record of a user's assent to both documents, captured on-screen (see
/// TermsAssentCheckbox) and written verbatim to the user's Firestore
/// document by AuthService at account creation.
class TermsAssent {
  const TermsAssent({
    this.termsVersion = kTermsVersion,
    this.privacyVersion = kPrivacyVersion,
  });

  final String termsVersion;
  final String privacyVersion;
}

/// Whether a previously stored acceptance version is stale relative to the
/// version currently in force.
///
/// This is deliberately NOT wired into any screen or sign-in flow yet -- no
/// caller invokes it, so no existing user is re-prompted or gated by it. It
/// exists only so a future re-consent flow has a ready, tested comparison to
/// build on; building that flow is out of scope here.
enum ConsentStatus { current, reconsentNeeded }

ConsentStatus checkConsentStatus({
  required String? storedVersion,
  required String currentVersion,
}) {
  return storedVersion == currentVersion
      ? ConsentStatus.current
      : ConsentStatus.reconsentNeeded;
}
