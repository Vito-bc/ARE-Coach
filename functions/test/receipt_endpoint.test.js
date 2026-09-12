"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");

const {
  RECEIPT_OUTCOME,
  decideAppleReceipt,
} = require("../lib/receipts");
const { validateAppleReceipt } = require("../lib/apple_validation");
const { applyReceiptDecision } = require("../lib/receipt_endpoint");

function effects() {
  const calls = { grant: [], downgrade: [] };
  return {
    calls,
    grant: async (decision) => calls.grant.push(decision),
    downgrade: async (decision) => calls.downgrade.push(decision),
  };
}

test("endpoint grants a verified eligible receipt", async () => {
  const fx = effects();
  const decision = decideAppleReceipt({
    status: 0,
    latest_receipt_info: [{
      product_id: "are_coach_monthly",
      expires_date_ms: "4102444800000",
    }],
  });
  const result = await applyReceiptDecision(decision, fx);
  assert.equal(result.status, 200);
  assert.deepEqual(result.body, {
    valid: true,
    outcome: RECEIPT_OUTCOME.VERIFIED,
    expiresAt: decision.expiresAt,
  });
  assert.equal(fx.calls.grant.length, 1);
  assert.equal(fx.calls.downgrade.length, 0);
});

test("endpoint downgrades only authoritative non-entitlement", async () => {
  const fx = effects();
  const decision = decideAppleReceipt({ status: 21006 });
  const result = await applyReceiptDecision(decision, fx);
  assert.equal(result.status, 200);
  assert.deepEqual(result.body, {
    valid: false,
    outcome: RECEIPT_OUTCOME.NOT_ENTITLED,
    reason: "expired",
    transactionFinalization: "not_safe",
  });
  assert.equal(fx.calls.grant.length, 0);
  assert.equal(fx.calls.downgrade.length, 1);
});

test("temporary, configuration and protocol failures never mutate entitlement", async () => {
  const decisions = [
    decideAppleReceipt({ status: 21005 }),
    decideAppleReceipt({ status: 21004 }),
    decideAppleReceipt({ status: null, latest_receipt_info: [] }),
    decideAppleReceipt({ status: 29999 }),
    await validateAppleReceipt("receipt", {
      sharedSecret: "",
      callApple: async () => {
        throw new Error("must not run");
      },
    }),
  ];
  for (const decision of decisions) {
    const fx = effects();
    const result = await applyReceiptDecision(decision, fx);
    assert.notEqual(result.status, 200);
    assert.equal(result.body.code, "validation_unavailable");
    assert.equal(result.body.retryable, decision.retryable === true);
    assert.equal(fx.calls.grant.length, 0);
    assert.equal(fx.calls.downgrade.length, 0);
  }
});

test("unknown decision shape fails unavailable without any mutation", async () => {
  for (const malformed of [
    { valid: true },
    { outcome: RECEIPT_OUTCOME.VERIFIED, valid: true },
    {
      outcome: RECEIPT_OUTCOME.VERIFIED,
      valid: true,
      productId: "another_app_subscription",
      expiresAt: 4102444800000,
    },
    {
      outcome: RECEIPT_OUTCOME.VERIFIED,
      valid: true,
      productId: "are_coach_monthly",
      expiresAt: 1,
    },
    { outcome: RECEIPT_OUTCOME.NOT_ENTITLED, valid: false },
    {
      outcome: RECEIPT_OUTCOME.NOT_ENTITLED,
      valid: false,
      reason: "expired",
      retryable: true,
    },
    {
      outcome: RECEIPT_OUTCOME.UNAVAILABLE,
      valid: false,
      reason: "bad_status",
      httpStatus: 200,
    },
  ]) {
    const fx = effects();
    const result = await applyReceiptDecision(malformed, fx);
    assert.equal(result.status, 502);
    assert.equal(result.body.code, "validation_unavailable");
    assert.equal(fx.calls.grant.length, 0);
    assert.equal(fx.calls.downgrade.length, 0);
  }
});
