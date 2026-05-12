# ARE-Coach — Code & Architecture Review

**Reviewer:** Pro-developer / pro-architect pass
**Date:** 2026-05-10
**Scope:** `ARE-Coach/` (active codebase). Archive folder excluded.
**Stack:** Flutter 3 (Dart 3.8), Firebase (Auth, Firestore, App Check, Crashlytics), Cloud Functions (Node 22), Gemini, in_app_purchase, Hive, Riverpod, flutter_local_notifications, speech_to_text / flutter_tts.

---

## Executive summary

ARE-Coach is in surprisingly good shape for an MVP: clean three-layer separation (screens / services / models), Firestore rules that actually scope by `uid`, App Check wired on both client and function, a Cloud Function that gates AI usage with atomic quotas + a server-side secret, and a respectable 700+ lines of unit/widget tests covering the most important business logic (`computeReadiness`, `computeSectionTrends`, auth flows, paging). Documentation in `docs/` is unusually mature for a one-developer app and the README + question-bank citations show care.

The launch-blocking issues are concentrated in a few specific places:

1. **Apple Sign-In is broken / insecure** — the rawNonce is replaced by the authorizationCode when constructing the Firebase credential. Sign-in will either fail outright or, if Firebase doesn't enforce nonce verification on that path, the flow becomes vulnerable to replay.
2. **In-app purchase has no server validation path wired up.** The `validateReceipt` Cloud Function exists, but no Dart code ever calls it. Users who "buy Premium" stay `role: free` server-side and `askCoach` will still hit the 10/day free quota. The paywall is a UX shell on top of nothing.
3. **Onboarding/splash run on every cold start** — there is no persisted "seen onboarding" flag, and the splash hard-codes a 3-second `Timer`. First impression is also the second impression.
4. **Several state-management & memory hygiene defects** — uncancelled `StreamSubscription`s on `IAPService.purchaseUpdates`, an `IAPService.initialize()` that can register multiple listeners on the same plugin stream, a `PageController` that is never `dispose()`d, and demo-data fallbacks in `progress_repository` that masquerade as real data on real Firestore errors.

Beyond those, there is a long tail of medium-severity issues (error swallowing with bare `catch (_)`, unicode/encoding corruption in user-facing strings, defensive fallbacks that mask real failures with fake data, IAP that doesn't restore entitlements anywhere, a `7.99` price hard-coded in the README that doesn't match anything in code) — listed below.

**Recommended release gate:** fix the four items above + verify the fixes via emulator + add three integration tests (auth, purchase->premium, askCoach) before submitting to App Store / Play. The rest can ship as v1.0.1.

---

## Severity legend

- **P0 — Blocks release / data-loss / security** (5 findings)
- **P1 — Must-fix soon / correctness or revenue loss** (10 findings)
- **P2 — Quality / future-debt** (12+ findings)
- **N — Nit / style** (sprinkled)

---

## 1. Architecture

### Strengths
- Clear layer split: `screens/ → services/ → models/`, with `core/` for cross-cutting concerns. No screens reach into other screens' state.
- `QuestionRepository` has a robust three-tier fallback: Firestore → bundled JSON → 3-question seed. The 3-second Firestore timeout (`question_repository.dart:29`) is exactly the right pattern.
- `Result<T>` sealed class (`core/result.dart`) is used consistently for the coach service — better than throwing across UI boundaries.
- App Check, Crashlytics, and the secret-managed Gemini key are correctly server-side.
- Firestore rules are scoped by `request.auth.uid`, `users` doc has a `hasOnly` allow-list for client-writable keys, and `subscriptions/usage` writes are admin-only.
- Functions enforce quotas inside a Firestore transaction (`functions/index.js:248`) — race-safe.
- CI runs `flutter analyze` and `flutter test` on every PR to `main`.

### Weaknesses

