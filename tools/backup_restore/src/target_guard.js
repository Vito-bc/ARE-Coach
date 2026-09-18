"use strict";

// The one thing standing between a mistyped restore command and overwriting
// real user data. Kept as plain, dependency-free functions (no Firestore, no
// I/O) so they can be unit-tested directly, without an emulator, and so the
// logic is easy to read in full during an incident.

const PRODUCTION_PROJECT_IDS = new Set(["architect-study-app"]);

/**
 * Throws unless writing to `projectId` is allowed. This is the hard
 * refusal: it cannot be satisfied by --yes or by piping input, only by the
 * operator explicitly passing --allow-production.
 */
function assertTargetAllowed({ projectId, allowProduction }) {
  if (!projectId) {
    throw new Error("A target --project is required.");
  }
  if (PRODUCTION_PROJECT_IDS.has(projectId) && !allowProduction) {
    throw new Error(
      `Refusing to write to production project "${projectId}" without ` +
        "--allow-production. If you really mean to restore into production, " +
        "re-run with --allow-production and confirm the typed prompt."
    );
  }
}

/**
 * Whether the CLI must stop and ask the operator to type the project id
 * back before writing. Production always asks, regardless of --yes -- --yes
 * exists to skip a prompt for routine emulator/drill runs, not to skip the
 * one prompt that exists specifically to catch a wrong production target.
 */
function needsTypedConfirmation({ projectId, yes }) {
  if (PRODUCTION_PROJECT_IDS.has(projectId)) return true;
  return !yes;
}

module.exports = { PRODUCTION_PROJECT_IDS, assertTargetAllowed, needsTypedConfirmation };
