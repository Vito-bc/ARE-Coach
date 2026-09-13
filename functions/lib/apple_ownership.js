"use strict";
const { randomUUID, createHash } = require("node:crypto");
const { unavailable } = require("./apple_transactions");

function createAppleRepository(db, config, Timestamp) {
  const namespace = createHash("sha256").update(`${config.bundleId}:${config.environment}:${config.appAppleId}`).digest("hex");
  const root = db.collection("appleBilling").doc(namespace);
  const ref = (kind, key) => root.collection(kind).doc(key);
  const userRef = uid => config.environment === "Production" ? db.collection("users").doc(uid) : ref("sandboxEntitlements", uid);
  return {
    async tokenFor(uid) {
      return db.runTransaction(async tx => {
        const account = ref("accounts", uid);
        const current = await tx.get(account);
        if (current.exists) return current.data().token;
        const token = randomUUID();
        tx.create(account, { token });
        tx.create(ref("tokens", token), { uid });
        return token;
      });
    },
    async apply(uid, purchase) {
      return db.runTransaction(async tx => {
        const ownerRef = ref("owners", purchase.originalTransactionId);
        const purchaseRef = ref("transactions", purchase.transactionId);
        const entitlementRef = userRef(uid);
        const [token, account, owner, previous, user] = await tx.getAll(
          ref("tokens", purchase.token), ref("accounts", uid), ownerRef, purchaseRef, entitlementRef);
        if (!token.exists || token.data().uid !== uid || !account.exists || account.data().token !== purchase.token ||
            (owner.exists && owner.data().uid !== uid) || (previous.exists && previous.data().uid !== uid)) {
          return unavailable("apple_ownership_recovery_required");
        }
        if (previous.exists && (previous.data().originalTransactionId !== purchase.originalTransactionId ||
            previous.data().productId !== purchase.productId)) return unavailable("apple_transaction_mismatch");
        const revoked = purchase.revoked || (previous.exists && previous.data().revoked === true);
        const now = Date.now();
        const active = !revoked && purchase.expiresAt > now;
        const data = user.data() || {};
        const currentExpiry = data.premiumUntil?.toMillis?.() || 0;
        // Retained expiry is history after revocation, not an active grant.
        // Compare durations only while the current entitlement is still active.
        const currentActive = data.subscriptionStatus === "active" && currentExpiry > now;
        if (!owner.exists) tx.create(ownerRef, { uid });
        const record = { ...purchase, uid, revoked };
        // Replaying identical proof does not rewrite the processing record.
        if (!previous.exists || purchase.signedAt > previous.data().signedAt || (revoked && !previous.data().revoked)) {
          tx.set(purchaseRef, record);
        }
        if (active && (!currentActive || purchase.expiresAt > currentExpiry)) {
          tx.set(entitlementRef, { role: "premium", subscriptionStatus: "active",
            subscriptionPlatform: "app_store", subscriptionId: purchase.productId,
            premiumUntil: Timestamp.fromMillis(purchase.expiresAt), appleTransactionId: purchase.transactionId,
            appleOriginalTransactionId: purchase.originalTransactionId, appleNamespace: namespace,
          }, { merge: true });
        } else if (!active && data.subscriptionPlatform === "app_store" &&
            data.appleNamespace === namespace && data.appleTransactionId === purchase.transactionId &&
            currentExpiry <= purchase.expiresAt) {
          tx.set(entitlementRef, { role: "free", subscriptionStatus: "expired" }, { merge: true });
        }
        return { status: 200, body: { valid: active, outcome: active ? "verified" : "not_entitled",
          uid, transactionId: purchase.transactionId, originalTransactionId: purchase.originalTransactionId,
          productId: purchase.productId, expiresAt: purchase.expiresAt, environment: config.environment,
          entitlementScope: config.environment === "Production" ? "production" : "sandbox",
          transactionFinalization: active ? "verified_transaction" : "not_safe",
          ...(active ? {} : { reason: revoked ? "revoked" : "expired" }),
        } };
      }, { maxAttempts: 5 });
    },
  };
}
module.exports = { createAppleRepository };
