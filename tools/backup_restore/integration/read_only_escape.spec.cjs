"use strict";

// Regression test for a HIGH-severity gap found in review: `.get()` (on a
// document OR a query/collection), `.stream()`, and `Firestore.prototype.
// getAll()` all resolve to a DocumentSnapshot/QuerySnapshot whose `.ref` the
// real @google-cloud/firestore SDK builds from the raw, unwrapped target --
// not from src/read_only_db.js's Proxy. Before the fix, this was a live,
// fully-writable escape from the read-only guard, reproduced against the
// real emulator three ways (doc.get().ref.set(), a query doc's .ref.set(),
// and a .stream() doc's .ref.set()). Fake-based coverage of the same
// contract lives in test/read_only_db.test.js; this file re-proves it
// against the real SDK, since a fake can be wrong about how the SDK
// actually builds a snapshot's `.ref` in a way a fake-only test would never
// catch.
//
// Run (mirrors this repo's other emulator-backed specs):
//   npx --yes firebase-tools@15.8.0 emulators:exec --only firestore \
//     --project demo-are-coach --config firebase.test.json \
//     "node --test tools/backup_restore/integration/read_only_escape.spec.cjs"

const { test, before, beforeEach } = require("node:test");
const assert = require("node:assert/strict");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { makeReadOnlyFirestore } = require("../src/read_only_db");

const PROJECT_ID = "demo-are-coach";
const EMULATOR_HOST = "127.0.0.1:8087";

let rawDb;
let db;

before(() => {
  if (process.env.FIRESTORE_EMULATOR_HOST !== EMULATOR_HOST) {
    throw new Error(`Local emulator required (FIRESTORE_EMULATOR_HOST must be ${EMULATOR_HOST})`);
  }
  const app = initializeApp({ projectId: PROJECT_ID }, "read-only-escape-spec");
  rawDb = getFirestore(app);
  db = makeReadOnlyFirestore(rawDb);
});

beforeEach(async () => {
  await rawDb.recursiveDelete(rawDb.collection("escape_test"));
});

async function currentValue(path) {
  const snap = await rawDb.doc(path).get();
  return snap.exists ? snap.data() : null;
}

test("a document snapshot's .ref from a wrapped doc's .get() cannot write", async () => {
  await rawDb.collection("escape_test").doc("d1").set({ x: 1 });

  const snap = await db.collection("escape_test").doc("d1").get();
  assert.equal(snap.exists, true);
  assert.deepEqual(snap.data(), { x: 1 });

  // The guard throws SYNCHRONOUSLY (see src/read_only_db.js's blocked()) --
  // .set() never even returns a promise to reject, so this is
  // assert.throws, not assert.rejects (which requires a function that
  // returns a promise; handed a sync throw instead, it lets the exception
  // escape uncaught rather than matching it).
  assert.throws(
    () => snap.ref.set({ x: 777 }),
    /Read-only Firestore guard/,
    "snap.ref.set() must be blocked by the guard, not reach the emulator"
  );
  assert.deepEqual(await currentValue("escape_test/d1"), { x: 1 }, "the document must be unchanged");
});

test("a query document snapshot's .ref from a wrapped collection's .get() cannot write", async () => {
  await rawDb.collection("escape_test").doc("q1").set({ x: 1 });
  await rawDb.collection("escape_test").doc("q2").set({ x: 1 });

  const query = await db.collection("escape_test").get();
  assert.equal(query.docs.length, 2);
  for (const doc of query.docs) {
    assert.throws(() => doc.ref.set({ x: 777 }), /Read-only Firestore guard/);
  }
  assert.deepEqual(await currentValue("escape_test/q1"), { x: 1 });
  assert.deepEqual(await currentValue("escape_test/q2"), { x: 1 });
});

test("a snapshot emitted by a wrapped collection's .stream() cannot write", async () => {
  await rawDb.collection("escape_test").doc("s1").set({ x: 1 });

  const stream = db.collection("escape_test").stream();
  let seen = 0;
  for await (const doc of stream) {
    seen += 1;
    assert.throws(() => doc.ref.set({ x: 777 }), /Read-only Firestore guard/);
  }
  assert.equal(seen, 1);
  assert.deepEqual(await currentValue("escape_test/s1"), { x: 1 });
});

test("db.getAll() results are guarded even when given wrapped refs as arguments", async () => {
  await rawDb.collection("escape_test").doc("g1").set({ x: 1 });
  await rawDb.collection("escape_test").doc("g2").set({ x: 1 });

  const refA = db.collection("escape_test").doc("g1");
  const refB = db.collection("escape_test").doc("g2");
  const [snapA, snapB] = await db.getAll(refA, refB);
  assert.deepEqual(snapA.data(), { x: 1 });
  assert.deepEqual(snapB.data(), { x: 1 });

  assert.throws(() => snapA.ref.set({ x: 777 }), /Read-only Firestore guard/);
  assert.throws(() => snapB.ref.set({ x: 777 }), /Read-only Firestore guard/);
  assert.deepEqual(await currentValue("escape_test/g1"), { x: 1 });
  assert.deepEqual(await currentValue("escape_test/g2"), { x: 1 });
});
