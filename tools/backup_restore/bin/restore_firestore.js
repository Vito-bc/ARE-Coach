#!/usr/bin/env node
"use strict";

// Loads an archive produced by export_firestore.js into a TARGET project.
// Default target is the local emulator. Writing to the real
// architect-study-app project requires --allow-production AND typing the
// project id back at a prompt -- see src/target_guard.js for the logic and
// docs/BACKUP_RESTORE.md for the runbook.
//
// Usage:
//   node bin/restore_firestore.js --archive <dir> [--project <id>] [--emulator-host host:port] [--allow-production] [--yes]
//
// With no --project, restores into the local emulator as project
// "demo-are-coach" (matching this repo's other emulator tooling).

const fs = require("node:fs");
const path = require("node:path");
const readline = require("node:readline");

const { restoreCollection, countExisting } = require("../src/tree");
const {
  assertTargetAllowed,
  needsTypedConfirmation,
  assertNoAmbientEmulatorHost,
} = require("../src/target_guard");

const DEFAULT_EMULATOR_PROJECT = "demo-are-coach";
const DEFAULT_EMULATOR_HOST = "127.0.0.1:8087";

function parseArgs(argv) {
  const args = { allowProduction: false, yes: false };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === "--archive") args.archive = argv[++i];
    else if (a === "--project") args.project = argv[++i];
    else if (a === "--emulator-host") args.emulatorHost = argv[++i];
    else if (a === "--allow-production") args.allowProduction = true;
    else if (a === "--yes") args.yes = true;
    else throw new Error(`Unknown argument: ${a}`);
  }
  if (!args.archive) throw new Error("--archive <dir> is required.");
  return args;
}

/** No side effects, never throws -- just what assertTargetAllowed needs. */
function resolveProjectId(args) {
  return args.project || DEFAULT_EMULATOR_PROJECT;
}

/**
 * Resolves FIRESTORE_EMULATOR_HOST for this run and returns whether the
 * target is the emulator. Called only AFTER assertTargetAllowed has already
 * cleared the target project id, so this never gets the last word on
 * whether writing to architect-study-app is allowed -- only on whether an
 * ambient env var may be trusted for a target that's already been approved.
 *
 * The emulator (and which one) is used only when THIS run says so, via
 * --emulator-host -- never by whatever FIRESTORE_EMULATOR_HOST happened to
 * already be set in the shell. The one exception is the "no --project"
 * default below: an ambient value that already matches DEFAULT_EMULATOR_HOST
 * isn't a silent inheritance, since it's already what this run would target
 * anyway; anything else still refuses.
 */
function resolveEmulatorTarget(args) {
  const envValue = process.env.FIRESTORE_EMULATOR_HOST;
  if (args.project) {
    assertNoAmbientEmulatorHost({ envValue, explicitFlag: Boolean(args.emulatorHost) });
    if (args.emulatorHost) process.env.FIRESTORE_EMULATOR_HOST = args.emulatorHost;
    return Boolean(process.env.FIRESTORE_EMULATOR_HOST);
  }
  // Default target: the local emulator.
  assertNoAmbientEmulatorHost({
    envValue,
    explicitFlag: Boolean(args.emulatorHost),
    expectedDefault: DEFAULT_EMULATOR_HOST,
  });
  process.env.FIRESTORE_EMULATOR_HOST = args.emulatorHost || envValue || DEFAULT_EMULATOR_HOST;
  return true;
}

function promptLine(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => rl.question(question, (answer) => {
    rl.close();
    resolve(answer);
  }));
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const projectId = resolveProjectId(args);

  // The hard refusal, first and unconditionally: this must not depend on
  // (or be pre-empted by) anything about the emulator/environment below --
  // a production target without --allow-production is refused for that
  // reason, even if the environment also happens to have a stale
  // FIRESTORE_EMULATOR_HOST set.
  assertTargetAllowed({ projectId, allowProduction: args.allowProduction });

  const usingEmulator = resolveEmulatorTarget(args);

  console.log("=".repeat(60));
  console.log(`RESTORE TARGET: ${projectId}${usingEmulator ? ` (emulator @ ${process.env.FIRESTORE_EMULATOR_HOST})` : " (REAL Firestore -- this writes real data)"}`);
  console.log(`Archive: ${path.resolve(args.archive)}`);
  console.log("=".repeat(60));

  if (needsTypedConfirmation({ projectId, yes: args.yes })) {
    const typed = await promptLine(`Type the project id ("${projectId}") to continue, anything else aborts: `);
    if (typed.trim() !== projectId) {
      console.error("Confirmation did not match. Aborting -- nothing was written.");
      process.exitCode = 1;
      return;
    }
  }

  const manifestPath = path.join(args.archive, "manifest.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  console.log(`Archive is from project "${manifest.sourceProject}", exported ${manifest.exportedAt}.`);

  const { initializeApp, cert, applicationDefault } = require("firebase-admin/app");
  const { getFirestore, Timestamp, GeoPoint, DocumentReference } = require("firebase-admin/firestore");

  const appOptions = { projectId };
  if (!usingEmulator) {
    appOptions.credential = process.env.GOOGLE_APPLICATION_CREDENTIALS
      ? cert(process.env.GOOGLE_APPLICATION_CREDENTIALS)
      : applicationDefault();
  }
  const app = initializeApp(appOptions);
  const db = getFirestore(app);
  const types = { Timestamp, GeoPoint, DocumentReference };

  const counts = {};
  for (const name of manifest.collections) {
    const treePath = path.join(args.archive, `${name}.json`);
    const tree = JSON.parse(fs.readFileSync(treePath, "utf8"));
    await restoreCollection(db, db.collection(name), tree, types);
    counts[name] = countExisting(tree);
    console.log(`  ${name}: restored ${counts[name]} document(s)`);
  }

  console.log("Restore complete.");
}

main().catch((err) => {
  console.error(err.stack || String(err));
  process.exitCode = 1;
});
