"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");

const {
  RECEIPT_OUTCOME,
  normalizePlatform,
  decideAppleReceipt,
  decidePlaySubscription,
} = require("../lib/receipts");

const NOW = Date.parse("2026-08-15T12:00:00Z");
const FUTURE = Date.parse("2026-09-15T12:00:00Z");
const PAST = Date.parse("2026-07-15T12:00:00Z");

// ---------------------------------------------------------------------------
// Platform routing
// ---------------------------------------------------------------------------

test("normalizePlatform maps every string a client actually sends", () => {
  // in_app_purchase reports verificationData.source as these two.
  assert.equal(normalizePlatform("app_store"), "app_store");
  assert.equal(normalizePlatform("google_play"), "google_play");
  // Older/hand-rolled clients.
  assert.equal(normalizePlatform("ios"), "app_store");
  assert.equal(normalizePlatform("android"), "google_play");
  assert.equal(normalizePlatform("macos"), "app_store");
  assert.equal(normalizePlatform("  Android  "), "google_play");
});

test("normalizePlatform refuses to guess an unknown store", () => {
  // Guessing would mean sending a Play token to Apple (or the reverse) and
  // reading the resulting error as "your purchase is invalid".
  for (const v of ["", "   ", "stripe", "amazon", "web", null, undefined, 7, {}]) {
    assert.equal(normalizePlatform(v), null);
  }
});

// ---------------------------------------------------------------------------
// Apple
// ---------------------------------------------------------------------------

const appleReceipt = (info, status = 0) => ({
  status,
  latest_receipt_info: info,
});

const appleTx = (over = {}) => ({
  product_id: "are_coach_monthly",
  expires_date_ms: String(FUTURE),
  ...over,
});

test("apple: active subscription with a future expiry is valid", () => {
  const d = decideAppleReceipt(appleReceipt([appleTx()]), NOW);
  assert.equal(d.outcome, RECEIPT_OUTCOME.VERIFIED);
  assert.equal(d.valid, true);
  assert.equal(d.expiresAt, FUTURE);
  assert.equal(d.productId, "are_coach_monthly");
});

test("apple: terminal receipt failures are authoritative non-entitlement", () => {
  for (const status of [21003, 21010]) {
    const d = decideAppleReceipt(appleReceipt([appleTx()], status), NOW);
    assert.equal(d.outcome, RECEIPT_OUTCOME.NOT_ENTITLED);
    assert.equal(d.valid, false);
    assert.equal(d.retryable, false);
  }
});

test("apple: temporary and internal statuses are unavailable", () => {
  for (const status of [21002, 21005, 21009, 21100, 21137, 21199]) {
    const d = decideAppleReceipt(appleReceipt([appleTx()], status), NOW);
    assert.equal(d.outcome, RECEIPT_OUTCOME.UNAVAILABLE);
    assert.equal(d.valid, false);
    assert.equal(d.retryable, true);
  }
});

test("apple: server configuration and routing statuses are unavailable", () => {
  for (const status of [21000, 21004, 21007, 21008]) {
    const d = decideAppleReceipt(appleReceipt([appleTx()], status), NOW);
    assert.equal(d.outcome, RECEIPT_OUTCOME.UNAVAILABLE);
    assert.equal(d.valid, false);
    assert.equal(d.retryable, false);
  }
});

test("apple: unknown status is unavailable, never a downgrade", () => {
  const d = decideAppleReceipt(appleReceipt([appleTx()], 29999), NOW);
  assert.equal(d.outcome, RECEIPT_OUTCOME.UNAVAILABLE);
  assert.equal(d.reason, "unknown_apple_status");
});

test("apple: status accepts only an integer number", () => {
  for (const status of [null, undefined, false, true, "", "0", "21005", 0.5]) {
    const d = decideAppleReceipt(
      { status, latest_receipt_info: [appleTx()] },
      NOW,
    );
    assert.equal(d.outcome, RECEIPT_OUTCOME.UNAVAILABLE, String(status));
    assert.equal(d.reason, "malformed_apple_status");
  }
});

