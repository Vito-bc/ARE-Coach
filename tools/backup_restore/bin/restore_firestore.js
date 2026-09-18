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
const { assertTargetAllowed, needsTypedConfirmation } = require("../src/target_guard");

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

function resolveTarget(args) {
  if (args.project) {
    if (args.emulatorHost) process.env.FIRESTORE_EMULATOR_HOST = args.emulatorHost;
    return { projectId: args.project, usingEmulator: Boolean(process.env.FIRESTORE_EMULATOR_HOST) };
  }
  // Default target is the local emulator.
  process.env.FIRESTORE_EMULATOR_HOST = args.emulatorHost || process.env.FIRESTORE_EMULATOR_HOST || DEFAULT_EMULATOR_HOST;
  return { projectId: DEFAULT_EMULATOR_PROJECT, usingEmulator: true };
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
  const { projectId, usingEmulator } = resolveTarget(args);

  assertTargetAllowed({ projectId, allowProduction: args.allowProduction });

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
