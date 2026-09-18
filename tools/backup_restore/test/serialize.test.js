"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp, GeoPoint, DocumentReference } = require("firebase-admin/firestore");
const { toPortable, fromPortable } = require("../src/serialize");

// Constructing an app/Firestore instance and building references from it is
// entirely local (no network call happens until a read/write is actually
// issued), so this stays a fast, emulator-free unit test even though it
// uses real firebase-admin classes -- a fake Timestamp/GeoPoint would prove
// nothing about whether `instanceof` actually matches the real ones.
const app = initializeApp({ projectId: "unit-test-project" }, "serialize-test");
const db = getFirestore(app);
const types = { Timestamp, GeoPoint, DocumentReference };

test("round-trips primitives and null unchanged", () => {
  for (const v of ["hello", 42, 3.14, true, false, null]) {
    assert.deepStrictEqual(fromPortable(toPortable(v, types), types, db), v);
  }
  assert.strictEqual(toPortable(undefined, types), null);
});

test("round-trips a Timestamp exactly (seconds and nanoseconds)", () => {
  const ts = new Timestamp(1_700_000_000, 123_000_000);
  const portable = toPortable(ts, types);
  assert.deepEqual(portable, { __t: "timestamp", seconds: 1_700_000_000, nanoseconds: 123_000_000 });
  const back = fromPortable(portable, types, db);
  assert.ok(back instanceof Timestamp);
  assert.ok(back.isEqual(ts));
});

test("round-trips a GeoPoint exactly", () => {
  const gp = new GeoPoint(40.7128, -74.006);
  const back = fromPortable(toPortable(gp, types), types, db);
  assert.ok(back instanceof GeoPoint);
  assert.ok(back.isEqual(gp));
});

test("round-trips a DocumentReference by path, rebuilt against the given db", () => {
  const ref = db.doc("users/abc123");
  const portable = toPortable(ref, types);
  assert.deepEqual(portable, { __t: "reference", path: "users/abc123" });
  const back = fromPortable(portable, types, db);
  assert.ok(back instanceof DocumentReference);
  assert.equal(back.path, "users/abc123");
});

test("round-trips raw bytes exactly", () => {
  const bytes = Buffer.from([0, 1, 2, 250, 255]);
  const back = fromPortable(toPortable(bytes, types), types, db);
  assert.ok(Buffer.isBuffer(back));
  assert.ok(back.equals(bytes));
});

test("round-trips arrays, including mixed-type and nested arrays", () => {
  const ts = new Timestamp(1, 0);
  const value = [1, "two", [3, ts], null];
  const back = fromPortable(toPortable(value, types), types, db);
  assert.equal(back[0], 1);
  assert.equal(back[1], "two");
  assert.equal(back[2][0], 3);
  assert.ok(back[2][1].isEqual(ts));
  assert.equal(back[3], null);
});

test("round-trips nested maps, including a Timestamp several levels deep", () => {
  const value = {
    role: "premium",
    dailyLimits: { questions: 20, coachMessages: { max: 10, resetAt: new Timestamp(2, 0) } },
  };
  const back = fromPortable(toPortable(value, types), types, db);
  assert.equal(back.role, "premium");
  assert.equal(back.dailyLimits.questions, 20);
  assert.equal(back.dailyLimits.coachMessages.max, 10);
  assert.ok(back.dailyLimits.coachMessages.resetAt.isEqual(new Timestamp(2, 0)));
});

test("toPortable sorts map keys, so the same input always serializes identically", () => {
  const a = toPortable({ b: 1, a: 2, c: 3 }, types);
  const b = toPortable({ c: 3, a: 2, b: 1 }, types);
  assert.deepStrictEqual(JSON.stringify(a), JSON.stringify(b));
  assert.deepStrictEqual(Object.keys(a), ["a", "b", "c"]);
});
