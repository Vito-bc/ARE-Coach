"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");

const { decideEntitlement } = require("../lib/entitlement");

const NOW = new Date("2026-07-13T12:00:00Z");
const future = new Date("2026-08-13T12:00:00Z");
const past = new Date("2026-06-13T12:00:00Z");

// Firestore hands premiumUntil back as a Timestamp (has .toDate()); make sure
// the decision handles that shape, not just a bare Date.
const ts = (d) => ({ toDate: () => d });

test("role:premium alone is NOT premium — the bug we fixed", () => {
  // A user granted the role once but with no live subscription must not keep
  // access forever.
  const e = decideEntitlement({ role: "premium" }, NOW);
  assert.equal(e.role, "premium");
  assert.equal(e.isPremium, false);
});

test("active subscription with a future premiumUntil is premium", () => {
  const e = decideEntitlement(
    { subscriptionStatus: "active", premiumUntil: ts(future) },
    NOW,
  );
  assert.equal(e.isPremium, true);
});

test("expired subscription is not premium (premiumUntil in the past)", () => {
  const e = decideEntitlement(
    { subscriptionStatus: "active", premiumUntil: ts(past) },
    NOW,
  );
  assert.equal(e.isPremium, false);
});

test("cancelled subscription is not premium even with a future date", () => {
  const e = decideEntitlement(
    { subscriptionStatus: "cancelled", premiumUntil: ts(future) },
    NOW,
  );
  assert.equal(e.isPremium, false);
});

test("role:premium does not rescue an expired subscription", () => {
  // Both signals present but the subscription is dead -> not premium.
  const e = decideEntitlement(
    { role: "premium", subscriptionStatus: "active", premiumUntil: ts(past) },
    NOW,
  );
  assert.equal(e.isPremium, false);
});

test("active status but missing premiumUntil is not premium", () => {
  const e = decideEntitlement({ subscriptionStatus: "active" }, NOW);
  assert.equal(e.isPremium, false);
});

test("empty / missing user doc is free and not premium", () => {
  for (const data of [undefined, null, {}]) {
    const e = decideEntitlement(data, NOW);
    assert.equal(e.role, "free");
    assert.equal(e.isPremium, false);
  }
});

test("status matching is case-insensitive", () => {
  const e = decideEntitlement(
    { subscriptionStatus: "ACTIVE", premiumUntil: ts(future) },
    NOW,
  );
  assert.equal(e.isPremium, true);
});

test("accepts a bare Date for premiumUntil (not only a Timestamp)", () => {
  const e = decideEntitlement(
    { subscriptionStatus: "active", premiumUntil: future },
    NOW,
  );
  assert.equal(e.isPremium, true);
});
