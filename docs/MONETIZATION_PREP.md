# Monetization Setup

Premium is a subscription sold through the App Store and Google Play. The
server is the only source of truth: a purchase grants nothing until
`validateReceipt` has checked it with the store and written the result to
Firestore.

## Products

Expected in both stores, with identical IDs (current console configuration has
not been verified in this follow-up):

- `are_coach_monthly`
- `are_coach_yearly`

The IDs are hardcoded in `functions/lib/receipts.js` (`PRODUCT_IDS`) and
`lib/services/iap_service.dart`. A purchase of anything else is ignored.

## How entitlement works

```
app  --(receipt / purchase token + ID token + App Check)-->  validateReceipt
                                                                  |
                     Apple signed JWS verifier <------------------+
                     Play subscriptionsv2     <-------------------+
                                                                  |
                              users/{uid} { role, subscriptionStatus,
                                            premiumUntil, subscriptionPlatform }
```

Two rules that are easy to get wrong and cost real money:

- **`role: "premium"` is a label, not proof of payment.** Entitlement is
  decided by `decideEntitlement()` from the *live subscription* —
  `subscriptionStatus: "active"` **and** a future `premiumUntil`. A stale role
  once survived cancellation, expiry and refund.
- **New sales require validation configuration.** `purchasesSupported` requires
  an enabled, supported storefront and a valid HTTPS validation URL. This build
  guard does not prove the backend is reachable or correctly configured; the
  transaction handler still validates every purchase, and store testing remains
  required.

## iOS (App Store)

PR #51 is merged at `bab1534524c545ce8d9e13dadac378174cb6ec67`. The subsequent
StoreKit 2 patch implements signed transaction verification and atomic ownership.
It is not deployment or payment-release approval.

### Server and adapter contract

Installed StoreKit 0.4.8+1 uses JWS in `serverVerificationData` and a decimal
transaction ID in `purchaseID`. The client first posts
`{platform:app_store, action:prepare_apple_purchase}` with Firebase ID token and
App Check. The backend creates a stable UUID for the authenticated UID; the
adapter forwards it through `PurchaseParam.applicationUserName` to native
`Product.PurchaseOption.appAccountToken`. It is not a user-selectable owner ID.

Validation posts `receiptFormat:storekit2_jws`, `receiptData`, `transactionId`
and `productId`. The official `@apple/app-store-server-library` 3.1.0 validates
ES256/trusted Apple certificates and expected bundle/environment. Server policy
checks product, auto-renewable type, transaction/original IDs, dates, revocation
and signed token. The worker always enables online certificate checks and is
terminated after 6 seconds, including outstanding requests. It accepts neither
test roots nor Xcode/LocalTesting signature-bypass modes.

Required backend environment configuration (not set by this task):

| Setting | Meaning |
| --- | --- |
| `APPLE_BUNDLE_ID` | Exact App Store bundle identifier; checked source currently uses `com.archedu.architectulaEducationApp`, confirm against App Store Connect before configuration. |
| `APPLE_APP_ID` | Actual positive decimal numeric App Store app ID, not Firebase app ID; no invented default. Required by the production library constructor. |
| `APPLE_ENVIRONMENT` | Exactly `Production` or `Sandbox`; no default or client override. |

Transaction JWS payloads identify the app by bundle ID; they do not contain an
`appAppleId` field for this verifier to compare. The configured App Store app ID
is supplied to the official verifier and included in the storage namespace;
App Store Connect must confirm the bundle/numeric-ID pair. Notifications/app
transactions have additional app-ID checks in Apple's library and are separate.
Public Apple trust anchors are bundled under `functions/certificates` with
source URLs and SHA-256 fingerprints. No App Store private API key is required
just to verify transaction signatures. API notifications/reconciliation will
require their own setup.

Within `appleBilling/{hash(bundle,environment,appId)}`, only the backend can read
or write accounts, token mappings, owners, transaction ledger and sandbox records.
Firestore rules deny these paths even to client admin claims. Owner assignment,
ledger and entitlement updates form one transaction; retries are idempotent.
Missing/foreign tokens, conflicts, invalid signatures, malformed proof,
configuration failures and outages return non-200 `unavailable`, without grant,
extension or downgrade. Recovery must authenticate and establish ownership through
a separately reviewed process; receipt possession or first claim is insufficient.

Production grants update `users/{uid}`. Sandbox grants are recorded only under
the separate private `sandboxEntitlements` namespace and never unlock production
Premium. The current app requires production-scope proof before completion;
a configured Sandbox backend alone does **not** produce end-to-end sandbox
paywall success. An isolated test-app entitlement/finalization flow and device
sign-off remain pending. Never point a production client at testing trust roots.

