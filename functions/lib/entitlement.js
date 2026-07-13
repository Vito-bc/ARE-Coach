/**
 * Decide a user's entitlement from their Firestore user document.
 *
 * Pure and side-effect free so the money-critical rule can be unit-tested.
 * The rule that matters: entitlement is the LIVE SUBSCRIPTION, never the `role`
 * field. `role: "premium"` once meant permanent access that survived
 * cancellation, expiry and refund — a paying-customer bug in reverse. `role`
 * is a label; only an active subscription with a future `premiumUntil` is proof
 * of payment.
 *
 * @param {object|null|undefined} data  the user doc (`snap.data()`)
 * @param {Date} [now]                  injectable clock for tests
 * @returns {{ role: "premium"|"free", isPremium: boolean }}
 */
function decideEntitlement(data, now = new Date()) {
  data = data || {};

  const role = data.role === "premium" ? "premium" : "free";
  const status = String(data.subscriptionStatus || "").toLowerCase();

  // Firestore stores this as a Timestamp (has .toDate()); tests may pass a Date.
  const raw = data.premiumUntil;
  const premiumUntil =
    raw && typeof raw.toDate === "function"
      ? raw.toDate()
      : raw instanceof Date
        ? raw
        : null;

  const isPremium =
    status === "active" &&
    premiumUntil instanceof Date &&
    premiumUntil.getTime() > now.getTime();

  return { role, isPremium };
}

module.exports = { decideEntitlement };
