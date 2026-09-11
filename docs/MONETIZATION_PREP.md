# Monetization Setup

Premium is a subscription sold through the App Store and Google Play. The
server is the only source of truth: a purchase grants nothing until
`validateReceipt` has checked it with the store and written the result to
Firestore.

## Products

Reserved in both stores, identical IDs:

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
- **We only sell where the server can verify the sale.** `purchasesSupported`
  is false on any platform or build that cannot reach `validateReceipt`.

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
purchases validate without a code change.

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
4. **Verify with a license tester** before opening the storefront — Play Console
   → Setup → License testing. A tester's purchase is real end-to-end but never
   charged, and the server logs it with `testPurchase: true`.
5. **Then** set the repo variable `ANDROID_PURCHASES_ENABLED=true` and rebuild
   (see [CI_RELEASE_BUILD.md](CI_RELEASE_BUILD.md)).

> Steps 4 and 5 are in that order on purpose. Until the service account works,
> the server answers 503, the app refuses to acknowledge the purchase, and
> Google auto-refunds it after three days — the buyer gets their money back but
> has a broken day. Shipping the storefront before the backend is what made
> Android purchases a release blocker in the first place.

### What the server accepts

`decidePlaySubscription()` grants access for `ACTIVE`, `IN_GRACE_PERIOD` and
`CANCELED` (cancelled means "won't renew" — the current period is paid for),
and refuses `ON_HOLD`, `PAUSED`, `PENDING` and `EXPIRED`. The state alone is
never enough: a line item for one of our products must also have an
`expiryTime` in the future.

### When validation can't answer

"The store says no" and "we never got an answer" are different events and the
app treats them differently. A `200 {valid: false}` is the store's verdict and
the buyer is told the receipt could not be verified. A 502/503/timeout is our
outage: the client reports `validation_unavailable`, says so plainly, and does
**not** send anyone to support over our own downtime.

Neither case completes the purchase, which is what makes the outage
recoverable — both stores re-deliver an unfinished transaction on the next
launch, and Play refunds an unacknowledged one after three days.

## Refunds and expiry

Both stores are polled, not pushed — the user doc updates the next time the app
validates. A refund or expiry therefore takes effect on the next validation,
and `getEntitlement` independently refuses to serve Premium past `premiumUntil`
even if nothing has re-validated yet.

Server-to-server notifications (App Store Server Notifications v2, Play
Real-time Developer Notifications) would make revocation immediate. Not built
yet; the `premiumUntil` check is what makes their absence safe rather than
expensive.

## Web

There is no web storefront. `purchasesSupported` is false on web and the
paywall says so rather than offering a button that cannot charge anyone.