**[P1] Riverpod usage is shallow and inconsistent.** Only two providers exist (`core/providers.dart`) and most screens still hold their own service instances as `final _service = ...` in `State`. Examples:
- `_TestsScreenState` instantiates `ProgressRepository()` directly (`tests_screen.dart:35`).
- `_ProfileScreenState` instantiates `IAPService()` directly (`profile_screen.dart:30`).
- `_AttemptHistoryScreenState` instantiates `ProgressRepository()` directly.
- `_CoachScreenState` instantiates `CoachService()` and `VoiceService()` directly.

Result: tests must inject via constructor (works), but you can't swap implementations in widget tests of these screens, and you can't fake Firebase without booting it. Move services behind Riverpod providers (or get_it) — the pattern is already set up for the dashboard, finish it everywhere.

**[P2] `dashboardMetricsProvider` invalidation works, but is fragile.** `tests_screen.dart:154` calls `ref.invalidate(dashboardMetricsProvider)` against the family object. Riverpod 2.x does invalidate all family instances in this case, so it works today — but the intent is unclear from the call site, and the provider is `family + not autoDispose`, so the cache persists across tab switches. Prefer either: (a) `ref.invalidate(dashboardMetricsProvider((uid: uid, firebaseReady: true)))` so the dependency is explicit, or (b) convert to a `Notifier` family that you mutate after `saveAttempt`. The current code is also reading `FirebaseAuth.instance.currentUser?.uid` inside the consumer rather than from a provider — wrap auth in a `StreamProvider<User?>` so UI rebuilds automatically on sign-out.

**[P1] Navigation uses string routes for splash/onboarding/home but `Navigator.of(context).push(MaterialPageRoute(...))` for the rest (paywall, history, NCARB calculator).** Pick one. Routes-by-name is fragile for typed args; consider migrating to GoRouter or just use direct `push(MaterialPageRoute(...))` everywhere. Today the app's named-route table doesn't include `LoginScreen.routeName`, even though the constant is declared (`login_screen.dart:19`).

**[P2] Two competing app bootstrap paths.** `main.dart` decides routing (login vs. ArchiEdApp) and `app.dart` separately owns the routes table (splash → onboarding → home). Result: when `firebaseReady && user != null`, you bypass the splash AND onboarding entirely and go straight to home. When `!firebaseReady`, you go through splash → onboarding → home — so the experience for "demo" users is different from authenticated users, with no shared first-run logic. Consolidate into one `ArchiEdRouter` and persist "seenOnboarding" so it's shown exactly once.

**[P2] No domain layer.** `progress_repository` does both data access AND analytics computation (readiness/trend stats). That's OK at MVP scale but as features grow you'll want a `lib/domain/` with pure functions and a thin repository. The `@visibleForTesting static` methods (`computeReadiness`, `computeSectionTrends`) are a code smell — those are pure functions; promote them to their own file outside the repository.

**[P2] Firestore writes from the client for `attempts/` and `analytics/`** are still allowed by the rules. Your own SECURITY_AUDIT.md flags this as MVP-acceptable but tamperable. A modified client can inflate `correctCount` and `score` and write straight to `attempts/{uid}/sessions/...`. Realistic risk is low (vanity metric), but if you ever use the readiness score as a Premium up-sell trigger or leaderboard, move attempt writes server-side.

---

## 2. Security & auth

### [P0] Apple Sign-In nonce is wrong (`auth_service.dart:60-93`)

```dart
final rawNonce = _generateNonce();
final nonce = _sha256ofString(rawNonce);
return SignInWithApple.getAppleIDCredential(..., nonce: nonce);
```

The function correctly generates `rawNonce`, hashes it, and sends the hash to Apple. But when constructing the Firebase credential:

```dart
final oauthCredential = OAuthProvider('apple.com').credential(
  idToken: appleCredential.identityToken,
  rawNonce: appleCredential.authorizationCode,  // ← wrong
);
```

It passes `authorizationCode` instead of the original `rawNonce`. The authorization code is *not* the nonce — it's a one-time code Apple returns for server-side exchange. Two consequences:

- Best case: Firebase rejects the credential because SHA-256(authorizationCode) ≠ the nonce embedded in the JWT, and Apple Sign-In always fails on iOS/macOS.
- Worst case (depending on Firebase backend behavior): the nonce check is silently skipped and the flow becomes replayable.

