"use strict";

/**
 * Store-receipt decisions — pure, side-effect free, no network, no Firestore.
 *
 * This is the money path. Getting it wrong in either direction is expensive:
 * too strict and a paying customer is locked out, too loose and we hand out
 * Premium for free. Keeping the decision pure is what lets every branch below
 * be pinned by a unit test (see `test/receipts.test.js`).
 *
 * Every decision has an explicit outcome. `valid` remains for the HTTP client,
 * but server-side effects must branch on `outcome`, never on `!valid`.
 */

/** Subscription products we sell. Anything else is not our entitlement. */
const PRODUCT_IDS = ["are_coach_monthly", "are_coach_yearly"];
const RECEIPT_OUTCOME = Object.freeze({
  VERIFIED: "verified",
  NOT_ENTITLED: "not_entitled",
  UNAVAILABLE: "unavailable",
});

function verified(fields) {
  return { outcome: RECEIPT_OUTCOME.VERIFIED, valid: true, ...fields };
}

function notEntitled(reason, fields = {}) {
  return {
    outcome: RECEIPT_OUTCOME.NOT_ENTITLED,
    valid: false,
    reason,
    retryable: false,
    ...fields,
  };
}

function unavailable(reason, { retryable = true, httpStatus = 503 } = {}) {
  return {
    outcome: RECEIPT_OUTCOME.UNAVAILABLE,
    valid: false,
    reason,
    retryable,
    httpStatus,
  };
}

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
 * @returns {{outcome: string, valid: boolean, expiresAt?: number, productId?: string, reason?: string, retryable?: boolean, httpStatus?: number}}
 */
function decideAppleReceipt(appleData, now = Date.now()) {
  if (
    !appleData ||
    typeof appleData !== "object" ||
    Array.isArray(appleData)
  ) {
    return unavailable("malformed_apple_response", {
      retryable: true,
      httpStatus: 502,
    });
  }

  // Apple's schema declares an integer. Number(null/false/"") is zero, so
  // coercion here could turn a malformed gateway response into a valid receipt.
  if (!Number.isInteger(appleData.status)) {
    return unavailable("malformed_apple_status", {
      retryable: true,
      httpStatus: 502,
    });
  }

  const status = appleData.status;
  if (status === 21003) return notEntitled("invalid_receipt");
  if (status === 21010) return notEntitled("account_not_found");
  // Apple says 21006 is a valid legacy subscription receipt in an expired
  // state. It is therefore authoritative non-entitlement, not an outage.
  if (status === 21006) return notEntitled("expired");

  if (status === 21002 || status === 21005 || status === 21009) {
    return unavailable("apple_temporarily_unavailable", { retryable: true });
  }
  if (status >= 21100 && status <= 21199) {
    return unavailable("apple_internal_error", { retryable: true });
  }
  if (status === 21004) {
    return unavailable("apple_shared_secret_mismatch", { retryable: false });
  }
  if (status === 21000) {
    return unavailable("apple_request_protocol_error", {
      retryable: false,
      httpStatus: 502,
    });
  }
  if (status === 21007 || status === 21008) {
    return unavailable("apple_routing_error", {
      retryable: false,
      httpStatus: 502,
    });
  }
  if (status !== 0) {
    return unavailable("unknown_apple_status", {
      retryable: false,
      httpStatus: 502,
    });
  }

  if (!Array.isArray(appleData.latest_receipt_info)) {
    return unavailable("malformed_apple_response", {
      retryable: true,
      httpStatus: 502,
    });
  }

  const candidates = [];
  for (const transaction of appleData.latest_receipt_info) {
    if (
      !transaction ||
      typeof transaction !== "object" ||
      Array.isArray(transaction) ||
      typeof transaction.product_id !== "string"
    ) {
      return unavailable("malformed_apple_transaction", {
        retryable: true,
        httpStatus: 502,
      });
    }
    if (!PRODUCT_IDS.includes(transaction.product_id)) continue;

    const rawExpiry = transaction.expires_date_ms;
    const expiryIsDecimalString =
      typeof rawExpiry === "string" && /^[0-9]+$/.test(rawExpiry);
    const expiryIsInteger =
      typeof rawExpiry === "number" && Number.isSafeInteger(rawExpiry);
    if (!expiryIsDecimalString && !expiryIsInteger) {
      return unavailable("malformed_apple_transaction", {
        retryable: true,
        httpStatus: 502,
      });
    }
    const expiresAt = Number(rawExpiry);
    if (!Number.isSafeInteger(expiresAt) || expiresAt <= 0) {
      return unavailable("malformed_apple_transaction", {
        retryable: true,
        httpStatus: 502,
      });
    }

    candidates.push({ transaction, expiresAt });
  }

  const transactions = [];
  for (const candidate of candidates) {
    const { transaction, expiresAt } = candidate;
    if (
      Object.prototype.hasOwnProperty.call(
        transaction,
        "cancellation_date_ms"
      )
    ) {
      const rawCancellation = transaction.cancellation_date_ms;
      const cancellationIsDecimalString =
        typeof rawCancellation === "string" && /^[0-9]+$/.test(rawCancellation);
      const cancellationIsInteger =
        typeof rawCancellation === "number" &&
        Number.isSafeInteger(rawCancellation) &&
        rawCancellation > 0;
      if (!cancellationIsDecimalString && !cancellationIsInteger) {
        return unavailable("malformed_apple_transaction", {
          retryable: true,
          httpStatus: 502,
        });
      }
      // A refunded or revoked transaction carries a cancellation date. Its
      // expiry can still be in the future, so without this check we would keep
      // serving Premium to someone Apple already gave the money back to.
      continue;
    }
    if (expiresAt > now) transactions.push(candidate);
  }
  transactions.sort((a, b) => b.expiresAt - a.expiresAt);

  if (transactions.length === 0) {
    return notEntitled(
      candidates.length === 0 ? "no_subscription" : "expired"
    );
  }

  const latest = transactions[0];
  return verified({
    expiresAt: latest.expiresAt,
    productId: latest.transaction.product_id,
  });
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
 * @returns {{outcome: string, valid: boolean, expiresAt?: number, productId?: string, reason?: string, state?: string, testPurchase?: boolean}}
 */
function decidePlaySubscription(sub, now = Date.now()) {
  if (!sub || typeof sub !== "object") {
    return notEntitled("invalid_receipt");
  }

  const state = String(sub.subscriptionState || "").toUpperCase();
  if (!PLAY_ENTITLING_STATES.has(state)) {
    return notEntitled(
      state === "SUBSCRIPTION_STATE_EXPIRED" ? "expired" : "not_entitled",
      {
      state,
      }
    );
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
    return notEntitled("expired", { state });
  }

  return verified({
    state,
    expiresAt: items[0].expiresAt,
    productId: items[0].productId,
    // License testers get real-looking purchases that were never charged. They
    // must work (that is how we QA), but the log should say so.
    testPurchase: Boolean(sub.testPurchase),
  });
}

module.exports = {
  PRODUCT_IDS,
  RECEIPT_OUTCOME,
  PLAY_ENTITLING_STATES,
  notEntitled,
  unavailable,
  normalizePlatform,
  decideAppleReceipt,
  decidePlaySubscription,
};
