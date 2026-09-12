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
                     App Store verifyReceipt  <-------------------+
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

1. Create the subscription products in App Store Connect with the IDs above.
2. Generate an **App-Specific Shared Secret** (App Store Connect → App
   Information → App-Specific Shared Secret).
3. Set it on the functions:
   ```bash
   firebase functions:secrets:set APPLE_SHARED_SECRET
   ```

Sandbox receipts are handled automatically: Apple answers `21007` on the
production endpoint and the function retries against sandbox, so TestFlight
purchases validate without a code change. That route is bounded to production
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
than being guessed into a terminal receipt verdict.

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
