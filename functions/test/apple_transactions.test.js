"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { configuration, classifyTransaction, handleAppleRequest } = require("../lib/apple_transactions");
const config = { bundleId: "com.example.coach", environment: "Production", appAppleId: 123 };
const now = Date.now();
const payload = { bundleId: config.bundleId, environment: "Production", productId: "are_coach_monthly",
  type: "Auto-Renewable Subscription", transactionId: "123", originalTransactionId: "100",
  purchaseDate: now - 1000, signedDate: now, expiresDate: now + 100000,
  inAppOwnershipType: "PURCHASED", appAccountToken: "00112233-4455-4677-8899-aabbccddeeff" };
const request = { platform: "app_store", receiptFormat: "storekit2_jws", receiptData: "signed.fixture.jws",
  transactionId: "123", productId: payload.productId };
test("server config rejects missing identifiers and unsigned testing modes", () => {
  for (const environment of [undefined, "LocalTesting", "Xcode", "", true]) {
    assert.throws(() => configuration({ APPLE_BUNDLE_ID: config.bundleId, APPLE_ENVIRONMENT: environment, APPLE_APP_ID: "123" }));
  }
  for (const appId of [undefined, "", "0", "1.1", true, null]) {
    assert.throws(() => configuration({ APPLE_BUNDLE_ID: config.bundleId, APPLE_ENVIRONMENT: "Production", APPLE_APP_ID: appId }));
  }
});
test("verified, expired and revoked are distinct from malformed signed data", () => {
  assert.equal(classifyTransaction(payload, request, config).transaction.outcome, "verified");
  assert.equal(classifyTransaction({ ...payload, expiresDate: now - 1 }, request, config).transaction.outcome, "not_entitled");
  assert.equal(classifyTransaction({ ...payload, revocationDate: now }, request, config).transaction.outcome, "not_entitled");
  for (const patch of [{ expiresDate: null }, { expiresDate: true }, { expiresDate: "123" }, { signedDate: undefined },
    { bundleId: "wrong" }, { environment: "Sandbox" }, { productId: "unknown" }, { transactionId: "456" },
    { originalTransactionId: "../escape" }, { appAccountToken: undefined }, { inAppOwnershipType: "FAMILY_SHARED" }]) {
    assert.equal(classifyTransaction({ ...payload, ...patch }, request, config).error.status, 503);
  }
});
test("endpoint outage then retry recovers without mutating on failure", async () => {
  let calls = 0, writes = 0;
  const dependencies = { config, verify: async () => { if (++calls === 1) throw Error("outage"); return payload; },
    repository: { apply: async () => { writes++; return { status: 200 }; } } };
  assert.equal((await handleAppleRequest(request, "A", dependencies)).status, 503);
  assert.equal(writes, 0);
  assert.equal((await handleAppleRequest(request, "A", dependencies)).status, 200);
  assert.equal(writes, 1);
});
test("JWS cannot fall back to legacy and legacy cannot claim ownership", async () => {
  let legacy = 0, writes = 0;
  const dependencies = { config, verify: async () => { throw Error("signature"); },
    validateLegacy: async () => { legacy++; return { valid: true }; }, repository: { apply: async () => writes++ } };
  assert.equal((await handleAppleRequest(request, "A", dependencies)).status, 503);
  assert.equal((await handleAppleRequest({ ...request, receiptFormat: "legacy_receipt" }, "A", dependencies)).status, 503);
  assert.equal(legacy, 0);
  assert.equal((await handleAppleRequest({ ...request, receiptData: "base64", receiptFormat: "legacy_receipt" }, "A", dependencies)).body.code, "apple_ownership_recovery_required");
  assert.equal(legacy, 1);
  assert.equal(writes, 0);
});
