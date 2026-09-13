const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { SignedDataVerifier } = require("@apple/app-store-server-library");
const { fixtures } = require("./signed_fixtures.cjs");
const { handleAppleRequest } = require("../lib/apple_transactions");
const { verifyAppleTransaction } = require("../lib/apple_verifier");
const config = { bundleId: "com.example.coach", environment: "Production", appAppleId: 123 };
let pki, verifier;
before(() => { pki = fixtures(); verifier = new SignedDataVerifier([pki.root], false, config.environment, config.bundleId, config.appAppleId); });
after(() => pki?.close());
function payload() { const now = Date.now(); return { bundleId: config.bundleId, environment: "Production",
  productId: "are_coach_monthly", type: "Auto-Renewable Subscription", transactionId: "123", originalTransactionId: "100",
  purchaseDate: now - 1000, signedDate: now, expiresDate: now + 100000, inAppOwnershipType: "PURCHASED",
  appAccountToken: "00112233-4455-4677-8899-aabbccddeeff" }; }
test("real verifier accepts test-signed ES256 chain and correct transaction", async () => {
  const p = payload();
  assert.deepEqual(await verifier.verifyAndDecodeTransaction(pki.signed(p)), p);
});
test("real verifier rejects altered payload, signature, bundle and environment", async () => {
  const jws = pki.signed(payload());
  const parts = jws.split(".");
  const tampered = [...parts]; tampered[1] = Buffer.from(JSON.stringify({ ...payload(), transactionId: "999" })).toString("base64url");
  const badSignature = [...parts]; const bytes = Buffer.from(parts[2], "base64url"); bytes[0] ^= 1; badSignature[2] = bytes.toString("base64url");
  for (const invalid of [tampered.join("."), badSignature.join("."), pki.signed({ ...payload(), bundleId: "wrong" }),
    pki.signed({ ...payload(), environment: "Sandbox" })]) await assert.rejects(verifier.verifyAndDecodeTransaction(invalid));
});
test("endpoint applies policy after real signature verification", async () => {
  let writes = 0;
  const deps = { config, verify: jws => verifier.verifyAndDecodeTransaction(jws),
    repository: { apply: async () => { writes++; return { status: 200 }; } } };
  for (const patch of [{ productId: "other" }, { transactionId: "999" }, { appAccountToken: undefined }, { expiresDate: null }]) {
    const result = await handleAppleRequest({ receiptFormat: "storekit2_jws", receiptData: pki.signed({ ...payload(), ...patch }),
      transactionId: "123", productId: "are_coach_monthly" }, "A", deps);
    assert.equal(result.status, 503);
  }
  assert.equal(writes, 0);
});
test("production worker cannot trust the test root or enable LocalTesting", async () => {
  await assert.rejects(verifyAppleTransaction(pki.signed(payload()), config));
  await assert.rejects(verifyAppleTransaction(pki.signed({ ...payload(), environment: "LocalTesting" }), { ...config, environment: "LocalTesting" }));
});
