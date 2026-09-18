#!/usr/bin/env node
"use strict";

// Dumps the collections listed in src/collections.js to a local, timestamped,
// deterministic JSON archive. READ-ONLY end to end: it never calls a
// Firestore write method (see src/read_only_db.js, which enforces this at
// the code level, not just via IAM). See docs/BACKUP_RESTORE.md.
//
// Usage:
//   node bin/export_firestore.js --project <projectId> [--out <dir>] [--emulator-host host:port]
//
// The credential used to run this (GOOGLE_APPLICATION_CREDENTIALS, or ADC)
// should hold ONLY roles/datastore.viewer on the source project. That is the
// real safety boundary; the read-only wrapper below is the second one.

const fs = require("node:fs");
const path = require("node:path");

const { COVERED_COLLECTIONS, EXCLUDED_COLLECTIONS } = require("../src/collections");
const { exportCollection, countExisting } = require("../src/tree");
const { makeReadOnlyFirestore } = require("../src/read_only_db");
const { assertNoAmbientEmulatorHost } = require("../src/target_guard");

function parseArgs(argv) {
  const args = { out: "backups" };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === "--project") args.project = argv[++i];
    else if (a === "--out") args.out = argv[++i];
    else if (a === "--emulator-host") args.emulatorHost = argv[++i];
    else throw new Error(`Unknown argument: ${a}`);
  }
  if (!args.project) throw new Error("--project is required (the SOURCE project to read from).");
  return args;
}

function timestampDirName(now) {
  // 2026-09-17T231045Z -- sortable, filesystem-safe on Windows and POSIX.
  return now.toISOString().replace(/[:-]/g, "").replace(/\.\d{3}Z$/, "Z");
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  // The emulator is used only when THIS run says so. A stale
  // FIRESTORE_EMULATOR_HOST left in the shell from unrelated work must
  // never be silently inherited -- it would make this "export from
  // production" invocation quietly read the emulator instead, producing an
  // archive that looks fine but is actually empty or stale.
  assertNoAmbientEmulatorHost({
    envValue: process.env.FIRESTORE_EMULATOR_HOST,
    explicitFlag: Boolean(args.emulatorHost),
  });
  if (args.emulatorHost) process.env.FIRESTORE_EMULATOR_HOST = args.emulatorHost;

  // Deferred so --project/--emulator-host are resolved (and the check
  // above has run) before firebase-admin reads its environment.
  const { initializeApp, cert, applicationDefault } = require("firebase-admin/app");
  const { getFirestore, Timestamp, GeoPoint, DocumentReference } = require("firebase-admin/firestore");

  // Against the emulator, no credential is needed or wanted (it doesn't
  // check auth, and requiring ADC there would break the drill in CI). Real
  // Firestore needs a real credential -- a service account limited to
  // roles/datastore.viewer (see docs/BACKUP_RESTORE.md), never a default
  // wide-open credential.
  const appOptions = { projectId: args.project };
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    appOptions.credential = process.env.GOOGLE_APPLICATION_CREDENTIALS
      ? cert(process.env.GOOGLE_APPLICATION_CREDENTIALS)
      : applicationDefault();
  }
  const app = initializeApp(appOptions);
  const rawDb = getFirestore(app);
  const db = makeReadOnlyFirestore(rawDb);
  const types = { Timestamp, GeoPoint, DocumentReference };

  console.log(`Exporting FROM: ${args.emulatorHost ? `emulator (${args.emulatorHost}), ` : ""}project "${args.project}"`);

  // Read-only sanity check: warn about any real collection this tool does
  // not know about, so a newly added collection doesn't silently go
  // unbacked-up. Never fails the export -- see the task note that CI wiring
  // is out of scope for this slice.
  const actualTopLevel = (await rawDb.listCollections()).map((c) => c.id).sort();
  const known = new Set([...COVERED_COLLECTIONS, ...EXCLUDED_COLLECTIONS.map((c) => c.name)]);
  const warnings = actualTopLevel
    .filter((id) => !known.has(id))
    .map((id) => `Collection "${id}" exists in Firestore but is not covered or explicitly excluded by this tool.`);
  for (const w of warnings) console.warn(`WARNING: ${w}`);

  const now = new Date();
  const archiveDir = path.join(args.out, timestampDirName(now));
  fs.mkdirSync(archiveDir, { recursive: true });

  const counts = {};
  for (const name of COVERED_COLLECTIONS) {
    const tree = await exportCollection(db.collection(name), types);
    fs.writeFileSync(path.join(archiveDir, `${name}.json`), JSON.stringify(tree, null, 2) + "\n", "utf8");
    counts[name] = countExisting(tree);
    console.log(`  ${name}: ${counts[name]} document(s)`);
  }

  const manifest = {
    tool: "are-coach-backup-restore",
    manifestVersion: 1,
    exportedAt: now.toISOString(),
    sourceProject: args.project,
    collections: COVERED_COLLECTIONS,
    excludedCollections: EXCLUDED_COLLECTIONS,
    counts,
    warnings,
  };
  fs.writeFileSync(path.join(archiveDir, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n", "utf8");

  console.log(`Archive written to: ${archiveDir}`);
}

main().catch((err) => {
  console.error(err.stack || String(err));
  process.exitCode = 1;
});
