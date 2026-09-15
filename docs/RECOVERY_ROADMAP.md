# ARE Coach recovery roadmap

## Current iteration: RAG/content recovery

Updated 2026-09-15. PR #55 is squash-merged as
`890dd1a9860ede3696a07e5af7791bf36f839036`. The current bounded follow-up adds
fail-closed source-edition, applicability, and usage-eligibility policy without
running generation, embeddings, index rebuilding, extraction of the real corpus,
or any real content import. Inventory and the first architect packet remain
unchanged. **The payment phase is not fully complete.**

The owner currently has neither a Mac nor Apple Developer Program membership.
iOS device testing is deferred until closed-beta preparation. This is a schedule
decision, not device sign-off or removal of payment release blockers.

### Verified content inventory and immediate work

See [RAG_RECOVERY_INVENTORY.md](RAG_RECOVERY_INVENTORY.md) for search boundaries,
counts, editions, pipeline findings and preservation evidence. The full 18-item
architect packet is local-only under
`build/maryana-review-batch-01-20260914/`; question text and review materials
must not be published in Git.

- Found all 26 registered PDFs, plus two starter MD sources. Read-only extraction
  counted 3,441 chunks (3,440 unique texts); the saved Coach index has 1,503 rows
  (1,502 unique texts). Its entries match current source chunks; it omits BC Ch.08.
- The local NCARB file is **September 2022 ARE 5.0 Guidelines**, despite its
  `handbook` filename. It does not establish the bank's April 2026 citations.
  AIA, AHPP and CSI source files were not found in the bounded local/backup search.
  Source edition/provenance recovery remains necessary before further generation.
- Current bank: 1,082 unique IDs. Generated reports: 40 unique candidates,
  28 accepted by the automated gate, with no recorded human approval. Historical
  1,100-row audit/snapshot counts are not the size of the current bank.
- RED remains **127 unresolved unique IDs**, all present and content-matching
  in the bank. No verdict, notes or Excel comments were found in any review-book
  version or backup. These are review candidates, not 127 established errors.
  The two 692-row worklist versions have the same IDs/common values; `_new`
  lacks `priority`. Do not regenerate or overwrite any existing workbook.
- **Next concrete action:** architect reviews the proposed 18 IDs in the existing
  RED workbook, recording verdict and source edition/section in notes. Missing
  exact sources remain explicit blockers to those decisions. No automated
  verdict, question-bank edit or quarantine is part of this inventory.

### Completed protection for generated-candidate import

The generated-question CLI now enforces the following controls. This completion
applies to generated-candidate import only; it does not approve candidates or
change the bank.

1. `merge_accepted` requires a readable versioned review workbook in every mode.
   Only an explicit `Approve` on the exact candidate can pass. Blank, `Reject`,
   `Needs edit`, invalid verdicts, missing/legacy books and duplicate/conflicting
   IDs fail closed. Omitting the legacy `--reviewed` flag cannot bypass review.
2. The review workbook binds each row and the full input snapshot to reproducible
   SHA-256 fingerprints. Import rechecks the visible question, options, answer,
   explanation and source cells; editing candidate JSON or those Excel cells
   requires a new workbook and new human approval. Existing workbooks are never
   overwritten and legacy books receive no automatic approval or migration.
3. On a future real apply, the separate non-Flutter provenance journal records
   candidate ID → `gen_qN`, the reviewed fingerprint, complete candidate snapshot,
   human-review evidence, `grounded_on`, every available source field and an
   explicit missing-field list. Reapplying the same approved version is idempotent.
4. Bank and journal updates use staged before/after hashes and a pending marker.
   Partial target replacement is detected and can be rolled forward from retained
   transaction evidence; unknown target content blocks automatic recovery.

No real review workbook, RED/worklist file, architect packet, generated candidate,
provenance journal or question-bank row was changed while implementing this gate.
Audit-driven edits/removals still require an equivalent explicit human-approval
path before they may be applied.

### Source policy gate in the current bounded follow-up