Success must match current UID and the exact transaction/product, include future
expiry and `transactionFinalization:verified_transaction`, and pass a fresh
Firestore entitlement read before `completePurchase`. Cold-start events may probe
ownership after login but remain unbound until server proof; late callbacks cannot
complete for another account. Definitive expired/revoked results release the retry
gate and keep `transactionFinalization:not_safe`; finishing rejections is separate.

### Legacy receipts and release prerequisites

Legacy `receiptFormat:legacy_receipt` remains a distinct bounded validation route.
It never accepts a JWS or handles fallback after signature failure. Because legacy
receipts do not prove the signed account-token relationship, this route returns
`apple_ownership_recovery_required` without changing entitlement. Existing expiry
enforcement continues. Historical/untagged purchases require safe support recovery;
they cannot be silently assigned to the caller.

The following shared-secret setup is for that legacy route only:

1. Create the subscription products in App Store Connect with the IDs above.
2. Generate an **App-Specific Shared Secret** (App Store Connect → App
   Information → App-Specific Shared Secret).
3. Set it on the functions:
   ```bash
   firebase functions:secrets:set APPLE_SHARED_SECRET
   ```

The legacy validator routes numeric `21007` from the
production endpoint to sandbox. This does not grant a bound entitlement or
establish StoreKit 2/TestFlight sign-off. That route is bounded to production
plus one sandbox call. Apple calls have a 6-second timeout each, so both fit
inside the client's 15-second request bound.

The backend uses three explicit outcomes. Status `0` is parsed for a current,
eligible subscription. Legacy `21006`, status `0` with no current subscription,
and terminal `21003`/`21010` are authoritative non-entitlement. `21002`,
`21005`, `21009`, `21100–21199`, shared-secret failure `21004`, routing/protocol
errors, unknown statuses, malformed response shapes, transport errors and
timeouts are validation unavailability. Those unavailable cases return non-200
and never grant Premium or call the downgrade path. Apple defines `21002` as
malformed data *or* a temporary service issue, so it remains retryable rather
than being guessed into a terminal receipt verdict. These are legacy helper
classifications; the endpoint now adds the ownership-recovery restriction above.

Renewal/refund notifications, secure historical-purchase recovery, rejected
finalization and device sign-off remain release blockers. A valid signature on an
old JWS does not establish that no later refund occurred. Local verifier/emulator
tests and green CI do not authorize public sales. No deploy, store settings,
production secrets or Android sales flag were changed in this patch.

## Android (Google Play)

Play has no shared secret. Validation is a Google Play Developer API call
authenticated with a **service account**, and it must be granted access from
*both* Google Cloud and the Play Console.

1. **Create the service account** — Google Cloud Console (project
   `architect-study-app`) → IAM & Admin → Service Accounts → Create. No project
   roles are needed; the permission that matters is granted in Play. Create a
   **JSON key** and download it.
2. **Link and grant in Play Console** — Play Console → Setup → API access, link
   the Google Cloud project, find the service account, and grant it the
   **View financial data, orders, and cancellation survey responses**
   permission for this app. (Play permission changes can take a few hours to
   take effect — if validation 401s right after setup, wait it out.)
3. **Store the key as a secret** (the whole JSON file, not a path):
   ```bash
   firebase functions:secrets:set GOOGLE_PLAY_SERVICE_ACCOUNT < service-account.json
   firebase deploy --only functions
   ```
   Delete the local JSON afterwards. It is a credential to your billing data.

   The function declares this secret, so it must exist before *any* deploy. To
   deploy the other functions before the Play account is ready, set it to the
   placeholder `{}` — Android validation then answers 503 "not configured"
   instead of granting anything, which is exactly what the storefront switch
   below is protecting against.
4. **Create a controlled license-tester build.** After configuring the backend,
   use a signed internal-test build with `ANDROID_PURCHASES_ENABLED=true` **only
   for that build**, and a valid `VALIDATE_RECEIPT_URL`. Keep the public/repository
   release flag `false`. Install through the intended Play test track using an
   enrolled license tester and verify that the store identifies a test payment.
5. **Verify end to end:** purchase, cancellation, pending payment, interrupted
   validation, explicit restore (including empty results), authoritative
   entitlement and successful acknowledgment. Include restart, duplicate delivery,
   account switch, expiry and refund scenarios. Record evidence; `testPurchase:
   true` in logs alone is not an end-to-end pass.