test("apple: expired subscription is not valid", () => {
  const d = decideAppleReceipt(
    appleReceipt([appleTx({ expires_date_ms: String(PAST) })]),
    NOW,
  );
  assert.equal(d.outcome, RECEIPT_OUTCOME.NOT_ENTITLED);
  assert.equal(d.valid, false);
  assert.equal(d.reason, "expired");
});

test("apple: a REFUNDED transaction does not grant premium", () => {
  // The money went back to the customer but the expiry is still in the future.
  // Without the cancellation check we would keep serving them Premium for free.
  const d = decideAppleReceipt(
    appleReceipt([appleTx({ cancellation_date_ms: String(PAST) })]),
    NOW,
  );
  assert.equal(d.outcome, RECEIPT_OUTCOME.NOT_ENTITLED);
  assert.equal(d.valid, false);
  assert.equal(d.reason, "expired");
});

test("apple: a receipt for a product we don't sell is ignored", () => {
  const d = decideAppleReceipt(
    appleReceipt([appleTx({ product_id: "some_other_app_yearly" })]),
    NOW,
  );
  assert.equal(d.valid, false);
});

test("apple: picks the LATEST expiry when several transactions are live", () => {
  const later = Date.parse("2026-11-15T12:00:00Z");
  const d = decideAppleReceipt(
    appleReceipt([
      appleTx({ expires_date_ms: String(FUTURE) }),
      appleTx({ product_id: "are_coach_yearly", expires_date_ms: String(later) }),
      appleTx({ expires_date_ms: String(PAST) }),
    ]),
    NOW,
  );
  assert.equal(d.valid, true);
  assert.equal(d.expiresAt, later);
  assert.equal(d.productId, "are_coach_yearly");
});

test("apple: empty, missing and malformed bodies are not valid", () => {
  for (const body of [
    null,
    undefined,
    "nope",
    [],
    {},
    appleReceipt(undefined),
    appleReceipt("broken"),
    appleReceipt([appleTx({ expires_date_ms: "" })]),
    appleReceipt([appleTx({ expires_date_ms: false })]),
    appleReceipt([appleTx({ cancellation_date_ms: false })]),
    appleReceipt([appleTx({ cancellation_date_ms: "" })]),
  ]) {
    const d = decideAppleReceipt(body, NOW);
    assert.equal(d.outcome, RECEIPT_OUTCOME.UNAVAILABLE);
    assert.equal(d.valid, false);
  }
});

test("apple: valid empty receipt is authoritative non-entitlement", () => {
  const d = decideAppleReceipt(appleReceipt([]), NOW);
  assert.equal(d.outcome, RECEIPT_OUTCOME.NOT_ENTITLED);
  assert.equal(d.reason, "no_subscription");
});

// ---------------------------------------------------------------------------
// Google Play
// ---------------------------------------------------------------------------

const playSub = (state, over = {}) => ({
  subscriptionState: state,
  lineItems: [
    {
      productId: "are_coach_monthly",
      expiryTime: new Date(FUTURE).toISOString(),
    },
  ],
  ...over,
});

test("play: ACTIVE subscription with a future expiry is valid", () => {
  const d = decidePlaySubscription(playSub("SUBSCRIPTION_STATE_ACTIVE"), NOW);
  assert.equal(d.valid, true);
  assert.equal(d.expiresAt, FUTURE);
  assert.equal(d.productId, "are_coach_monthly");
});

test("play: CANCELED but not yet expired still gets what they paid for", () => {
  // "Canceled" on Play means "will not renew". They paid for this period.
  const d = decidePlaySubscription(playSub("SUBSCRIPTION_STATE_CANCELED"), NOW);
  assert.equal(d.valid, true);
  assert.equal(d.expiresAt, FUTURE);
});

test("play: IN_GRACE_PERIOD keeps access while Google retries the card", () => {
  const d = decidePlaySubscription(playSub("SUBSCRIPTION_STATE_IN_GRACE_PERIOD"), NOW);
  assert.equal(d.valid, true);
});