The local source sidecar now has a strict
`are-coach.corpus-source-metadata.v2` shape. It records stable family/title,
issuing authority, explicit edition and revision, jurisdiction, applicable exam
divisions, applicability status/evidence, policy profiles, and a separate owner
status/note for the permitted uses `human_review`, `question_generation`, and
`coach_index`. The implementation does not decide source rights; it only enforces
the explicitly recorded owner status. Missing, unknown, pending, malformed, or
mismatched metadata is never upgraded to approval.

The pure selector returns `eligible`, `excluded`, or `invalid_metadata`, with
deterministic machine-readable reasons. Human review may see explicitly permitted
sources whose applicability is pending, but the restriction remains in the report.
Generation and Coach indexing require their own explicit use permission, approved
applicability, matching division/jurisdiction/profile, known identity, edition, and
revision. NYC-only material does not feed the six ARE divisions; model-code material
does not become NYC authority without an explicit dual declaration. A newer edition
is not an automatic substitute for an expected older one.

Grounded generation now selects the target division before the chunk and refuses
before API/embedding setup when a requested division has no eligible source. The
policy decision is carried through candidate JSON, versioned v3 review workbook,
and the import journal; distractor repair preserves it. The Coach indexer applies
the independent `coach_index` policy, defaults to dry-run, emits a deterministic
exclusion report, and refuses to replace an index for invalid metadata or an empty
eligible set. Existing page/hash/page-locator/chunk identities remain unchanged.
Legacy v1/v2 review shapes remain readable but gain no inferred eligibility.

No real manifest was populated or human-verified in this implementation. The real
Coach index remains unchanged; all tests use synthetic metadata and PDF/MD/TXT data.

### Open source-provenance and recovery work

1. **Page-aware ingestion (implemented in this draft):** new chunks preserve the
   corpus-relative path, exact source SHA-256, path-and-bytes document identity,
   1-based physical PDF page, deterministic locator/chunk ID and processing version.
   PDF chunks do not cross pages. Empty/unextractable pages retain their page number
   in diagnostics and do not trigger OCR. MD/TXT keep `source_page=null` as explicitly
   not applicable. Metadata flows through grounded candidate JSON, v2 review books,
   the import journal and Coach index/retrieval serialization. Existing candidates,
   v1 review books and saved index rows receive no guessed metadata.
2. **Real metadata decisions:** the schema and fail-closed enforcement are implemented,
   but the owner still must populate and human-verify the real manifest. Filenames
   remain non-evidence; no NYC/model-code dual applicability, edition equivalence, or
   supersession is inferred.
3. **Source rights:** establish and record permission for each source before any
   generation, distribution, or production indexing. Existing corpus rules and the
   policy engine are not a rights audit or legal determination.
4. **Provenance completeness:** later source additions still need complete reviewed
   metadata; the pipeline cannot supply values absent from the source declaration.
5. **Independent backup:** back up corpus, source manifest, review workbook,
   candidate-to-bank journal, provenance, index and bank snapshot outside this
   disk/sync boundary, then verify restoration. The destination has not been
   selected; this task remains open and no external backup is claimed.

Maryana's RED review and the first architect packet remain pending human work. The
payment release blockers below remain open and unchanged in status.

### Preservation and independent backup requirement

New work uses `codex/rag-content-recovery-20260913` in
`build/rag-recovery-worktree`, created clean from the verified main SHA.
The original `codex/iap-lifecycle-followup` checkout retains all 25 local changes.
Its prior snapshot and ZIP were hash-verified and preserved; an additional
25-file ZIP, manifest, status and binary diff were saved in a local temporary
preservation archive outside this worktree.

The same-disk corpus backup was checked against its manifest: all **4,464 files /
115,050,139 bytes** match both the backup and current sources. This remains a
temporary safeguard. **Independent,
durable corpus backup is required:** separate storage/account, access controls,
source/review/index/bank manifests and a verified restore. Destination is not yet
specified; no external copy is claimed. OneDrive sync alone is not this evidence.

