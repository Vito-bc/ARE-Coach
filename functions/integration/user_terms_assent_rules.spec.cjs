"use strict";

// Validates the firestore.rules changes for this slice: a `users/{uid}`
// document can only ever be CREATED with a full, typed, size-capped assent
// record attached (termsAcceptedVersion/termsAcceptedAt,
// privacyAcceptedVersion/privacyAcceptedAt), and those fields can never be
// changed afterward via update (re-consent stays dormant -- see
// lib/core/legal_versions.dart). Runs against the real rules file on the
// local Firestore emulator, using the CLIENT SDK so rules are actually
// enforced (unlike firebase-admin, which bypasses them).
const { test, before, after, beforeEach } = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const { doc, setDoc, serverTimestamp } = require("firebase/firestore");

let env;

before(async () => {
  // Refuse to run unless explicitly connected to the local demo emulator.
  if (process.env.FIRESTORE_EMULATOR_HOST !== "127.0.0.1:8087") {
    throw Error("Local emulator required");
  }
  env = await initializeTestEnvironment({
    projectId: "demo-are-coach",
    firestore: {
      host: "127.0.0.1",
      port: 8087,
      rules: readFileSync(join(__dirname, "../../firestore.rules"), "utf8"),
    },
  });
});

beforeEach(async () => env.clearFirestore());

after(async () => {
  if (env) await env.cleanup();
});

function fullAssentPayload() {
  return {
    email: "a@example.com",
    name: null,
    role: "free",
    createdAt: serverTimestamp(),
    lastActiveAt: serverTimestamp(),
    termsAcceptedVersion: "2026-06-03",
    termsAcceptedAt: serverTimestamp(),
    privacyAcceptedVersion: "2026-06-03",
    privacyAcceptedAt: serverTimestamp(),
  };
}

test("owner can create their own user doc with a full, valid assent record", async () => {
  const db = env.authenticatedContext("A").firestore();
  await assertSucceeds(setDoc(doc(db, "users/A"), fullAssentPayload()));
});

test("create is rejected when the assent fields are missing entirely (pre-slice shape)", async () => {
  const db = env.authenticatedContext("A").firestore();
  await assertFails(
    setDoc(doc(db, "users/A"), {
      email: "a@example.com",
      role: "free",
      createdAt: serverTimestamp(),
      lastActiveAt: serverTimestamp(),
    })
  );
});

test("create is rejected when only the terms half of the assent record is present", async () => {
  const db = env.authenticatedContext("A").firestore();
  const { privacyAcceptedVersion, privacyAcceptedAt, ...partial } = fullAssentPayload();
  await assertFails(setDoc(doc(db, "users/A"), partial));
});

test("create is rejected when a version field is the wrong type", async () => {
  const db = env.authenticatedContext("A").firestore();
  await assertFails(
    setDoc(doc(db, "users/A"), {
      ...fullAssentPayload(),
      termsAcceptedVersion: 20260603,
    })
  );
});

test("create is rejected when a version string exceeds the size cap", async () => {
  const db = env.authenticatedContext("A").firestore();
  await assertFails(
    setDoc(doc(db, "users/A"), {
      ...fullAssentPayload(),
      termsAcceptedVersion: "x".repeat(21),
    })
  );
});

test("create is rejected when an accepted-at field is not a timestamp", async () => {
  const db = env.authenticatedContext("A").firestore();
  await assertFails(
    setDoc(doc(db, "users/A"), {
      ...fullAssentPayload(),
      termsAcceptedAt: "2026-06-03T00:00:00Z",
    })
  );
});

test("an owner cannot later modify the assent fields via update -- re-consent stays dormant", async () => {
  const db = env.authenticatedContext("A").firestore();
  await assertSucceeds(setDoc(doc(db, "users/A"), fullAssentPayload()));
  await assertFails(
    setDoc(doc(db, "users/A"), { termsAcceptedVersion: "2027-01-01" }, { merge: true })
  );
  await assertFails(
    setDoc(doc(db, "users/A"), { privacyAcceptedAt: serverTimestamp() }, { merge: true })
  );
  // The pre-existing, unrelated update surface is unchanged by this slice.
  await assertSucceeds(setDoc(doc(db, "users/A"), { name: "A" }, { merge: true }));
});

test("an unauthenticated client cannot create a user doc even with a complete assent record", async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertFails(setDoc(doc(db, "users/A"), fullAssentPayload()));
});

test("an owner cannot create SOMEONE ELSE's user doc, assent record or not", async () => {
  const db = env.authenticatedContext("A").firestore();
  await assertFails(setDoc(doc(db, "users/B"), fullAssentPayload()));
});