Same bug in `linkAnonymousToApple` (`auth_service.dart:73-93`).

**Fix.** Hoist `rawNonce` so it's available at credential-creation time:

```dart
Future<({AuthorizationCredentialAppleID credential, String rawNonce})>
    _requestAppleCredential() async {
  final rawNonce = _generateNonce();
  final hashed = _sha256ofString(rawNonce);
  final credential = await SignInWithApple.getAppleIDCredential(
    scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
    nonce: hashed,
  );
  return (credential: credential, rawNonce: rawNonce);
}

Future<User?> signInWithApple() async {
  // …
  final (:credential, :rawNonce) = await _requestAppleCredential();
  final oauthCredential = OAuthProvider('apple.com').credential(
    idToken: credential.identityToken,
    rawNonce: rawNonce,
  );
  // …
}
```

Add a regression test using a captured argument mock.

### [P1] `verifyAppCheck` is only enforced on `askCoach`, not on `validateReceipt` (`functions/index.js:78-167`)

The receipt-validation endpoint should require an App Check token too — otherwise a stolen ID token + a hand-rolled HTTP client can hit `validateReceipt` and (in the future, when wiring is fixed) flip a user to `premium`. Add the same `await verifyAppCheck(req)` call right after `verifyBearerToken`.

### [P1] `enforceUsageLimits` debits before the AI call (`functions/index.js:243-288`)

If `generateCoachAnswer` returns a fallback because Gemini was unavailable, the user is still charged a daily/minute quota slot but received the canned response. Either:
- Charge after a successful Gemini reply (move the transaction below `generateCoachAnswer`, with care for the race), or
- Detect `model === 'fallback'` and roll back the increment with a follow-up transaction, or
- Don't count fallback responses against quota (probably the right answer for paying users).

### [P1] `validateReceipt` only handles iOS (`functions/index.js:99-101`)

It returns 400 for any non-iOS platform. If you ship Android with `in_app_purchase`, Play Store receipts go through Google Play Developer API (`androidpublisher`), not Apple. Either add Android verification or remove Android from the storefront for v1.

### [P2] Free vs. premium daily limits inconsistent (`functions/index.js:12-13` vs. `README.md:188`)

- README advertises "Free tier: 10 questions/day, 50 AI coach messages/day".
- Function code enforces `FREE_DAILY_LIMIT = 10` and `PREMIUM_DAILY_LIMIT = 200`.

Either fix the README (current behavior is 10 free messages) or change the constants. Make sure App Store/Play submissions match the actual enforced limit, not the README.

### [P2] `isAnonymous` returns `true` when there is no user (`auth_service.dart:24`)

`bool get isAnonymous => _auth.currentUser?.isAnonymous ?? true;`

Semantically wrong (no user ≠ anonymous user) and the tests bake this in (`auth_service_test.dart:86-88`). Code that uses `isAnonymous` to decide UI ("upgrade your guest account") will treat signed-out users as guests. Rename to `isAnonymousOrSignedOut`, or fix the default and update callers.

### [P2] Firestore rule mismatch with client write (`firestore.rules:84-87`)

The `reports` rule requires `keys().hasAll(['uid','questionId','reason','status','createdAt'])` but `report_repository.dart:44-53` always writes `questionText` and optionally `comment`. `hasAll` allows extra keys, so this works — but if you ever tighten to `hasOnly` you'll silently break flagging. Either tighten the rule and add `questionText`/`comment` to the allow-list, or document that extras are accepted.

### [P2] `_ensureUserRecord` failures are silently swallowed (`auth_service.dart:124-142`)

If Firestore is throttled or unreachable during sign-in, the user record never gets written, and the function reports success. Subsequent `users/{uid}` reads will return `null` and gracefully fall back, but the user's entitlement (`role: free`) is never persisted, so the Cloud Function's `getEntitlement` will assume free even for users who later upgrade. At minimum: `FirebaseCrashlytics.instance.recordError(e, stack, fatal: false)`.