The current review set contains Python CLI, tests and documentation only. PDFs,
private notes, workbook contents, extracted text, secrets and indexes stay
local/ignored. No generation, embedding, index rebuild, real bank mutation,
reset/clean, push, merge, deployment or store changes were performed. Payment
code and runtime payment tests were not touched for this content task.

### Remaining payment release blockers (separate workstream)

PR #52 implemented StoreKit 2/JWS verification and atomic Apple account ownership;
PR #53 added isolated Apple Sandbox purchase/restore and worker-bootstrap fixes.
Those implementation changes are merged. Historical statements below describing
missing JWS transport or an open draft are superseded, not reopened as new work.
Implementation and previous local/CI evidence do not establish release readiness.

1. **Apple external setup and signed beta artifacts:** Mac access, Apple Developer
   Program, app/bundle/numeric app IDs, products/subscription groups, signing and
   provisioning, Sandbox accounts, dedicated non-production Firebase project/app,
   Auth, App Check, Functions configuration/secrets and canonical endpoint.
   Independently verify environment agreement before the device run.
2. **Deferred iOS device/Sandbox sign-off:** purchase, restore, cancellation,
   pending/Ask-to-Buy, interrupted checkout/finishing, restart/cold start,
   expiry/renewal/refund and A/B account-switch/replay scenarios. Resume during
   closed-beta preparation; signed-device/TestFlight evidence is still absent.
3. **Lifecycle synchronization:** App Store Server Notifications v2 and Play RTDN
   or an explicitly justified alternative, retries and periodic reconciliation.
   Old signed proof alone does not reveal a later refund/revocation.
4. **Rejected/unsupported transaction finalization:** separate delivery/finalization
   policy and device evidence; rejected transactions remain `not_safe`, and unknown
   paid products need an explicit fulfillment/migration policy.
5. **Historical ownership recovery:** safe support/migration for legacy receipts,
   missing/mismatched appAccountToken and family sharing. First receipt claimant
   must not become owner automatically. Preserve cross-account/replay protection.
6. **Android release:** verify Play app/service-account/API and subscription/base-plan
   configuration, license-tester purchase/restore, interrupted acknowledgment and
   device recovery. Confirm receipt/token ownership and concurrent replay behavior
   for Play separately; Apple binding is not evidence for Play. New Android sales
   remain default-off until release approval and store evidence.
7. **Release review:** recheck dependency findings for the actual release tree
   (historical eight moderate findings are not a current security count), store
   disclosures/configuration, signed artifacts, exact release CI and explicit
   sales enablement approval. No external settings were inspected or changed here.
8. **Platform/product limits:** web checkout is unimplemented and full Flutter web
   integration sign-off remains absent (historical CanvasKit limitation).
   Sandbox Premium is private to its environment; Coach quota/server features
   reading production `users/{uid}` are not proof of sandbox payment integration.

Use [MONETIZATION_PREP.md](MONETIZATION_PREP.md) for the existing device runbook
and evidence fields. Payments, Android and web stay on the roadmap while current
work proceeds on content recovery.

## Archived evidence: StoreKit 2 and Apple account binding

The following records describe previous iterations. Their then-current branches,
draft status, authorizations and future steps are historical. The current scope,
main SHA, deferred device schedule and release blockers above take precedence.

