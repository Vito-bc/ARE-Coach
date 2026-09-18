"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const {
  assertTargetAllowed,
  needsTypedConfirmation,
  assertNoAmbientEmulatorHost,
  PRODUCTION_PROJECT_IDS,
} = require("../src/target_guard");

test("PRODUCTION_PROJECT_IDS names the real project", () => {
  assert.ok(PRODUCTION_PROJECT_IDS.has("architect-study-app"));
});

test("assertTargetAllowed refuses production without --allow-production", () => {
  assert.throws(
    () => assertTargetAllowed({ projectId: "architect-study-app", allowProduction: false }),
    /Refusing to write to production/
  );
});

test("assertTargetAllowed refuses production when allowProduction is undefined", () => {
  assert.throws(
    () => assertTargetAllowed({ projectId: "architect-study-app" }),
    /Refusing to write to production/
  );
});

test("assertTargetAllowed permits production only with the explicit override", () => {
  assert.doesNotThrow(() =>
    assertTargetAllowed({ projectId: "architect-study-app", allowProduction: true })
  );
});

test("assertTargetAllowed permits a non-production project without any override", () => {
  assert.doesNotThrow(() => assertTargetAllowed({ projectId: "demo-are-coach", allowProduction: false }));
  assert.doesNotThrow(() => assertTargetAllowed({ projectId: "some-other-project" }));
});

test("assertTargetAllowed rejects a missing project id even for a non-production target", () => {
  assert.throws(() => assertTargetAllowed({ projectId: undefined }), /--project is required/);
  assert.throws(() => assertTargetAllowed({ projectId: "" }), /--project is required/);
});

test("needsTypedConfirmation is always true for production, even with --yes", () => {
  assert.equal(needsTypedConfirmation({ projectId: "architect-study-app", yes: true }), true);
  assert.equal(needsTypedConfirmation({ projectId: "architect-study-app", yes: false }), true);
});

test("needsTypedConfirmation is skippable via --yes for a non-production target", () => {
  assert.equal(needsTypedConfirmation({ projectId: "demo-are-coach", yes: true }), false);
});

test("needsTypedConfirmation defaults to true (asks) for a non-production target without --yes", () => {
  assert.equal(needsTypedConfirmation({ projectId: "demo-are-coach", yes: false }), true);
  assert.equal(needsTypedConfirmation({ projectId: "demo-are-coach" }), true);
});

test("assertNoAmbientEmulatorHost allows through when nothing is set", () => {
  assert.doesNotThrow(() => assertNoAmbientEmulatorHost({ envValue: undefined, explicitFlag: false }));
  assert.doesNotThrow(() => assertNoAmbientEmulatorHost({ envValue: "", explicitFlag: false }));
});

test("assertNoAmbientEmulatorHost refuses to silently inherit an ambient value with no explicit flag", () => {
  assert.throws(
    () => assertNoAmbientEmulatorHost({ envValue: "203.0.113.5:9999", explicitFlag: false }),
    /FIRESTORE_EMULATOR_HOST is already set/
  );
});

test("assertNoAmbientEmulatorHost's error names the actual variable and value", () => {
  assert.throws(
    () => assertNoAmbientEmulatorHost({ envValue: "203.0.113.5:9999", explicitFlag: false }),
    /203\.0\.113\.5:9999/
  );
});

test("assertNoAmbientEmulatorHost allows an ambient value through when --emulator-host was passed explicitly", () => {
  assert.doesNotThrow(() =>
    assertNoAmbientEmulatorHost({ envValue: "203.0.113.5:9999", explicitFlag: true })
  );
});

test("assertNoAmbientEmulatorHost, with an expectedDefault: tolerates an ambient value that already matches it", () => {
  assert.doesNotThrow(() =>
    assertNoAmbientEmulatorHost({
      envValue: "127.0.0.1:8087",
      explicitFlag: false,
      expectedDefault: "127.0.0.1:8087",
    })
  );
});

test("assertNoAmbientEmulatorHost, with an expectedDefault: still refuses a CONFLICTING ambient value", () => {
  assert.throws(
    () =>
      assertNoAmbientEmulatorHost({
        envValue: "203.0.113.5:9999",
        explicitFlag: false,
        expectedDefault: "127.0.0.1:8087",
      }),
    /FIRESTORE_EMULATOR_HOST is already set/
  );
});

test("assertNoAmbientEmulatorHost never fires when there is no ambient value, expectedDefault or not", () => {
  assert.doesNotThrow(() =>
    assertNoAmbientEmulatorHost({ envValue: undefined, explicitFlag: false, expectedDefault: "127.0.0.1:8087" })
  );
});