6. **Later authorize public enablement.** Only after the required backend and
   sandbox checks pass, separately authorize changing the public
   `ANDROID_PURCHASES_ENABLED` variable and producing a public release build
   (see [CI_RELEASE_BUILD.md](CI_RELEASE_BUILD.md)).

> Order: backend configuration → controlled enabled tester build → complete
> purchase/restore/entitlement/acknowledgment verification → later public release
> authorization. No credentials, production variables or store accounts were
> changed, and no deploy was performed in the lifecycle follow-up.

### What the server accepts

`decidePlaySubscription()` grants access for `ACTIVE`, `IN_GRACE_PERIOD` and
`CANCELED` (cancelled means "won't renew" — the current period is paid for),
and refuses `ON_HOLD`, `PAUSED`, `PENDING` and `EXPIRED`. The state alone is
never enough: a line item for one of our products must also have an
`expiryTime` in the future.

### When validation can't answer

"The store says no" and "we never got an answer" are different events and the
app treats them differently. A definitive response is HTTP 200 with boolean
`valid:false`, `outcome:"not_entitled"`, and
`transactionFinalization:"not_safe"`; the buyer is told that the receipt did
not establish access and can start a new subscription. A bare legacy
`200 {valid:false}` is treated as protocol failure. A 502/503/504/timeout is
unavailable: the client reports `validation_unavailable`, says so plainly, and
does not send anyone to support over our own downtime. Only definitive
non-entitlement invokes `markUserFree`; unavailable validation preserves the
stored entitlement and normal expiry enforcement continues.

Neither case completes a purchased/restored transaction as verified. The
application-owned service keeps the store listener alive across navigation and
retains failed transactions for in-session retry. **Restore Purchases** retries
those entries and queries the store, including when Android new sales are off.
Missing/invalid validation URLs fail closed in debug, profile and release;
offline tests use explicit fakes.

HTTP 200 with absent/non-boolean `valid`, an unexpected JSON shape, malformed
body, non-200 status, connection failure or timeout is unavailable, not a receipt
verdict. Credential retrieval, HTTP validation, the fresh server entitlement
read and completion each have a 15-second limit; store operations have a
45-second limit. Long pending payments have a visible state without an indefinite
spinner. No success appears until server validation, entitlement refresh and any
required completion succeed for the same account.

The Apple verdict is still account-receipt level: the request does not bind the
incoming `PurchaseDetails.purchaseID` to a transaction proven by the response.
Accordingly, the server labels transaction finalization `not_safe`, and the
client does not call `completePurchase` after rejection. It removes the rejected
item from its in-session retry gate so an expired restore does not block a new
purchase; StoreKit may redeliver the unfinished item. Safe rejected-transaction
finalization depends on the separate StoreKit transport/transaction-identity
patch and sandbox/device evidence.

The installed Android adapter (0.4.0+10) returns a `BillingResultWrapper` for
acknowledgment, although the generic API exposes `Future<void>`. The follow-up
checks `BillingResponse.ok` explicitly. Exceptions and non-OK results remain
retryable failures; a timeout reuses the outstanding completion future to avoid
concurrent acknowledgment. StoreKit cancelled/failed queue cleanup is separate
from verified delivery.

The Android plugin queries purchases on explicit restore; merely reopening is
not a guaranteed retry. Store redelivery and interruption/restart recovery need
device verification. An automatic refund is not a replacement for recovery or
evidence that a customer received the service.

See [RECOVERY_ROADMAP.md](RECOVERY_ROADMAP.md) for the locally completed Apple
status contract and the separate StoreKit 2/JWS transport, transaction/account
ownership, renewal/refund synchronization and dependency review tasks. The
client recognizes the new explicit non-entitlement shape, but the current
account-level receipt response still cannot authorize finalization of a specific
StoreKit transaction.

## Refunds and expiry

Both stores are polled, not pushed — the user doc updates the next time the app
validates. A refund or expiry therefore takes effect on the next validation,
and `getEntitlement` independently refuses to serve Premium past `premiumUntil`
even if nothing has re-validated yet.

Server-to-server notifications (App Store Server Notifications v2, Play
Real-time Developer Notifications), retry handling and reconciliation are not
built yet. Expiry checking blocks access after expiry; a refund **before** expiry
can remain undetected until revalidation. This remains a separate pre-launch
task, and the client lifecycle tests do not close it.

## Web

There is no web storefront. `purchasesSupported` is false on web and the
paywall says so rather than offering a button that cannot charge anyone.
