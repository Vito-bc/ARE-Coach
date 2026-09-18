"use strict";

// Regression test for two review-found gaps in the read-only export guard.
// Fake-based coverage of the same contracts lives in test/read_only_db.test.js;
// this file re-proves them against the real SDK, since a fake can be wrong
// about SDK internals in a way a fake-only test would never catch.
//
// 1. (HIGH) `.get()` (on a document OR a query/collection), `.stream()`, and
//    `Firestore.prototype.getAll()` all resolve to a DocumentSnapshot/
//    QuerySnapshot whose `.ref` the real @google-cloud/firestore SDK builds
//    from the raw, unwrapped target -- not from src/read_only_db.js's Proxy.
//    Reproduced three ways (doc.get().ref.set(), a query doc's .ref.set(),
//    a .stream() doc's .ref.set()), plus getAll().
// 2. (MEDIUM) every wrapped reference's `.firestore` back-pointer, and a
//    QuerySnapshot's `.query` back-pointer, hand back the RAW root
//    Firestore/Query unless re-wrapped -- reopening batch()/bulkWriter()/
//    etc. via one extra property access. Also: `docChanges()` is populated
//    on a one-shot `.get()`, not only a realtime listener's snapshot, so its
//    `.doc.ref` needs the same guard as `.docs[i].ref`.
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

test("a ref's .firestore back-pointer cannot write, including re-blocking batch()", async () => {
  await rawDb.collection("escape_test").doc("f1").set({ x: 1 });

  const ref = db.collection("escape_test").doc("f1");
  assert.throws(() => ref.firestore.batch(), /Read-only Firestore guard/);
  assert.throws(
    () => ref.firestore.collection("escape_test").doc("f1").set({ x: 777 }),
    /Read-only Firestore guard/
  );
  assert.deepEqual(await currentValue("escape_test/f1"), { x: 1 });
});

test("a snapshot's ref.firestore back-pointer cannot write", async () => {
  await rawDb.collection("escape_test").doc("f2").set({ x: 1 });

  const snap = await db.collection("escape_test").doc("f2").get();
  assert.throws(() => snap.ref.firestore.batch(), /Read-only Firestore guard/);
  assert.throws(
    () => snap.ref.firestore.collection("escape_test").doc("f2").set({ x: 777 }),
    /Read-only Firestore guard/
  );
  assert.deepEqual(await currentValue("escape_test/f2"), { x: 1 });
});

test("a query snapshot's .query back-pointer cannot write", async () => {
  await rawDb.collection("escape_test").doc("f3").set({ x: 1 });

  const query = await db.collection("escape_test").get();
  assert.throws(() => query.query.doc("f3").set({ x: 777 }), /Read-only Firestore guard/);
  assert.deepEqual(await currentValue("escape_test/f3"), { x: 1 });
});

test("a snapshot delivered to onSnapshot() cannot write", async () => {
  // The one public read route integration/read_only_reachability.spec.cjs
  // deliberately does not walk (a live listener would race its own first
  // callback inside a breadth-first walk and buy flakiness). Covered here
  // deterministically instead: subscribe, take the first snapshot,
  // unsubscribe.
  await rawDb.collection("escape_test").doc("o1").set({ x: 1 });

  const firstSnapshot = await new Promise((resolve, reject) => {
    let unsubscribe = null;
    let settled = false;
    const finish = (fn, value) => {
      if (settled) return;
      settled = true;
      if (unsubscribe) unsubscribe();
      fn(value);
    };
    unsubscribe = db.collection("escape_test").onSnapshot(
      (snap) => finish(resolve, snap),
      (err) => finish(reject, err)
    );
  });

  assert.ok(firstSnapshot.docs.length >= 1);
  for (const doc of firstSnapshot.docs) {
    assert.throws(() => doc.ref.set({ x: 777 }), /Read-only Firestore guard/);
  }
  assert.deepEqual(await currentValue("escape_test/o1"), { x: 1 });
});

test("docChanges()[i].doc.ref cannot write, on a plain one-shot get() (no listener involved)", async () => {
  await rawDb.collection("escape_test").doc("f4").set({ x: 1 });

  const query = await db.collection("escape_test").get();
  const changes = query.docChanges();
  assert.ok(changes.length >= 1);
  for (const change of changes) {
    assert.throws(() => change.doc.ref.set({ x: 777 }), /Read-only Firestore guard/);
  }
  assert.deepEqual(await currentValue("escape_test/f4"), { x: 1 });
});