Updated 2026-09-13. PR [#51](https://github.com/Vito-bc/ARE-Coach/pull/51)
is **merged**, squash/main `bab1534524c545ce8d9e13dadac378174cb6ec67`.
Current `origin/main` was fetched and matches that base. The new isolated branch
is `codex/storekit2-account-binding` in `build/storekit2-worktree`. The original
dirty `codex/iap-lifecycle-followup` checkout, the earlier worktree and the
25-file snapshot/archive remain preserved. This iteration authorizes a new
draft PR only, without merge, deployment, production changes or sales enablement.

### PR #52 review corrections: revoked expiry and first delivery

Continued the existing draft [PR #52](https://github.com/Vito-bc/ARE-Coach/pull/52)
from verified local/remote HEAD `350f7ff5dea141630f3458123e17d8427726cf00`.
Before production-code changes, the new Firestore-emulator regression failed:
yearly grant -> confirmed revocation -> shorter new monthly grant returned
`verified` while the user remained `free`. Two new service regressions (including
switching accounts during HTTP) and a real-paywall regression also failed:
first delivery to B, ownership refusal, then A's Restore never completed purchase.

The backend now compares expiry against a current grant only when its status is
active and its expiry is in the future. The historical expiry of revoked access
cannot block a new eligible subscription. Ownership, ledger and entitlement still
commit atomically; replay of the old revoked or expired transaction cannot remove
the new monthly access or resurrect revoked access. The emulator regression also
checks repeated monthly proof leaves the ledger unchanged.

The client stores `ownerUid` separately from `attemptUid`. First JWS delivery
reserves the attempt account's retry gate but does not prove ownership. A strict
503 `unavailable` / `apple_ownership_recovery_required` response releases that
reservation without finishing the purchase. Ordinary outages retain the attempt
reservation, preserving protection against duplicate purchase. Legacy/Play retain
their previous captured-account policy. Exact verified server proof sets the JWS
owner before entitlement refresh/completion; an unfinished proven purchase cannot
be retried or completed for another account.

A late ownership refusal can release only the unproven attempt's bookkeeping;
it cannot change the new account's UI or grant/finish a purchase. Restore waiting
for another account's in-flight request re-evaluates eligibility after the request
settles. Requests for the same transaction remain serialized. Real paywall and
service tests cover B -> refusal -> A -> explicit Restore, plus account switching
during HTTP and recovery of a proven owner's unfinished entitlement delivery.

Before/after evidence: the four defect regressions failed before the fixes and
pass afterward. The targeted Flutter suite passes 79 tests; the real verifier /
Firestore suite passes 11 (4 crypto, 7 emulator). Pure Functions tests pass 60 in
a fresh temporary copy without node_modules; content checks pass 8. Full Flutter
passes 172 tests and `flutter analyze --no-pub` reports no issues. One initial
full run exposed a pre-existing HTTP-timeout test's fixed 40ms sleep under load;
the test now awaits the error event with a bounded timeout. Its focused rerun
and the subsequent full suite both passed. `git diff --check` is clean.
CI is checked against
the exact pushed follow-up SHA, not the earlier green HEAD.

This correction does not implement notifications, sandbox client flow or rejected
finalization. `transactionFinalization:not_safe`, Android's default-off flag and
the CanvasKit/full-web limitation remain unchanged. Original dirty checkout and
backup are preserved; no real purchases, production writes, merge or deploy.

### Implemented contract

- Installed `in_app_purchase` 3.2.3 / StoreKit adapter 0.4.8+1 use StoreKit 2 by
  default. `sk2_transaction_wrapper.dart:154,159` supplies the transaction JWS
  and decimal transaction ID. `in_app_purchase_storekit_platform.dart:177`
  maps `PurchaseParam.applicationUserName` to `appAccountToken`; the Swift
  StoreKit2 purchase bridge parses the UUID and adds `.appAccountToken`.
  StoreKit was promoted to a direct dependency without a version change.
- Authenticated `prepare_apple_purchase` returns the server-created stable UUID
  for that UID and app/environment namespace. The client waits for it before
  opening the Apple checkout and rejects late account-switch responses.
- `receiptFormat:storekit2_jws` adds the requested `transactionId` and `productId`.
  The official Apple Node library 3.1.0 verifies the signature, Apple chain,
  bundle and environment; policy then checks subscription type, product, IDs,
  signed/purchase/expiry/revocation dates and the signed account token. Server
  configuration supplies identifiers, never the client or an unverified payload.
  OCSP checks run inside a worker with a 6-second termination deadline.
- `appleBilling/{namespace}` contains private account/token mappings, original
  transaction owners and processed transaction IDs. Namespace hashes bundle,
  environment and App Store app ID. Ownership and entitlement commit atomically.
  Repeat proof is idempotent; foreign/missing tokens and owner conflicts make no
  entitlement writes. Older expired transactions cannot remove a newer grant;
  a revocation already observed for a transaction cannot be undone by old proof.
- Production writes `users/{uid}`; Sandbox uses only the private
  `sandboxEntitlements` subcollection. This client accepts only production-scope
  access proof, so Sandbox cannot unlock or finalize production access. A separate
  sandbox application/backend verification flow remains a sign-off requirement.
- Successful Apple responses contain exact UID, transaction/product IDs,
  environment, scope, expiry and `transactionFinalization:verified_transaction`.
  The client matches those fields and refreshes server entitlement before
  finishing that transaction. Expired/revoked proof returns `not_entitled` with
  `transactionFinalization:not_safe`: it clears the repurchase retry gate but
  does not finish the rejected transaction.
- Cold-start JWS entries remain locally unbound while probing the backend.
  Login alone never binds them. A foreign login or unavailable verification
  leaves the entry recoverable; exact successful ownership proof binds it before
  entitlement refresh/completion. Existing UID/epoch guards and account-scoped
  retry protection remain in place.
- Legacy receipts use an explicit separate route, never a fallback after JWS
  failure. Because they lack this ownership proof, they return unavailable /
  `apple_ownership_recovery_required` without granting or downgrading. They need
  a separately reviewed recovery process; first receipt claimant is never owner.
- Play validation and Android's default-off sales flag are unchanged. The bounded
  premium-expiry timer and unknown StoreKit transaction behavior remain intact.

### Verification evidence and release limits

New tests exercise actual ES256 signing and the official verifier with ephemeral
test-only PKI, including payload/signature tampering, mismatched app/environment,
product/transaction IDs and production rejection of test trust. The test CA is
never loaded by production code; `functions/integration` is excluded from deploy.
Firestore demo-emulator tests use real signed requests and real transactions for
concurrent A/B replay, stable tokens, idempotency, failed-commit rollback, older
expiry, revocation, outage recovery, Sandbox isolation and rules denial for owner,
foreign, anonymous and admin clients. Pure tests still run without node_modules;
CI installs locked dependencies explicitly for the separate integration job.

Local evidence for this patch:

| Gate | Result |
| --- | --- |
| New StoreKit service contract tests | 12 passed; cold-start real-paywall regression also passed |
| Full `flutter test --no-pub` | 168 passed |
| `flutter analyze --no-pub` | No issues found |
| Pure Functions tests | 60 passed in a fresh temporary copy containing only `lib` and `test`, no node_modules |
| Real verifier signed-fixture tests | 4 passed |
| Firestore emulator ownership/rules tests | 6 passed against local `demo-are-coach`, including real failed-commit rollback |
| Content checks | 8 passed |
| Dependency review | Existing npm package versions unchanged; added official Apple and explicit test dependencies. Flutter lock changes only StoreKit `transitive` to `direct main`. |
| Diff check | Clean before commit |

CI includes a separate dependency-installed verifier/emulator job; the PR receipt
reports results against the exact pushed SHA. Windows `flutter pub get --offline`
resolved the unchanged plugin versions but warned that native plugin symlinks
require Developer Mode. Tests and analyze succeeded; this is not a Windows native
build sign-off. The first rules test incorrectly expected an identical no-op
write to fail; it now attempts a real protected-field change. The cold-start widget
test explicitly initializes the shared listener before emitting the purchase.
No real store purchases, production writes or device verification were performed.
The earlier standalone dart2js timer check remains valid evidence only for that
timer; the Flutter web runner was blocked loading CanvasKit. Full web integration
is **not** claimed.

Remaining payment release blockers:

1. Configure and independently verify actual App Store numeric app ID, bundle,
   environment, App Check and isolated sandbox/device flow; no settings were
   changed here. See [MONETIZATION_PREP.md](MONETIZATION_PREP.md).
2. Renewal/refund notifications and reconciliation. An old correctly signed JWS
   does not prove that no later refund occurred; certificate OCSP checks do not
   answer subscription refund status. Known revocation is monotonic locally,
   but obtaining later lifecycle events is a separate implementation task.
3. Rejected-transaction finalization and safe support/migration for missing or
   mismatched appAccountToken. Historical legacy receipts cannot automatically
   become bound purchases. Family sharing is not automatically assigned either.
4. Device/sandbox restore, interrupted checkout, pending/Ask-to-Buy, restart,
   renewal/refund and account-switch sign-off; release review and sales approval.
   Local unit/emulator success does not make payments release-ready.

## Archived evidence: PR #51 lifecycle and legacy-validation follow-up

The rest of this document records the earlier iteration. Its references to an
open draft, the next StoreKit task and missing JWS/account binding are historical;
the current contract and remaining blockers above supersede those statements.

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

## Isolated Apple Sandbox flow (draft follow-up)

The follow-up from merged PR #52 adds a build-wide purchase contract and a
separate sandbox entitlement read. Production remains the default. A sandbox
checkout is enabled only when Apple `Sandbox`, Firebase `Sandbox`, entitlement
source `apple_sandbox`, a non-production Firebase project, that project's
canonical `validateReceipt` URL and complete Firebase iOS options agree.
Prepare and validation carry this contract; the backend compares it with its
deployment configuration before token provisioning or JWS verification.

Sandbox entitlements stay under the private environment namespace. The
authenticated `get_apple_entitlement` action returns only the caller's UID and
can attest that an exact transaction/product was processed. Auth and App Check
remain endpoint prerequisites, while Firestore rules continue to deny all
client access to tokens, owners, ledger and sandbox-entitlement documents.
Production `users/{uid}` is not mutated by sandbox validation.

The sandbox client uses that endpoint for restart/account refresh, paywall and
Premium UI state, with local expiry scheduling. Completion requires matching
UID, transaction, product, Firebase project, Apple environment and scope, plus
a current future entitlement read. Outages do not fabricate access or finish a
transaction; a previously confirmed in-memory entitlement is retained only
until its known expiry. Account epoch/retry guards prevent a late response from
granting or completing for another login. Rejected finalization remains
`not_safe`, and Android sales remain disabled.

Worker-bootstrap correction evidence on 2026-09-13: the new integration
regression failed on the reviewed PR head because the worker discarded the
Firebase project ID and stopped at configuration before constructing
`SignedDataVerifier`. The parent and worker now strictly validate the same
serialized Production/Sandbox configuration. Tests assert that both trusted
environments reach JWS signature verification, while a missing project ID and
`LocalTesting` stop at configuration. The worker still uses only the bundled
Apple roots, enables online certificate checks and remains bounded by the
six-second parent timeout; test roots are not passed to production code.

Local evidence on 2026-09-13: 39/39 targeted Flutter IAP/provider/real-paywall
tests; 183/183 complete Flutter tests; clean `flutter analyze --no-pub`; 62/62
pure Functions tests without loading production services; 6/6 real ES256 and
worker-bootstrap verifier tests; 8/8 Firestore demo-emulator ownership/rules tests; and
8/8 content checks. `git diff --check` is clean. The emulator suite specifically
covers authenticated-UID isolation, exact processed proof, sandbox storage
separation, production rejection of sandbox JWS, atomicity, idempotency and
private billing rules. CI evidence is tied to the exact draft-PR SHA after push.
The earlier CanvasKit limitation remains: a full Flutter web integration run is
not claimed, and unrelated web-runner troubleshooting was not repeated.

External configuration is **not performed** and device testing is **not
performed**. The dedicated Firebase project/app, Auth users, App Check
registration/enforcement, Functions environment/secrets, App Store products,
Sandbox Apple Accounts, signing/provisioning and physical-device/TestFlight run
remain required. See `MONETIZATION_PREP.md` for exact commands, scenarios and
evidence fields. Sandbox Premium currently controls client Premium surfaces;
server features such as Coach quota still read `users/{uid}` and therefore do
not treat the private sandbox entitlement as production payment. Notifications
and reconciliation are still absent, so renewal/refund automation is not
claimed.

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
