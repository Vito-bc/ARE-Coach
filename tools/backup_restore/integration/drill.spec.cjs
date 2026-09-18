"use strict";

// THE DRILL. This is the actual deliverable this tool exists to produce: a
// running, automated proof that a real disaster-recovery restore works, not
// just that the code compiles. It exercises the real CLI entry points (as
// child processes, exactly as an operator would run them) against the local
// Firestore emulator, using synthetic data only.
//
//   seed synthetic data -> export (real CLI) -> wipe -> restore (real CLI)
//   -> verify restored state is field-for-field equivalent to seeded state
//
// "Equivalent" here means: exportAll() reads back an IDENTICAL portable-JSON
// tree before the wipe and after the restore -- same document paths, same
// `exists` flags (including parent-only documents that were never written,
// only implied by a subcollection -- see tree.js), same field values with
// exact types (a restored Timestamp must still be a Timestamp with the same
// seconds/nanoseconds, not a string or a plain object), same array contents
// and order, same nested maps, at every depth including the 3-collection-
// deep appleBilling ledger. assert.deepStrictEqual on those two trees is the
// literal equivalence check -- see the "restored state is field-for-field
// equivalent" test below.
//
// Run (mirrors this repo's other emulator-backed specs):
//   npx --yes firebase-tools@15.8.0 emulators:exec --only firestore \
//     --project demo-are-coach --config firebase.test.json \
//     "node --test tools/backup_restore/integration/drill.spec.cjs"

const { test, before, beforeEach } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

const { COVERED_COLLECTIONS } = require("../src/collections");
const { exportAll, countExisting } = require("../src/tree");

const PROJECT_ID = "demo-are-coach";
const REPO_ROOT = path.join(__dirname, "..", "..", "..");
const EXPORT_BIN = path.join(__dirname, "..", "bin", "export_firestore.js");
const RESTORE_BIN = path.join(__dirname, "..", "bin", "restore_firestore.js");

let db;
const types = () => ({ Timestamp, GeoPoint: require("firebase-admin/firestore").GeoPoint, DocumentReference: require("firebase-admin/firestore").DocumentReference });

before(() => {
  // Same guard as this repo's other emulator specs: refuse to run anywhere
  // that isn't unambiguously the local demo emulator.
  if (process.env.FIRESTORE_EMULATOR_HOST !== "127.0.0.1:8087") {
    throw new Error("Local emulator required (FIRESTORE_EMULATOR_HOST must be 127.0.0.1:8087)");
  }
  const app = initializeApp({ projectId: PROJECT_ID }, "backup-restore-drill");
  db = getFirestore(app);
});

async function wipeAllCovered() {
  for (const name of COVERED_COLLECTIONS) {
    // recursiveDelete on a CollectionReference removes every document in it
    // and everything nested under each of them -- the same primitive
    // functions/index.js's deleteAccount uses for a real per-user tree.
    await db.recursiveDelete(db.collection(name));
  }
}

beforeEach(async () => {
  await wipeAllCovered();
});

