const { test, before, after, beforeEach } = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { initializeTestEnvironment, assertFails, assertSucceeds } = require("@firebase/rules-unit-testing");
const { doc, setDoc, getDoc } = require("firebase/firestore");
const { initializeApp, deleteApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { SignedDataVerifier } = require("@apple/app-store-server-library");
const { createAppleRepository } = require("../lib/apple_ownership");
const { handleAppleRequest } = require("../lib/apple_transactions");
const { fixtures } = require("./signed_fixtures.cjs");
const config = { bundleId: "com.example.coach", environment: "Production", appAppleId: 123, firebaseProjectId: "demo-are-coach" };
let env, app, db, repository, pki, verifier;
before(async () => {
  // Refuse to run unless explicitly connected to the local demo emulator.
  if (process.env.FIRESTORE_EMULATOR_HOST !== "127.0.0.1:8087") throw Error("Local emulator required");
  env = await initializeTestEnvironment({ projectId: "demo-are-coach", firestore: {
    host: "127.0.0.1", port: 8087, rules: readFileSync(join(__dirname, "../../firestore.rules"), "utf8") } });
  app = initializeApp({ projectId: "demo-are-coach" }, "apple-integration");
  db = getFirestore(app);
  repository = createAppleRepository(db, config, Timestamp);
  pki = fixtures(); verifier = new SignedDataVerifier([pki.root], false, config.environment, config.bundleId, config.appAppleId);
});
beforeEach(async () => env.clearFirestore());
after(async () => { pki?.close(); if (env) await env.cleanup(); if (app) await deleteApp(app); });
async function payload(patch = {}) {
  const now = Date.now();
  return { bundleId: config.bundleId, environment: "Production", productId: "are_coach_monthly",
    type: "Auto-Renewable Subscription", transactionId: "123", originalTransactionId: "100",
    purchaseDate: now - 5000, signedDate: now, expiresDate: now + 100000, inAppOwnershipType: "PURCHASED",
    appAccountToken: await repository.tokenFor("A"), ...patch };
}
function request(p, uid = "A", deps = {}) {
  const requestConfig = deps.config || config;
  return handleAppleRequest({ receiptFormat: "storekit2_jws", receiptData: pki.signed(p),
    transactionId: p.transactionId, productId: p.productId, appleEnvironment: requestConfig.environment,
    firebaseProjectId: requestConfig.firebaseProjectId,
    entitlementSource: requestConfig.environment === "Sandbox" ? "apple_sandbox" : "production" }, uid, { config,
    verify: jws => verifier.verifyAndDecodeTransaction(jws), repository, ...deps });
}
const records = async kind => (await db.collectionGroup(kind).get()).docs.map(d => d.data());
test("stable token provisioning and concurrent signed A/B replay have only one owner", async () => {
  const tokens = await Promise.all(Array.from({ length: 6 }, () => repository.tokenFor("A")));
  assert.equal(new Set(tokens).size, 1);
  await repository.tokenFor("B");
  await db.doc("users/B").set({ role: "premium", subscriptionStatus: "active", premiumUntil: Timestamp.fromMillis(Date.now() + 200000) });
  const beforeB = (await db.doc("users/B").get()).data();
  const p = await payload();
  const results = await Promise.all([request(p, "A"), request(p, "B"), request(p, "A"), request(p, "B")]);
  assert.deepEqual(results.map(r => r.status), [200, 503, 200, 503]);
  assert.deepEqual(await records("owners"), [{ uid: "A" }]);
  assert.equal((await records("transactions")).length, 1);
  assert.equal((await db.doc("users/A").get()).data().premiumUntil.toMillis(), p.expiresDate);
  assert.deepEqual((await db.doc("users/B").get()).data(), beforeB);
  const ledger = await records("transactions");
  await request(p);
  assert.deepEqual(await records("transactions"), ledger);
});
test("missing/unknown/foreign token and outage leave all entitlements and ownership untouched", async () => {
  const p = await payload();
  await db.doc("users/A").set({ role: "premium", subscriptionStatus: "active", premiumUntil: Timestamp.fromMillis(p.expiresDate) });
  const before = (await db.doc("users/A").get()).data();
  for (const token of [undefined, "00112233-4455-4677-8899-aabbccddeeff", await repository.tokenFor("B")]) {
    assert.equal((await request({ ...p, appAccountToken: token })).status, 503);
  }
  assert.equal((await request(p, "A", { verify: async () => { throw Error("outage"); } })).status, 503);
  assert.deepEqual((await db.doc("users/A").get()).data(), before);
  assert.deepEqual(await records("owners"), []);
  assert.deepEqual(await records("transactions"), []);
  assert.equal((await request(p)).status, 200);
});
test("failed Firestore commit rolls back ownership, ledger and entitlement together", async () => {
  const p = await payload();
  const poison = db.doc("testFault/existing"); await poison.set({ exists: true });
  const failingDb = { collection: name => db.collection(name), runTransaction: (fn, options) => db.runTransaction(tx => {
    const set = tx.set.bind(tx);
    tx.set = (...args) => { set(...args); tx.create(poison, { conflict: true }); return tx; };
    return fn(tx);
  }, options) };
  assert.equal((await request(p, "A", { repository: createAppleRepository(failingDb, config, Timestamp) })).status, 503);
  assert.deepEqual(await records("owners"), []);
  assert.deepEqual(await records("transactions"), []);
  assert.equal((await db.doc("users/A").get()).exists, false);
  assert.equal((await request(p)).status, 200);
});
test("older expired transaction cannot overwrite newer entitlement; revocation is monotonic", async () => {
  const newer = await payload({ transactionId: "124" });
  await request(newer);
  const before = (await db.doc("users/A").get()).data();
  const expired = await payload({ expiresDate: Date.now() - 1 });
  const rejection = await request(expired);
  assert.equal(rejection.body.outcome, "not_entitled");
  assert.equal(rejection.body.transactionFinalization, "not_safe");
  assert.deepEqual((await db.doc("users/A").get()).data(), before);
  assert.equal((await request({ ...newer, revocationDate: Date.now() })).body.valid, false);
  assert.equal((await db.doc("users/A").get()).data().subscriptionStatus, "expired");
  assert.equal((await request(newer)).body.valid, false);
  assert.equal((await db.doc("users/A").get()).data().subscriptionStatus, "expired");
});
test("revoked yearly expiry cannot block a new monthly entitlement", async () => {
  const now = Date.now();
  const yearly = await payload({ productId: "are_coach_yearly", expiresDate: now + 365 * 86400000 });
  assert.equal((await request(yearly)).body.valid, true);
  const revoked = { ...yearly, revocationDate: now };
  assert.equal((await request(revoked)).body.valid, false);
  assert.equal((await db.doc("users/A").get()).data().subscriptionStatus, "expired");
  const monthly = await payload({ transactionId: "124", originalTransactionId: "101", expiresDate: now + 30 * 86400000 });
  assert.equal((await request(monthly)).body.outcome, "verified");
  const active = (await db.doc("users/A").get()).data();
  assert.equal(active.role, "premium");
  assert.equal(active.subscriptionStatus, "active");
  assert.equal(active.appleTransactionId, monthly.transactionId);
  assert.equal(active.premiumUntil.toMillis(), monthly.expiresDate);
  const ledger = await records("transactions");
  await request(monthly);
  assert.deepEqual(await records("transactions"), ledger);
  for (const old of [yearly, revoked, await payload({ transactionId: "122", expiresDate: now - 1 })]) {
    assert.equal((await request(old)).body.valid, false);
    assert.deepEqual((await db.doc("users/A").get()).data(), active);
  }
});

test("sandbox has separate ownership namespace and cannot grant production Premium", async () => {
  const sandbox = { ...config, environment: "Sandbox" };
  const sandboxRepository = createAppleRepository(db, sandbox, Timestamp);
  const token = await sandboxRepository.tokenFor("A");
  const p = await payload({ environment: "Sandbox", appAccountToken: token });
  const sandboxVerifier = new SignedDataVerifier([pki.root], false, "Sandbox", config.bundleId, config.appAppleId);
  const result = await request(p, "A", { config: sandbox, repository: sandboxRepository,
    verify: jws => sandboxVerifier.verifyAndDecodeTransaction(jws) });
  assert.equal(result.body.entitlementScope, "sandbox");
  assert.equal((await db.doc("users/A").get()).exists, false);
  assert.equal((await records("sandboxEntitlements")).length, 1);
  assert.equal((await request(p)).status, 503);
});
test("sandbox entitlement endpoint returns only the authenticated uid and exact processed proof", async () => {
  const sandbox = { ...config, environment: "Sandbox" };
  const sandboxRepository = createAppleRepository(db, sandbox, Timestamp);
  const token = await sandboxRepository.tokenFor("A");
  const p = await payload({ environment: "Sandbox", appAccountToken: token });
  const sandboxVerifier = new SignedDataVerifier([pki.root], false, "Sandbox", config.bundleId, config.appAppleId);
  await request(p, "A", { config: sandbox, repository: sandboxRepository,
    verify: jws => sandboxVerifier.verifyAndDecodeTransaction(jws) });
  const result = await handleAppleRequest({ action: "get_apple_entitlement", platform: "app_store",
    appleEnvironment: "Sandbox", firebaseProjectId: config.firebaseProjectId, entitlementSource: "apple_sandbox",
    transactionId: p.transactionId, productId: p.productId, uid: "B" }, "A",
  { config: sandbox, repository: sandboxRepository });
  assert.equal(result.body.uid, "A");
  assert.equal(result.body.active, true);
  assert.equal(result.body.processedTransaction, true);
  const foreign = await handleAppleRequest({ action: "get_apple_entitlement", platform: "app_store",
    appleEnvironment: "Sandbox", firebaseProjectId: config.firebaseProjectId, entitlementSource: "apple_sandbox",
    transactionId: p.transactionId, productId: p.productId }, "B",
  { config: sandbox, repository: sandboxRepository });
  assert.equal(foreign.body.active, false);
  assert.equal(foreign.body.processedTransaction, false);
  assert.equal((await db.doc("users/A").get()).exists, false);
});
test("Firestore rules deny billing reads and writes for owner, foreign, admin and anonymous clients", async () => {
  await request(await payload());
  const ownerPath = (await db.collectionGroup("owners").get()).docs[0].ref.path;
  const accountPath = (await db.collectionGroup("accounts").get()).docs[0].ref.path;
  for (const client of [env.authenticatedContext("A"), env.authenticatedContext("B"),
    env.authenticatedContext("admin", { role: "admin" }), env.unauthenticatedContext()]) {
    for (const path of [ownerPath, accountPath, "appleBilling/fake/tokens/fake", "appleBilling/fake/transactions/123"]) {
      await assertFails(getDoc(doc(client.firestore(), path)));
      await assertFails(setDoc(doc(client.firestore(), path), { uid: "B" }));
    }
  }
  const owner = env.authenticatedContext("A").firestore();
  await assertSucceeds(getDoc(doc(owner, "users/A")));
  await assertFails(setDoc(doc(owner, "users/A"), { premiumUntil: new Date(Date.now() + 999999999) }, { merge: true }));
  await assertSucceeds(setDoc(doc(owner, "users/A"), { name: "A" }, { merge: true }));
});
