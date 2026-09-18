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

/**
 * The emulator (and which one) is used ONLY when the operator says so for
 * THIS run, via --emulator-host -- never by whatever FIRESTORE_EMULATOR_HOST
 * happened to already be set in the shell. A stale value left over from
 * unrelated local work would otherwise silently misdirect either script:
 * export would silently read the emulator instead of the named real
 * project (false confidence in a backup that's actually empty or stale),
 * and restore would skip setting real credentials and write into whatever
 * is on that stale host -- while still printing "Restore complete."
 *
 * `expectedDefault`, if given, is the one case where an ambient value is
 * tolerated: restore's own "no --project" emulator default. If the ambient
 * value already equals that default exactly, there is nothing being
 * silently inherited -- it already is what this run would target anyway.
 * Any OTHER ambient value (a conflicting one), or any ambient value at all
 * when there is no such fallback (export always names a real --project;
 * restore given an explicit --project), throws.
 */
function assertNoAmbientEmulatorHost({ envValue, explicitFlag, expectedDefault }) {
  if (!envValue || explicitFlag) return;
  if (expectedDefault && envValue === expectedDefault) return;
  throw new Error(
    `FIRESTORE_EMULATOR_HOST is already set in the environment ("${envValue}") ` +
      "and --emulator-host was not passed for this run. Refusing to silently " +
      "inherit it: pass --emulator-host to confirm that target explicitly, or " +
      "unset FIRESTORE_EMULATOR_HOST and re-run."
  );
}

module.exports = {
  PRODUCTION_PROJECT_IDS,
  assertTargetAllowed,
  needsTypedConfirmation,
  assertNoAmbientEmulatorHost,
};