### [P2] Apple/Firebase token leakage in logs (`functions/index.js:50-60`)

`logger.info("coach_request", { uid, ... })` — `uid` in logs is fine (it's an opaque identifier). Just make sure you don't ever start logging `req.body` or `prompt` as-is; right now you don't, which is correct. Add an explicit comment to keep it that way.

### [N] Web App Check uses an empty reCAPTCHA key (`main.dart:35-37`)

If `RECAPTCHA_SITE_KEY` isn't defined at build time, you pass `ReCaptchaV3Provider('')`. That'll either throw on activation (caught by the bare `catch (_)`) or register a non-functional provider. Cleaner: skip activation entirely for web when the key is empty, and log to Crashlytics so you notice.

---

## 3. In-app purchase / monetization

### [P0] Receipt validation is never invoked from the client

`functions/index.js` exports `validateReceipt`. The Dart side (`iap_service.dart`, `paywall_screen.dart`) never touches it.

```dart
void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
  for (final purchase in purchases) {
    if (purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored) {
      if (purchase.pendingCompletePurchase) {
        _iap.completePurchase(purchase);
      }
      _purchaseController.add(purchase);  // ← no receipt POST anywhere
    }
    // …
  }
}
```

The paywall shows "Welcome to Premium!" via SnackBar (`paywall_screen.dart:66-69`), but `users/{uid}.role` is never updated, so `getEntitlement` in the Cloud Function still treats the user as free. **End result: people pay and stay on the free tier.** This is the single biggest revenue/UX risk in the codebase.

**Required steps:**
1. After `completePurchase`, call `validateReceipt` with `receiptData: purchase.verificationData.serverVerificationData` and the user's ID token.
2. Only treat the purchase as success once the function returns `{ valid: true }`.
3. On failure, do not call `completePurchase` until validation succeeds (you may need to retry on next launch — track in Hive that a purchase is awaiting validation).
4. Add a Premium banner / badge that reads from `users/{uid}.role` (StreamProvider) so UI reflects the truth-of-record.

### [P1] No restore path back to entitlement (`paywall_screen.dart:108`)

`restorePurchases()` just triggers a re-emission to the purchase stream, but since you never validate on the server, "Restore" doesn't actually restore Premium server-side. After fixing P0, make sure restore also calls validateReceipt with the latest receipt.

### [P1] `IAPService` is instantiated per-screen (`profile_screen.dart:30`, then passed to `PaywallScreen`)

The plugin's purchase stream is global — listening to it from a screen that may not be alive when the purchase resolves means lost confirmations (the user backs out of the paywall while StoreKit is processing, comes back, and the SnackBar never fires). Initialize `IAPService` once at app bootstrap (in `ArchiEdBootstrap`) and provide it via Riverpod. Always validate receipts in the background, not in a screen.

### [P1] `IAPService.initialize()` leaks subscriptions (`iap_service.dart:20-30`)

If `initialize()` is called twice (e.g., the user closes and reopens Profile), a second `_iap.purchaseStream.listen(...)` registers, but the prior `_subscription` reference is overwritten without `.cancel()`. Guard with `if (_subscription != null) return;` or always `await _subscription?.cancel()` first.

### [P1] `PaywallScreen` never cancels its `purchaseUpdates` listener (`paywall_screen.dart:34`)

`widget.iapService.purchaseUpdates.listen(_onPurchaseUpdate);` is called in `initState` but never cancelled. If the user opens the paywall, dismisses without buying, then the underlying stream emits later, your stale closure calls `setState` on a disposed state object. Hold the `StreamSubscription` and `cancel()` in `dispose`.

### [P2] Local subscription expiry / grace handling

The Cloud Function trusts Apple's `expires_date_ms` and writes it to `premiumUntil`. The function exposes no scheduled job to mark users `free` once `premiumUntil` lapses; today this only happens reactively the next time `validateReceipt` is called. Once you wire client validation, also schedule an Apple Server-to-Server notification handler (`subscriptionStatusChanged`) — Apple now sends these via App Store Server Notifications v2 instead of waiting for client polling.

### [P2] README claims pricing ($7.99/mo) that isn't anywhere in code (`README.md:188-191`)

Price is fetched from the store dynamically (good), but the README hard-codes $7.99 which doesn't match the `_features` copy or any product config. Either remove or move it to a single source of truth so QA can spot drift.

### [P2] Paywall sort puts monthly first regardless of selection (`paywall_screen.dart:46-49`)

`a.id == kMonthlyId ? -1 : 1` — this is non-transitive (it doesn't define a relative order for two non-monthly items). With only two products this works; if you ever add a third tier, the sort is undefined. Use an explicit ordering map.

---

## 4. State management & memory hygiene

### [P1] `OnboardingScreen._controller` is never disposed (`onboarding_screen.dart:16`)

```dart
final _controller = PageController();
```

Add `@override void dispose() { _controller.dispose(); super.dispose(); }`. Same screen also never persists "onboarding seen", so users see it on every launch (P1 — see "Architecture / two bootstrap paths").

### [P1] `CoachScreen` listens to its own `purchaseUpdates`-equivalent without bookkeeping

`coach_screen.dart` itself is OK, but note that any future addition of `purchaseUpdates`-style streams should hold a `StreamSubscription` field and cancel it in `dispose`.

### [P1] `progress_repository.fetchAttemptHistoryPage` returns fake data on Firestore errors (`progress_repository.dart:280-296`)

```dart
final fallback = List.generate(5, (i) => AttemptHistoryItem(
  id: 'demo_$i', mode: 'section', score: 55 + (i * 6), ...));
return const AttemptHistoryPage(items: [], hasMore: false).copyWith(items: fallback);
```

On a real Firestore failure for a signed-in user, the History screen renders five **fake** attempts as if they were real. That's confusing for the user, hostile to QA, and impossible to triage from Crashlytics. Same pattern in `fetchDashboardMetrics` (`progress_repository.dart:216-242`) which silently returns canned weak sections (Project Management 31%, etc.). **Fallback to demo data only when `firebaseReady == false`. On a real failure, surface an error state.**

### [P2] `home_shell.dart` rebuilds all four screens on every tab switch (`home_shell.dart:48-50`)

`screens[_index]` is computed inside `build`, so every tap reconstructs the off-screen widgets via `_HomeShellState.build` — relatively cheap but means `DashboardScreen`, `TestsScreen`, etc. lose their internal state when navigated away. Use an `IndexedStack` for cheap state preservation, or `PageView` with `AutomaticKeepAliveClientMixin`.

### [P2] `SplashScreen` uses a hard-coded 3-second `Timer` (`splash_screen.dart:21`)

Three seconds is a long time. Either:
- Cut to 1 second + a fade transition, or
- Replace with "wait for first frame of next route", which is what most production apps do.

Also: there's no guard against `Navigator.pushReplacementNamed` being called after a hot-restart that already replaced the splash.

### [P2] `_TestsScreenState` doesn't dispose `_progressRepository` (`tests_screen.dart:35`)

`ProgressRepository` doesn't currently hold disposable resources, but if you ever add a connection / subscription, you'll silently leak. Move to provider.

### [P2] `dashboardMetricsProvider` is intentionally non-autoDispose (`core/providers.dart:11-12`) — fine, but combined with the `family` invalidation bug above, the cache outlives data freshness.

---

## 5. UX / correctness

### [P1] Onboarding shown on every cold start (no persisted flag)

There is no `Hive.box('settings').get('onboarded')` check anywhere. Symptom: returning users see the same 3-slide marketing carousel every launch.

```dart
// Suggested
final box = await Hive.openBox('settings');
final onboarded = box.get('onboarded', defaultValue: false) as bool;
if (onboarded) {
  // pushReplacement(HomeShell.routeName);
} else {
  // … finish onboarding then `box.put('onboarded', true)`.
}
```

### [P1] Mojibake in user-facing strings

Several files contain corrupted bytes (likely a Windows / UTF-8 encoding incident):

- `tests_screen.dart:434` — `'� ${(questionCount * 1.5).round()} minutes'` (replacement glyph U+FFFD)
- `_test_result_screen.dart:68` — `'Passing � great work!'`
- `_test_result_screen.dart:70` — `'Almost there � keep studying'`
- `coach_service.dart:26` — `'10-15 point'` (was probably en-dash)
- A handful of comment glyphs in `tests_screen.dart` decorative dividers

Open the affected files with explicit UTF-8 and replace with the right characters (em-dash `—`, en-dash `–`, etc.). Add `flutter analyze` strict-string-encoding once Dart supports it, or hook a pre-commit `grep -P "\\xEF\\xBF\\xBD"`.

### [P1] `flutter_riverpod` is imported but the app uses `StatefulWidget + setState` in most screens

If you're going to keep Riverpod, lean into it; otherwise drop the dependency. Mixed paradigms are confusing for the next maintainer.

### [P2] `pushReplacementNamed(HomeShell.routeName)` from "Sign In" button on onboarding goes to home without authenticating (`onboarding_screen.dart:243-247`)

Button is labeled "Sign In" but actually does the same as "Start Free" — pushes home. Either remove the button, or route to `LoginScreen` (which currently isn't in the routes table; you'd need to add it).

### [P2] `_LoginScreen` Apple button's "disabled while loading" state is `() {}` not `null` (`login_screen.dart:326`)

`SignInWithAppleButton(onPressed: loading ? () {} : onApple, …)` — passing a no-op closure shows the button as enabled. Accessibility services announce it as tappable. Pass `null` when loading, and let the button render in its disabled state.

### [P2] Coach screen's "demo scenario" button is dead code in live mode

`_runDemoScenario` exists (`coach_screen.dart:124-139`) but I can't tell from the snippet I read whether it's still surfaced in the UI. If it's still surfaced when `CoachService.isLive == true`, hide it; it confuses test users.

### [P2] `tests_screen.dart` summary contains stray `_TestsScreenState` reference (`tests_screen.dart:339, 364, 678`)

`TestsScreenStateConfig` is an `abstract final class` that just re-exposes private state constants. This is a workaround that suggests the constants should live outside `_TestsScreenState` from the start. Promote `sections` and `sectionIcons` to top-level `const` values.

### [N] `_emptyMetrics` in `DashboardScreen` (`dashboard_screen.dart:15-20`) defaults `readinessPercent: 0` — but the Firestore failure fallback in repository returns 42. UX is inconsistent: a logged-out user sees 0%, a logged-in user with a transient Firestore error sees 42%.

### [N] Profile shows `'Free plan'` hard-coded (`profile_screen.dart:135`) — even for Premium users. After fixing the IAP wiring this will mislead paying users.

### [N] `_LoginScreen._showApple` hides Apple Sign-In on macOS (it shouldn't — Sign In with Apple is fully supported on macOS): currently `defaultTargetPlatform == TargetPlatform.iOS || TargetPlatform.macOS`, so macOS is included. Verify your Xcode capabilities for the macOS target include "Sign In with Apple"; if not, sign-in will fail at runtime.

---

## 6. Tests & quality gates

### Strengths
- 700 LOC of tests covering models, the most important repository computations, auth flows, login screen rendering, and the test-session UI.
- CI runs on every PR.
- Good use of mocktail; `_stubFirestore` is reusable.
- `@visibleForTesting` correctly applied to pure compute functions.

### Gaps

**[P1] No test exists for the IAP flow.** This is the area with the most revenue risk and the most recently added code.

**[P1] No test for the Apple sign-in nonce.** If you fix the P0 bug and don't add a regression test, you will regress. Mock `OAuthProvider` invocation and assert that `rawNonce` passed to it equals the `rawNonce` used to compute the hash sent to Apple.

**[P1] No emulator tests for Firestore rules.** The SECURITY_AUDIT.md flags this as a release-gate item; it isn't done. Add `@firebase/rules-unit-testing` tests under `functions/` (or a sibling node project) and run them in CI.

**[P2] `widget_test.dart` is a placeholder.** It pumps `ArchiEdApp(firebaseReady: false)` for 4 seconds and asserts nothing. Either delete or assert: `expect(find.text('ArchiEd Education'), findsOneWidget);`.

**[P2] Integration test is also a placeholder** (`integration_test/app_bootstrap_test.dart` — just `pumpAndSettle`). Real integration coverage = pick a flow ("take a 5-question quick quiz → see result"), drive it with the integration_test harness, run on a real device matrix at least once before each release.

**[P2] No analyzer customizations.** `analysis_options.yaml` only `include:`s `flutter_lints`. Recommend turning on at minimum: `prefer_const_constructors`, `prefer_const_literals_to_create_immutables`, `avoid_unnecessary_containers`, `require_trailing_commas`, `unawaited_futures` (catches missing `await` on `await box.put`-type calls). This is "free quality" in CI.

**[P2] No `dart format --output=none --set-exit-if-changed .` step in CI.** PRs can land with inconsistent formatting.

**[P2] Functions has no tests (`functions/package.json` lint script literally echoes "No lint configured").** Add jest or vitest tests for `enforceUsageLimits`, `getEntitlement`, and the Apple receipt-status branching.

---

## 7. Performance

**[P2] `QuestionRepository.loadFromAsset` shuffles every time it's called** (`question_repository.dart:60-69`). The provider caches the list, so today this only runs once — but anyone who calls the repository directly (which `TestsScreen` does for filtering) will reshuffle on each call. Consider returning an immutable list and shuffling at the call site.

**[P2] `tests_screen.dart:80` shuffles the full list, then takes N.** For a 213-question bank this is fine, but if the bank grows you're shuffling everything to keep 5–60. `Random` + index pick or a Fisher-Yates of only first N is cheaper.

**[P2] `progress_repository.saveAttempt` writes a single sessions doc with the entire `questionResults` array inline** (`progress_repository.dart:159-168`). For a 60-question timed exam, that's ~60 maps in one doc. Firestore docs are capped at 1 MB; you're nowhere near it, but it makes querying by question (e.g., "what's my history on q42?") impossible. Once you have analytics needs beyond "weak sections", split into a `questionAttempts` subcollection.

**[N] `ProfileScreen` does an extra `Hive.openBox('settings')` round-trip on every visit** (`_loadReminderPref`). Cache in a provider.

---

## 8. Dependencies & release readiness

### Dependency hygiene
- All Firebase libraries on relatively current 2024-era versions.
- `speech_to_text: ^6.6.1` — there is a `7.x` line; check changelog for permission flow improvements.
- `firebase_app_check: ^0.3.2+4` — still 0.x; pin precisely and watch for breaking changes.
- `flutter_lints: ^5.0.0` and `flutter_test` — fine.
- No `freezed`, `json_serializable`, or `riverpod_generator` despite Riverpod usage. Adding code generation would simplify provider scopes.

### Release checklist (pre-launch)

| Item | Status |
|---|---|
| Apple Sign-In nonce fix + test | ❌ |
| IAP receipt validation wired client → function | ❌ |
| `validateReceipt` requires App Check token | ❌ |
| `validateReceipt` supports Android (or Android disabled) | ❌ |
| Onboarding "seen" flag persisted | ❌ |
| Mojibake strings cleaned | ❌ |
| Firestore rules emulator tests in CI | ❌ |
| Crashlytics enabled (✓ done) + opt-in dialog if required by region | Partial |
| Apple privacy nutrition label written | Unknown |
| App Store IAP product IDs registered (`are_coach_monthly`, `are_coach_yearly`) | Unknown |
| Apple S2S notifications endpoint stood up | ❌ |
| `dashboard_screen` empty/error states correct (no fake 42%) | ❌ |
| `SCHEDULE_EXACT_ALARM` removed (you use `inexactAllowWhileIdle`) | ❌ |
| Privacy policy + terms-of-service URLs reachable and current | ✓ (linked in profile) |

### Android-specific
- `AndroidManifest.xml` declares `SCHEDULE_EXACT_ALARM` but `notification_service.dart:107` uses `AndroidScheduleMode.inexactAllowWhileIdle`. Drop the permission (Play Console will ask you to justify it).
- No `com.android.vending.BILLING` permission visible (Flutter's `in_app_purchase` plugin merges it, but verify in the built APK with `aapt dump permissions`).
- Min SDK 21 is fine; consider raising to 24 to drop multidex special cases.

### iOS-specific
- `Info.plist` includes correct usage strings for Microphone and Speech Recognition. Good.
- `Info.plist` allows landscape on iPhone — fine for a study app.
- No `NSUserTrackingUsageDescription` — fine since you don't run IDFA-using SDKs. If you ever add a crash/analytics SDK that touches IDFA, this becomes a submission blocker.
- Bundle id `com.archedu.architectulaEducationApp` — consider shortening to `com.archedu.arecoach`; the current id telegraphs an internal codename.

---

## 9. Prioritized action list (one developer, two-week sprint)

**Day 1–2 (security & revenue blockers)**
1. Fix Apple nonce bug + test. *(2 h)*
2. Wire `validateReceipt` from client; gate Premium UI on `users/{uid}.role` stream. *(1 day)*
3. Add `verifyAppCheck` to `validateReceipt`. *(15 min)*

**Day 3–4 (UX + state)**
4. Persist `onboarded` flag in Hive; unify bootstrap so splash → onboarding runs once. *(3 h)*
5. Move `IAPService` to a Riverpod provider initialized at app start, cancel subscriptions in `dispose`. *(3 h)*
6. Replace silent demo-data fallbacks in `progress_repository` with an explicit error state when `firebaseReady`. *(2 h)*
7. Dispose `OnboardingScreen` `PageController`; fix Apple-button disabled state. *(30 min)*

**Day 5 (correctness & cleanup)**
8. Remove mojibake strings, add a CI grep guard. *(1 h)*
9. Remove `SCHEDULE_EXACT_ALARM`, verify notification still fires on Android 13+. *(1 h)*
10. `analysis_options.yaml`: turn on `prefer_const_*`, `unawaited_futures`, `require_trailing_commas`. *(30 min)*
11. Fix `_LoginScreen` Apple disabled state + `_showApple` macOS check. *(20 min)*

**Day 6–8 (tests & gates)**
12. Add IAP integration test (mock plugin). *(0.5 day)*
13. Add Firestore rules emulator tests. *(1 day)*
14. Add cloud-function jest tests for entitlement + quota. *(0.5 day)*

**Day 9–10 (release)**
15. Run on real device matrix; verify Crashlytics + App Check token flow end-to-end.
16. Cut release branch, submit to TestFlight/Internal Testing.

---

## 10. Things you did well (worth keeping)

- The three-tier question fallback (`Firestore → JSON → seed`) — exemplary for offline-tolerant mobile.
- App Check is set up correctly for both prod and dev (graceful degrade on activation failure).
- Atomic quota in a Firestore transaction is a textbook implementation.
- Firestore rules with `hasOnly` allow-list for user-writable fields — many MVPs ship with `request.auth != null` and call it a day.
- Crashlytics is wired into both `FlutterError.onError` and `PlatformDispatcher.onError` — covers async errors that the simple wiring misses.
- Tests use mocktail consistently and stub Firestore correctly.
- Docs/ folder includes ARCHITECTURE, SECURITY_AUDIT, MONETIZATION_PREP, PHASE4_BACKEND — most one-person projects skip this entirely.
- Question bank is well-cited and traceable to public standards (AIA, IBC, NYC Building Code, ASCE, ASHRAE) — the README's reference table is a quality signal that will help with App Store review.

---

*Reviewed against the codebase as of 2026-05-10. If you'd like, the next pass can be: (a) producing the actual patches for the P0/P1 items, or (b) writing the Firestore rules emulator test suite.*