function mkTmpDir(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function runNode(scriptPath, args, options = {}) {
  try {
    const stdout = execFileSync(process.execPath, [scriptPath, ...args], {
      cwd: path.join(__dirname, ".."),
      env: process.env,
      encoding: "utf8",
      input: options.input,
    });
    return { status: 0, stdout, stderr: "" };
  } catch (err) {
    return { status: err.status ?? 1, stdout: err.stdout || "", stderr: err.stderr || String(err) };
  }
}

/** One doc for each covered collection's real shape, with subcollections,
 * nested maps, arrays, and timestamps at several depths. Mirrors the actual
 * document shapes this app writes (see functions/lib/apple_ownership.js,
 * functions/index.js, and firestore.rules) closely enough that a schema
 * regression here would be a real signal, not a strawman.
 */
async function seedSyntheticData() {
  const t = (iso) => Timestamp.fromDate(new Date(iso));

  // --- users -----------------------------------------------------------
  await db.collection("users").doc("alice").set({
    email: "alice@example.com",
    name: "Alice Archer",
    role: "premium",
    targetExamDate: t("2027-03-01T00:00:00Z"),
    createdAt: t("2026-01-05T12:00:00Z"),
    lastActiveAt: t("2026-09-10T08:30:00Z"),
    dailyLimits: { questions: 999, coachMessages: { max: 999, resetAt: t("2026-09-11T00:00:00Z") } },
    termsAcceptedVersion: "2026-06-03",
    termsAcceptedAt: t("2026-01-05T12:00:00Z"),
    privacyAcceptedVersion: "2026-06-03",
    privacyAcceptedAt: t("2026-01-05T12:00:00Z"),
    subscriptionStatus: "active",
    subscriptionPlatform: "app_store",
    subscriptionId: "are_coach_yearly",
    premiumUntil: t("2027-01-01T00:00:00Z"),
    appleTransactionId: "1000000123",
    appleOriginalTransactionId: "1000000100",
  });
  await db.collection("users").doc("bob").set({
    email: "bob@example.com",
    name: null,
    role: "free",
    createdAt: t("2026-08-01T00:00:00Z"),
    lastActiveAt: t("2026-09-15T00:00:00Z"),
    dailyLimits: { questions: 20, coachMessages: { max: 5, resetAt: t("2026-09-16T00:00:00Z") } },
    termsAcceptedVersion: "2026-06-03",
    termsAcceptedAt: t("2026-08-01T00:00:00Z"),
    privacyAcceptedVersion: "2026-06-03",
    privacyAcceptedAt: t("2026-08-01T00:00:00Z"),
  });

  // --- attempts/{uid}/sessions/{id} -------------------------------------
  // attempts/alice and attempts/bob are deliberately never .set() -- only
  // their `sessions` subcollections are written, matching production (see
  // tree.js's note on parent-only documents). This proves the drill covers
  // that exact shape, not just the easy fully-populated-document case.
  await db.collection("attempts").doc("alice").collection("sessions").doc("s1").set({
    questionId: "nyc_q1", correct: true, selectedOption: "Alpha", answeredAt: t("2026-09-01T10:00:00Z"), durationMs: 4200,
  });
  await db.collection("attempts").doc("alice").collection("sessions").doc("s2").set({
    questionId: "nyc_q2", correct: false, selectedOption: "Beta", answeredAt: t("2026-09-01T10:05:00Z"), durationMs: 9100,
  });
  await db.collection("attempts").doc("bob").collection("sessions").doc("s1").set({
    questionId: "ce_q3", correct: true, selectedOption: "Gamma", answeredAt: t("2026-09-15T09:00:00Z"), durationMs: 3000,
  });

  // --- analytics/{uid}/weakTopics/{id} -----------------------------------
  await db.collection("analytics").doc("alice").collection("weakTopics").doc("structural").set({
    topic: "Structural Systems", missCount: 3, lastMissedAt: t("2026-09-01T10:05:00Z"),
  });

  // --- coach_chats/{uid}/threads/{id}/messages/{id} ----------------------
  const thread = db.collection("coach_chats").doc("alice").collection("threads").doc("default");
  await thread.set({ title: "Study help", createdAt: t("2026-09-01T09:00:00Z"), updatedAt: t("2026-09-01T09:05:00Z") });
  await thread.collection("messages").doc("m1").set({
    role: "user", text: "Explain egress width", citations: [], createdAt: t("2026-09-01T09:00:00Z"),
  });
  await thread.collection("messages").doc("m2").set({
    role: "assistant",
    text: "Per IBC 1005, minimum egress width scales with occupant load...",
    citations: [{ source: "IBC 2021", section: "1005.1", page: 112 }],
    createdAt: t("2026-09-01T09:00:30Z"),
  });

  // --- usage/{uid}/daily/{dateKey} ---------------------------------------
  await db.collection("usage").doc("alice").collection("daily").doc("2026-09-16").set({
    questionsAnswered: 12, coachMessages: 3, date: t("2026-09-16T00:00:00Z"),
  });

  // --- subscriptions/{uid} ------------------------------------------------
  await db.collection("subscriptions").doc("alice").set({
    platform: "app_store", status: "active", updatedAt: t("2026-09-01T00:00:00Z"),
  });

  // --- reports/{id} (flat, keyed by a `uid` field, not by doc id) ---------
  await db.collection("reports").doc("r1").set({
    uid: "alice", questionId: "nyc_q1", questionText: "Which code governs egress width?",
    reason: "outdated", comment: "cites a superseded edition", status: "pending", createdAt: t("2026-09-05T00:00:00Z"),
  });

  // --- appleBilling/{namespace}/{kind}/{key} (3 levels deep) --------------
  const ns = db.collection("appleBilling").doc("test-namespace-hash");
  await ns.collection("owners").doc("1000000100").set({ uid: "alice" });
  await ns.collection("accounts").doc("alice").set({ token: "tok-abc-123" });
  await ns.collection("tokens").doc("tok-abc-123").set({ uid: "alice" });
  await ns.collection("transactions").doc("1000000123").set({
    uid: "alice", transactionId: "1000000123", originalTransactionId: "1000000100",
    productId: "are_coach_yearly", revoked: false, signedAt: Date.now() - 60_000, expiresAt: Date.now() + 31_536_000_000,
  });
}

test("the drill: seed -> export -> wipe -> restore -> verify equivalence", async () => {
  await seedSyntheticData();

  const seededSnapshot = await exportAll(db, COVERED_COLLECTIONS, types());
  const seededCount = COVERED_COLLECTIONS.reduce((sum, name) => sum + countExisting(seededSnapshot[name]), 0);
  assert.ok(seededCount > 0, "sanity check: the seed actually wrote something");

  // --- export, via the real CLI ------------------------------------------
  const outDir = mkTmpDir("backup-drill-out-");
  const exportResult = runNode(EXPORT_BIN, ["--project", PROJECT_ID, "--out", outDir]);
  assert.equal(exportResult.status, 0, `export CLI failed:\n${exportResult.stderr}`);

  const archiveName = fs.readdirSync(outDir)[0];
  assert.ok(archiveName, "export CLI did not create an archive directory");
  const archiveDir = path.join(outDir, archiveName);

  const manifest = JSON.parse(fs.readFileSync(path.join(archiveDir, "manifest.json"), "utf8"));
  assert.deepStrictEqual(manifest.collections, COVERED_COLLECTIONS);
  for (const name of COVERED_COLLECTIONS) {
    assert.ok(fs.existsSync(path.join(archiveDir, `${name}.json`)), `missing archive file for ${name}`);
  }

  // --- wipe ----------------------------------------------------------------
  await wipeAllCovered();
  const afterWipe = await exportAll(db, COVERED_COLLECTIONS, types());
  const afterWipeCount = COVERED_COLLECTIONS.reduce((sum, name) => sum + countExisting(afterWipe[name]), 0);
  assert.equal(afterWipeCount, 0, "the emulator was not actually wiped before restore");

  // --- restore, via the real CLI --------------------------------------------
  const restoreResult = runNode(RESTORE_BIN, ["--archive", archiveDir, "--project", PROJECT_ID, "--yes"]);
  assert.equal(restoreResult.status, 0, `restore CLI failed:\n${restoreResult.stderr}`);

  // --- verify: field-for-field equivalence to the ORIGINAL seeded state ----
  const restoredSnapshot = await exportAll(db, COVERED_COLLECTIONS, types());
  assert.deepStrictEqual(
    restoredSnapshot,
    seededSnapshot,
    "restored Firestore state is not field-for-field equivalent to the seeded state"
  );

  const restoredCount = COVERED_COLLECTIONS.reduce((sum, name) => sum + countExisting(restoredSnapshot[name]), 0);
  assert.equal(restoredCount, seededCount, "document count changed across the round trip");

  console.log(`DRILL OK: ${seededCount} document(s) across ${COVERED_COLLECTIONS.length} collections, ` +
    `seeded -> exported -> wiped -> restored -> verified byte-for-byte equal.`);
});

test("restore CLI refuses architect-study-app without --allow-production, and never reaches the network", async () => {
  // No archive is even needed: the guard runs, and must run, before
  // firebase-admin is initialized at all -- so this is safe to point at the
  // real production project id without --emulator-host and without ever
  // touching real Firestore. If this ever DID reach the network, it would
  // hang/fail on missing credentials rather than silently write -- but the
  // assertion below is that it fails fast, for the right, stated reason.
  const fakeArchive = mkTmpDir("backup-drill-unused-archive-");
  const result = runNode(RESTORE_BIN, ["--archive", fakeArchive, "--project", "architect-study-app"]);
  assert.notEqual(result.status, 0, "restore CLI must exit non-zero when refusing a production target");
  assert.match(result.stderr, /Refusing to write to production/);
});
