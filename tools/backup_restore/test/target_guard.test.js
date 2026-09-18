"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { assertTargetAllowed, needsTypedConfirmation, PRODUCTION_PROJECT_IDS } = require("../src/target_guard");

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
