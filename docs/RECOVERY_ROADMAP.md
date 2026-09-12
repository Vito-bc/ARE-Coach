# ARE Coach recovery roadmap

Updated: 2026-09-12. Scope of this iteration: **PR #50 follow-up: purchase
lifecycle and validation safety**. The supplied September recovery plan and
its April research comparison are the planning inputs; competitor claims and
readiness percentages have not been independently re-audited here.

## Baseline and evidence

| Layer | Verified state |
| --- | --- |
| Remote main | `8404ecc6f34e05d0fb350bd8b47db6a3e099faa6`, PR #50 squash merge |
| PR #50 | [Merged](https://github.com/Vito-bc/ARE-Coach/pull/50) at 2026-09-11 23:02 UTC; reviewed head remained `081a4f9c7425948e9d87288f78e739a9ed894273` |
| Working base | Exact PR head above. Its Git tree `e6f6431…` equals the merged main tree, so this local follow-up is content-current despite the squash SHA. |
| Local branch | `codex/iap-apple-validation-followup`, isolated from current `origin/main` at `8404ecc6f34e05d0fb350bd8b47db6a3e099faa6`; the original dirty `codex/iap-lifecycle-followup` checkout remains preserved |
| Baseline CI | [All three jobs passed on the exact PR head](https://github.com/Vito-bc/ARE-Coach/actions/runs/34532327495): Analyze and test, Content checks, Cloud Functions tests |
| Earlier Cloud report | 105 Flutter tests, 40 Functions tests, npm audit reduced from 13 findings (one critical) to eight moderate; reported historical evidence, not device validation |

Main now contains PR #50's Play subscriptionsv2 validator, receipt decision
modules, default-off Android flag, paywall stream error handling, dependency
repairs, runbook and tests. The merge happened during this follow-up task. Its
tree is identical to the local base tree; this diff preserves that implementation
and does not reimplement Play Billing.

This follow-up changes code, tests and documentation only. No merge, deployment,
production secret/variable change or store account operation is part of it. No
real charges or production writes were used for testing. The public Android flag
remains default `false`.

## Purchase patch and verification levels

| Work | Implemented | Local verification | CI | Store sandbox | Production enabled |
| --- | --- | --- | --- | --- | --- |
| Play validation and dependency fixes | PR #50 only | Historical Cloud evidence; Functions gate repeated in this follow-up | PR head green | Pending | Android default off; actual external settings not inspected |
| Shared app service, early store listener, idempotent initialization | Follow-up diff | Targeted service/navigation tests | Tracked on draft follow-up PR | Pending | Not deployed |
| Missing/invalid URL fails closed; strict boolean verdict; bounded requests | Follow-up diff | Regression tests, including never-resolving HTTP | Tracked on draft follow-up PR | Pending | Not deployed |
| Cancellation, pending, empty restore, duplicate suppression and retry | Follow-up diff | Service and real paywall tests | Tracked on draft follow-up PR | Pending | Not deployed |
| Account change/disposal guard, account-scoped retry gate and authoritative entitlement refresh | Follow-up diff | Fake-account and real paywall A/B tests | Tracked on draft follow-up PR | Pending | Not deployed |
| Android acknowledgment result handling | Follow-up diff; installed adapter's result is checked explicitly | Fake Android platform test | Tracked on draft follow-up PR | Pending | Not deployed |
| Repurchase after rejected restore; consistent service/paywall purchase guard | Follow-up review correction | Service and paywall regressions | Tracked on draft follow-up PR | Pending | Not deployed |
| Browser-safe entitlement expiry with renewal/cancellation | Follow-up review correction | Monthly/yearly timer, renewal, cancellation and tab-suspension regressions; Dart2js/Chrome probe passed | Tracked on draft follow-up PR | Not applicable to local timer | Not deployed |
| Apple status and endpoint effect contract | Follow-up backend diff | Pure status/routing/timeout tests and mutation-spy endpoint tests | Tracked on draft follow-up PR | Pending | Not deployed |

Before the fix, six added regressions failed on the base: missing endpoint,
four malformed `valid` payloads, and concurrent initialization (three store
listeners). Flashcard/profile ownership, cancellation and silent empty restore
were also traced directly through their base call sites. Existing PR paywall
`onError` behavior, strict `valid:false` rejection, Play validation and default-off
release gating were preserved rather than reported as newly implemented.

Final gate results are recorded in the review receipt below. Green unit tests
do not establish that every money-path blocker is closed.

### Recovery behavior and limits

- ProviderScope owns the service; bootstrap starts it before onboarding/auth
  navigation. Profile and flashcard upsell resolve the same provider. Routes
  detach listeners without closing the store listener or HTTP client.
- Real incoming purchased/restored events require a valid HTTPS endpoint,
  captured account credentials, HTTP 200 with boolean `valid:true`, and a fresh
  server entitlement read. `role` alone is never sufficient: active status and
  future expiry are required; cached/pending Firestore snapshots grant nothing.
- A negative receipt verdict requires HTTP 200 with boolean `valid:false`,
  `outcome:not_entitled` and `transactionFinalization:not_safe`. A bare legacy
  `valid:false`, malformed body, other HTTP status, connection failure or
  timeout means validation is unavailable. This prevents the old backend shape
  from being mistaken for a safe terminal decision during a mixed rollout.
- Credentials, HTTP validation, entitlement read and completion each have a
  15-second bound. Store initiation/restore has a 45-second bound. Pending store
  payment is a visible, non-spinning state. A timeout does not cancel a remote
  server operation; late client callbacks cannot grant access to a new account.
- Retry ownership is scoped to the uid captured with the store event. Only the
  current signed-in user's unresolved entries block a new purchase. Entries for
  another uid, and entries captured while `uid == null`, are skipped before
  validation, Restore matching and paywall state changes; they are never claimed
  by the next account. Returning to the original uid restores its retry path.
  That user's own unresolved operation continues to block a duplicate charge.
- Transactions with unavailable validation or unfinished confirmation stay
  available for explicit **Restore Purchases** and in-session retry. A terminal
  `valid:false` removes only that transaction from the retry queue, so an expired
  restore cannot permanently prevent a new subscription. A timed-out
  acknowledgment reuses its underlying future;
  a failed acknowledgment may be retried. Finished transaction IDs suppress
  duplicate validation/completion/success during the session. Explicit restore
  of a finished transaction refreshes server access without completing it again.
- StoreKit terminal cancelled/failed queue entries are finished separately,
  including unknown product IDs, without any success/access grant. Unknown paid
  products now surface `unsupported_product`; they remain unfinished until a
  fulfillment/migration policy exists. Do not blindly acknowledge an undelivered
  purchase to clear the queue.
- Rejected purchased/restored transactions are deliberately **not finished**.
  The backend classification is now corrected, but its legacy App Store receipt
  verdict remains account-level and does not prove that the exact StoreKit
  `purchaseID` was processed or delivered. The response states
  `transactionFinalization:not_safe`; the client removes the item from its
  in-session retry gate so repurchase works, while StoreKit may redeliver it.
  Binding and safely finishing that transaction remains part of the StoreKit
  transport/identity task plus sandbox/device verification.
- Entitlement expiry is scheduled in intervals of at most one day, rechecking
  the absolute deadline each time. This avoids browser `setTimeout` int32
  overflow for monthly/yearly subscriptions while still revoking locally at
  expiry. Renewal, inactive/cache/error snapshots and provider disposal cancel
  the previous timer. A suspended browser can process expiry on its next callback.
- Restore remains available for recovery when Android *new sales* are disabled.
  The installed Android adapter queries purchases on explicit restore; do not
  promise that merely reopening the app will finish an outstanding purchase.
  Cold-start/store redelivery, interrupted acknowledgment, restart and real
  account-switch behavior still require device tests. In-memory suppression is
  not durable receipt ownership or cross-device idempotency.

Completion rules were checked against the installed versions (`in_app_purchase`
3.2.3, Android 0.4.0+10, StoreKit 0.4.8+1) and the
[Flutter plugin documentation](https://pub.dev/packages/in_app_purchase/versions/3.2.3),
[Google Play integration guidance](https://developer.android.com/google/play/billing/integrate)
and [Apple transaction finishing](https://developer.apple.com/documentation/storekit/transaction/finish()).
Automatic refunds are not a recovery strategy or proof of working purchases.

## Local source preservation

The existing `tools/question_audit/backups` contains local bank snapshots, but
no verified external corpus/index/workbook backup was established from it.
A timestamped copy was made **outside this repository**, before any asset edit:
`%TEMP%/ARE-Coach-recovery-20260910-174850`.

- 4,464 files / 115,050,139 bytes: corpus (including 26 PDFs), reports (including
  four workbooks), previous bank backups, grader cache and `functions/coach_index.json`.
- Every copied file's SHA-256 matched its source. Seven restore samples were
  copied back into a separate sample tree and checked, including a PDF, workbook,
  bank snapshot, cache entry and index. The local backup contains `manifest.json`.
- This is a **provisional same-disk temporary copy**. Independent durable backup
  is pending; temp retention and OneDrive sync are not verified backup guarantees.
- Corpus, index, review workbooks and historical audit documents were not edited
  or regenerated. No PDFs, extracted source text, `.env` or secrets are included
  in the review diff. Metadata-only summary: local ignored
  `build/recovery-backup-summary.json`.
- Before rebasing the follow-up, all 25 changed files were copied to
  `%TEMP%/ARE-Coach-iap-followup-snapshot-20260912-131829` and a matching zip.
  `SNAPSHOT_MANIFEST.json` records the original branch/HEAD, size and SHA-256 for
  every file; source, directory-copy and transferred-worktree hashes matched.

## Apple backend contract completed locally

`decideAppleReceipt` now accepts only an integer status and returns one of three
explicit outcomes. Status `0` proceeds to strict transaction parsing; `21006`,
`21003` and `21010` are authoritative non-entitlement. Temporary `21002`,
`21005`, `21009` and `21100–21199`, configuration `21004`, routing/protocol
errors, unknown statuses and malformed bodies are unavailable. The latter
return 502/503/504 with retryability metadata and cannot call either entitlement
mutation. Apple describes `21002` as malformed data or temporary service trouble,
so this implementation follows Apple's “try again” instruction rather than
claiming a final verdict. [Apple status definitions](https://developer.apple.com/documentation/appstorereceipts/status)

Production verification falls back to sandbox only on strict numeric `21007`,
with at most two Apple calls. Each call has a 6-second abort timeout, keeping the
two-call path inside the client's 15-second request bound. The pure
endpoint orchestrator validates decision shape, grants only `verified`, invokes
`markUserFree` only for `not_entitled`, and fails unknown decisions unavailable.
Play decisions now carry the same explicit outcome field while retaining their
existing state/token behavior.

The complete 25-file diff was reconciled against its manifest and transferred to
`codex/iap-apple-validation-followup` from current `origin/main`. No reviewed
file was lost and no PR #50 implementation was reapplied separately; the base
tree already contains it. This branch is for a separate draft follow-up PR and
must remain unmerged pending review. The next bounded implementation task is
StoreKit 2/JWS
transport plus transaction/app/account identity, which is required before safe
rejected-transaction finalization and iOS sandbox sign-off.

Other separate pre-launch money tasks:

1. **StoreKit 2 / backend transport compatibility (source-confirmed mismatch):**
   installed `in_app_purchase_storekit` 0.4.8+1 defaults to StoreKit 2
   (`lib/src/in_app_purchase_storekit_platform.dart`, `_useStoreKit2 = true`).
   Its `lib/src/store_kit_2_wrappers/sk2_transaction_wrapper.dart` maps the
   transaction JWS into `serverVerificationData`. The app forwards that value,
   while `functions/index.js::validateAppleReceipt` passes it as `receipt-data`
   to the legacy `verifyReceipt` API. There is no JWS verification route or
   explicit StoreKit 1 selection in the app. Align the client/server format,
   verify Apple signatures and app/environment identity, and add contract plus
   sandbox tests before enabling iOS sales. This is source evidence, not a
   reproduced device purchase; do not silently treat JWS as a legacy receipt.
   [Apple validation guidance](https://developer.apple.com/documentation/storekit/validating-receipts-with-the-app-store)
2. **Receipt ownership/account binding and replay:** the current handler verifies
   the authenticated UID, validates the receipt, then writes `users/{uid}` without
   a receipt/token ownership lookup in that path. Review store/transaction/app
   identity and bind ownership atomically; test account A/B and concurrent replay.
   Client epoch guards are not a substitute for this server boundary.
3. **Renewal/refund synchronization:** App Store Server Notifications v2 / Play
   RTDN (or an explicitly justified alternative), retries and reconciliation.
   Expiry checks stop access after expiry; a refund before expiry can remain
   undetected until revalidation. Notifications are not implemented here.
4. **Dependencies:** recheck the eight moderate findings reported by Cloud for
   actual release applicability. No broad npm upgrade or repeated audit was run
   in this scoped patch; neither the old count nor green tests are a current
   security sign-off.

## Remaining product and release roadmap

| Priority/workstream | Remaining work and acceptance evidence |
| --- | --- |
| Content review | Deduplicate flags by question ID; start with 15–20 unique critical questions for an architect, with sources and rationale. Record approve/fix/quarantine. Verify quarantined questions cannot enter quizzes/diagnostics and recompute objective coverage. The supplied audit's 52 consistency flags, 127 red rows and 926 distractor flags overlap and are not counts of unique bad questions. No measured content-quality percentage is claimed. |
| Honest progress and study plan | After purchase patch review, remove fabricated empty-history readiness, separate total attempts from the last-ten list, replace the constant 500 with the chosen division's real bank/progress. Then incorporate exam date, available time and weak topics. These are recovery-plan findings, not a fresh full progress audit in this task. |
| Practice and explanations | Preserve short quizzes, study/test modes, useful explanations and error review. Check source provenance, incorrect-answer rationale, topic/objective links and the next suggested practice action. |
| Offline persistence/account isolation | Asset availability is not offline result synchronization. Add durable queued saves, restart/retry without duplicate attempts; verify account-specific local progress, sign-out/delete cleanup and password recovery. Flashcard Hive/account isolation remains separate from this purchase-account guard. |
| Exam product gaps | Current mock is a multi-division diagnostic: 65 questions / 130 minutes, including NYC. Full division simulation, case studies/documents/illustrations and adaptive planning remain separately scoped gaps. Verify NCARB specifications before promising a full simulator; keep NYC coverage separate from the six ARE divisions. |
| Infrastructure | Reproduce the RAG index from preserved sources in a clean environment; verify Firebase rules, App Check, quotas, observability and a minimal beta feedback path. |
| Stores and signing | Inventory products, subscription groups/base plans, credentials, signing/provisioning and store disclosures. Verify controlled purchase/restore/entitlement/acknowledgment before public flags. Windows local tests do not verify iOS builds or store devices. |
| Platforms | Keep iOS, Android and web on the roadmap. Web checkout is unimplemented. A closed iOS beta is a possible sequence, not an approved reduction of platform scope. |
| Later scope | No redesign, video, AR/VR, community, gamification, guarantees or other competitor-feature expansion in this patch. April research is a hypothesis list, not an approved v1 specification. |

Historical sources remain unchanged: [CODE_REVIEW.md](CODE_REVIEW.md),
[ARCHITECTURE.md](ARCHITECTURE.md), [FIREBASE_PHASE2.md](FIREBASE_PHASE2.md),
[PHASE4_BACKEND.md](PHASE4_BACKEND.md), [SECURITY_AUDIT.md](SECURITY_AUDIT.md).
Use this roadmap for current priorities rather than replaying historical audit
findings as an unfiltered backlog. Release details:
[MONETIZATION_PREP.md](MONETIZATION_PREP.md) and [CI_RELEASE_BUILD.md](CI_RELEASE_BUILD.md).

## Review receipt

| Check | Final result |
| --- | --- |
| Apple backend contract tests | 36 passed: strict statuses/shapes, timeout/transport, bounded sandbox route and endpoint mutation effects |
| Client contract-targeted Flutter tests | 73 passed after the account-scoped retry correction: service, Android completion, expiry timer and paywall/navigation behavior |
| Account-switch regression before/after | On PR HEAD `181c1b9â€¦`, the two-file run ended with 58 passed / 4 failed: completed and in-flight A retries blocked B, a null retry was claimed by B, and the real paywall button stayed disabled. The identical run passed 62/62 after the correction. |
| Previous lifecycle/expiry targeted suite | 68 passed before this backend task (2026-09-11) |
| `flutter analyze --no-pub` | No issues after transfer (2026-09-12) |
| Full `flutter test --no-pub` | 155 passed after the account-scoped retry correction (2026-09-12) |
| Dart2js timer probe in headless Chrome 153 | Passed: monthly/yearly subscriptions retain access after event-loop turns, and a short actual expiry fires once. Compiles the production timer class directly. |
| `flutter test --platform chrome` (expiry tests) | Runner failed before test execution: local CanvasKit JS/Wasm loading errors and `Web test for servicessubscription_expiry_timer_test.dart not found`. Not counted as passed; the standalone Dart2js/Chrome probe above bypasses the Flutter rendering/test harness, not the production timer. |
| `node --test` | 56 passed after transfer in an isolated workspace copy containing only Functions package metadata, libraries and tests; no npm install or node_modules |
| `python -m src.check_bank` | All eight checks passed again on 2026-09-12; 1,082 questions and 300 flashcards. Content remains unchanged. |
| `git diff --check` | Passed after the account-scoped retry correction |

Environment: Flutter 3.41.6 / Dart 3.11.4, Node 22.17.1. The local content gate
used the installed Pydantic 2.11.7; CI pins 2.9.2. No dependency versions were
upgraded: the two existing Android/platform-interface Flutter packages became
direct dependencies at their already locked versions, with compatible caret
constraints. The already locked `fake_async` 1.3.3 became a direct dev dependency
for deterministic expiry tests. Lockfile changes only classify these three
dependencies as direct; versions and hashes are unchanged. Original node_modules
and all source/review assets were preserved.

Changed files (25):

- Ownership/auth: `lib/main.dart`, `lib/core/providers.dart`,
  `lib/services/iap_service.dart`, new `lib/services/purchase_account.dart`,
  `lib/services/subscription_expiry_timer.dart`.
- Entry points/UI: `lib/screens/profile_screen.dart`,
  `lib/screens/flashcard_session_screen.dart`, `lib/screens/paywall_screen.dart`.
- Dependency metadata: `pubspec.yaml`, `pubspec.lock`.
- Backend contract: `functions/index.js`, `functions/lib/receipts.js`, new
  `functions/lib/apple_validation.js`, `functions/lib/receipt_endpoint.js`.
- Tests: `test/services/iap_service_test.dart`,
  `test/screens/paywall_screen_test.dart`, new
  `test/services/android_completion_test.dart`,
  `test/services/subscription_expiry_timer_test.dart`,
  `test/screens/purchase_lifecycle_test.dart`, `test/support/purchase_fakes.dart`.
- Backend tests: `functions/test/receipts.test.js`, new
  `functions/test/apple_validation.test.js`,
  `functions/test/receipt_endpoint.test.js`.
- Documentation: `docs/MONETIZATION_PREP.md`, new `docs/RECOVERY_ROADMAP.md`.

Local ignored logs: `build/iap-targeted.log`, `build/flutter-analyze.log`,
`build/flutter-suite.log`, `build/functions-gate.log`, `build/content-gate.log`.
PR metadata was rechecked before handoff: #50 is merged as `8404ecc6…`; its
source head remained `081a4f9c…`, and both commits have the same Git tree.

Review correction evidence (2026-09-11): four purchase regressions failed before
the correction (purchased/restored rejection retained in retry, untyped retry
guard error, and Restore twice then Subscribe never reaching the store). Two
monthly/yearly tests failed with the original unbounded timer behavior extracted
into the timer helper and a browser int32 timeout model. The corrected suite
adds 17 tests in total, including actual event-loop checks, renewal, cancellation,
tab suspension and unknown-product handling. Current logs:
`build/review-regressions-before.log`, `build/review-timer-before.log`,
`build/review-targeted.log`, `build/review-analyze.log`,
`build/review-flutter-suite.log`, `build/review-chrome-timer.log`,
`build/review-chrome-probe.log`. Reproducible standalone browser probe:
`build/subscription_expiry_browser_probe.dart` and matching `.html`/compiled `.js`;
these are local ignored artifacts, not application files. The stuck Flutter web
test and its dedicated browser/compiler processes were stopped after recording
the runtime errors. The browser probe uses a separate temporary profile under
`build/`, with no signed-in browser session or store calls.

Apple contract verification logs are local ignored artifacts:
`build/apple-contract-functions.log`, `build/apple-contract-flutter-targeted.log`,
`build/apple-contract-analyze.log`, and `build/apple-contract-flutter-full.log`.
The Functions gate ran from `build/functions-pure-20260911-191732`, which has no
`node_modules` and contains only package metadata, `lib/` and `test/`.
The transferred result was checked again on 2026-09-12 from
`%TEMP%/ARE-Coach-functions-pure-followup-final` with the same 56/56 result.

Account-switch correction evidence (2026-09-12): the initial two-file service
and widget run against PR #51 HEAD `181c1b9â€¦` produced four expected failures.
After scoping the retry gate and redelivery path to the captured non-null uid,
that run passed 62/62 and the broader IAP target passed 73/73. The full Flutter
suite passed 155/155, Functions 56/56, content checks 8/8 and analysis was clean.
No backend contract, rejected-transaction finalization rule or Android release
flag changed in this correction.

Apple sandbox, Play license-tester/device checks, signed release artifacts and
production enablement remain pending. Apple error semantics are fixed and
locally tested; the StoreKit 2/JWS contract mismatch and transaction
identity/finalization gap above remain pre-launch blockers. Follow-up CI is
tracked on the draft PR for the exact pushed commit. Independent durable corpus
backup also remains pending; the patch-level `%TEMP%` snapshot above is a
recoverable same-disk transfer safeguard, not an independent backup.
