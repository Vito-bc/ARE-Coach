"use strict";

/**
 * Store-receipt decisions — pure, side-effect free, no network, no Firestore.
 *
 * This is the money path. Getting it wrong in either direction is expensive:
 * too strict and a paying customer is locked out, too loose and we hand out
 * Premium for free. Keeping the decision pure is what lets every branch below
 * be pinned by a unit test (see `test/receipts.test.js`).
 *
 * The only shape callers see is the Decision:
 *   { valid: true,  expiresAt: <ms>, productId: <string> }
 *   { valid: false, reason: <string> }
 */

/** Subscription products we sell. Anything else is not our entitlement. */
const PRODUCT_IDS = ["are_coach_monthly", "are_coach_yearly"];

/**
 * Play subscription states that still entitle the user.
 *
 * CANCELED means "will not renew" — the user already paid for the current
 * period and keeps access until `expiryTime`, so it counts. ON_HOLD (payment
 * failed, retrying), PAUSED (user froze it), PENDING (never completed) and
 * EXPIRED do not: nobody is paying us in those states.
 */
const PLAY_ENTITLING_STATES = new Set([
  "SUBSCRIPTION_STATE_ACTIVE",
  "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
  "SUBSCRIPTION_STATE_CANCELED",
]);

/**
 * Normalizes the `platform` field the client sends into a store we validate.
 *
 * The Flutter `in_app_purchase` plugin reports `purchase.verificationData.source`
 * as "app_store" on iOS and "google_play" on Android; older clients sent plain
 * "ios". Anything unrecognized returns null and the request is rejected — we
 * never guess which store a receipt came from.
 *
 * @param {unknown} value
 * @returns {"app_store"|"google_play"|null}
 */
function normalizePlatform(value) {
  const v = String(value || "").trim().toLowerCase();
  if (v === "ios" || v === "app_store" || v === "macos") return "app_store";
  if (v === "android" || v === "google_play") return "google_play";
  return null;
}

/**
 * Decides entitlement from an Apple `/verifyReceipt` response body.
 *
 * @param {object} appleData  parsed response from verifyReceipt
 * @param {number} [now]      injectable clock (ms since epoch)
 * @returns {{valid: boolean, expiresAt?: number, productId?: string, reason?: string}}
 */
function decideAppleReceipt(appleData, now = Date.now()) {
  if (!appleData || typeof appleData !== "object") {
    return { valid: false, reason: "invalid_receipt" };
  }
  // Apple signals every failure through a non-zero status (21002 malformed,
  // 21003 unauthenticated, 21010 no such account, ...). Only 0 is a real receipt.
  if (Number(appleData.status) !== 0) {
    return { valid: false, reason: "invalid_receipt" };
  }

  const transactions = (appleData.latest_receipt_info || [])
    .filter((t) => {
      if (!t || !PRODUCT_IDS.includes(t.product_id)) return false;
      // A refunded or revoked transaction carries a cancellation date. Its
      // expiry can still be in the future, so without this check we would keep
      // serving Premium to someone Apple already gave the money back to.
      if (t.cancellation_date_ms) return false;
      const expires = Number(t.expires_date_ms);
      return Number.isFinite(expires) && expires > now;
    })
    .sort((a, b) => Number(b.expires_date_ms) - Number(a.expires_date_ms));

  if (transactions.length === 0) {
    return { valid: false, reason: "expired" };
  }

  const latest = transactions[0];
  return {
    valid: true,
    expiresAt: Number(latest.expires_date_ms),
    productId: latest.product_id,
  };
}

/**
 * Decides entitlement from a Google Play `purchases.subscriptionsv2` resource.
 *
 * v2 splits the answer in two: a top-level `subscriptionState` (is this person
 * paying?) and per-`lineItems` `expiryTime` (until when?). Both have to hold —
 * a state alone never grants access, and an expiry alone never does either.
 *
 * @param {object} sub    the subscriptionsv2 resource
 * @param {number} [now]  injectable clock (ms since epoch)
 * @returns {{valid: boolean, expiresAt?: number, productId?: string, reason?: string, state?: string, testPurchase?: boolean}}
 */
function decidePlaySubscription(sub, now = Date.now()) {
  if (!sub || typeof sub !== "object") {
    return { valid: false, reason: "invalid_receipt" };
  }

  const state = String(sub.subscriptionState || "").toUpperCase();
  if (!PLAY_ENTITLING_STATES.has(state)) {
    return {
      valid: false,
      state,
      reason: state === "SUBSCRIPTION_STATE_EXPIRED" ? "expired" : "not_entitled",
    };
  }

  // Google extends `expiryTime` into the future while a grace-period retry is
  // in flight, so requiring a future expiry here does not cut off a user whose
  // card is merely being retried — it only cuts off one nobody is paying for.
  const items = (Array.isArray(sub.lineItems) ? sub.lineItems : [])
    .map((li) => ({
      productId: li && li.productId,
      expiresAt: Date.parse((li && li.expiryTime) || ""),
    }))
    .filter(
      (li) =>
        PRODUCT_IDS.includes(li.productId) &&
        Number.isFinite(li.expiresAt) &&
        li.expiresAt > now
    )
    .sort((a, b) => b.expiresAt - a.expiresAt);

  if (items.length === 0) {
    return { valid: false, state, reason: "expired" };
  }

  return {
    valid: true,
    state,
    expiresAt: items[0].expiresAt,
    productId: items[0].productId,
    // License testers get real-looking purchases that were never charged. They
    // must work (that is how we QA), but the log should say so.
    testPurchase: Boolean(sub.testPurchase),
  };
}

module.exports = {
  PRODUCT_IDS,
  PLAY_ENTITLING_STATES,
  normalizePlatform,
  decideAppleReceipt,
  decidePlaySubscription,
};