test("play: states where nobody is paying us grant nothing", () => {
  // ON_HOLD  = payment failed and grace is over.
  // PAUSED   = user froze the subscription.
  // PENDING  = purchase never completed.
  // EXPIRED  = over.
  const states = [
    "SUBSCRIPTION_STATE_ON_HOLD",
    "SUBSCRIPTION_STATE_PAUSED",
    "SUBSCRIPTION_STATE_PENDING",
    "SUBSCRIPTION_STATE_EXPIRED",
    "SUBSCRIPTION_STATE_UNSPECIFIED",
  ];
  for (const state of states) {
    const d = decidePlaySubscription(playSub(state), NOW);
    assert.equal(d.valid, false, `${state} must not be entitled`);
  }
});

test("play: EXPIRED is reported as expired, other refusals as not_entitled", () => {
  assert.equal(
    decidePlaySubscription(playSub("SUBSCRIPTION_STATE_EXPIRED"), NOW).reason,
    "expired",
  );
  assert.equal(
    decidePlaySubscription(playSub("SUBSCRIPTION_STATE_ON_HOLD"), NOW).reason,
    "not_entitled",
  );
});

test("play: ACTIVE state with a PAST expiry is still refused", () => {
  // State and expiry must BOTH hold. A stale state field alone is not payment.
  const d = decidePlaySubscription(
    playSub("SUBSCRIPTION_STATE_ACTIVE", {
      lineItems: [
        {
          productId: "are_coach_monthly",
          expiryTime: new Date(PAST).toISOString(),
        },
      ],
    }),
    NOW,
  );
  assert.equal(d.valid, false);
  assert.equal(d.reason, "expired");
});

test("play: a line item for another app's product grants nothing", () => {
  const d = decidePlaySubscription(
    playSub("SUBSCRIPTION_STATE_ACTIVE", {
      lineItems: [
        { productId: "unrelated_monthly", expiryTime: new Date(FUTURE).toISOString() },
      ],
    }),
    NOW,
  );
  assert.equal(d.valid, false);
});

test("play: picks the latest live line item across products", () => {
  const later = Date.parse("2027-01-15T12:00:00Z");
  const d = decidePlaySubscription(
    playSub("SUBSCRIPTION_STATE_ACTIVE", {
      lineItems: [
        { productId: "are_coach_monthly", expiryTime: new Date(FUTURE).toISOString() },
        { productId: "are_coach_yearly", expiryTime: new Date(later).toISOString() },
      ],
    }),
    NOW,
  );
  assert.equal(d.productId, "are_coach_yearly");
  assert.equal(d.expiresAt, later);
});

test("play: a license-tester purchase is honoured but flagged", () => {
  const d = decidePlaySubscription(
    playSub("SUBSCRIPTION_STATE_ACTIVE", { testPurchase: {} }),
    NOW,
  );
  assert.equal(d.valid, true);
  assert.equal(d.testPurchase, true);
  assert.equal(
    decidePlaySubscription(playSub("SUBSCRIPTION_STATE_ACTIVE"), NOW).testPurchase,
    false,
  );
});

test("play: missing, empty and malformed responses grant nothing", () => {
  const cases = [
    null,
    undefined,
    "nope",
    {},
    { subscriptionState: "SUBSCRIPTION_STATE_ACTIVE" },
    { subscriptionState: "SUBSCRIPTION_STATE_ACTIVE", lineItems: [] },
    { subscriptionState: "SUBSCRIPTION_STATE_ACTIVE", lineItems: "broken" },
    {
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      lineItems: [{ productId: "are_coach_monthly", expiryTime: "not-a-date" }],
    },
  ];
  for (const c of cases) {
    assert.equal(decidePlaySubscription(c, NOW).valid, false);
  }
});

test("play: state matching is case-insensitive", () => {
  const d = decidePlaySubscription(playSub("subscription_state_active"), NOW);
  assert.equal(d.valid, true);
});
