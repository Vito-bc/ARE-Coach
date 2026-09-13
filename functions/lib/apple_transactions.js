"use strict";

// Pure policy: callers supply only payloads returned by SignedDataVerifier.
const { PRODUCT_IDS } = require("./receipts");
const uuid = value => typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
const id = value => typeof value === "string" && /^[1-9][0-9]{0,39}$/.test(value);
const millis = value => Number.isSafeInteger(value) && value > 0;
function unavailable(reason, retryable = false) {
  return { status: 503, body: { outcome: "unavailable", code: reason, retryable,
    transactionFinalization: "not_safe" } };
}
function configuration(env) {
  const { APPLE_BUNDLE_ID: bundleId, APPLE_ENVIRONMENT: environment, APPLE_APP_ID: appId } = env;
  if (typeof bundleId !== "string" || !/^[a-zA-Z0-9.-]{3,200}$/.test(bundleId) ||
      !["Production", "Sandbox"].includes(environment) ||
      typeof appId !== "string" || !/^[1-9][0-9]*$/.test(appId) || !Number.isSafeInteger(Number(appId))) {
    throw new Error("apple_configuration");
  }
  return { bundleId, environment, appAppleId: Number(appId) };
}
function classifyTransaction(payload, request, config, now = Date.now()) {
  if (!payload || typeof payload !== "object" ||
      payload.bundleId !== config.bundleId || payload.environment !== config.environment ||
      !PRODUCT_IDS.includes(payload.productId) || payload.type !== "Auto-Renewable Subscription" ||
      !id(payload.transactionId) || !id(payload.originalTransactionId) ||
      payload.transactionId !== request.transactionId || payload.productId !== request.productId ||
      !millis(payload.expiresDate) || !millis(payload.purchaseDate) ||
      !millis(payload.signedDate) || payload.signedDate > now + 300000 ||
      payload.purchaseDate > payload.signedDate || payload.expiresDate <= payload.purchaseDate ||
      (payload.revocationDate !== undefined && (!millis(payload.revocationDate) || payload.revocationDate > now + 300000)) ||
      (payload.inAppOwnershipType !== "PURCHASED")) {
    return { error: unavailable("apple_transaction_mismatch") };
  }
  if (!uuid(payload.appAccountToken)) return { error: unavailable("apple_ownership_recovery_required") };
  return { transaction: {
    transactionId: payload.transactionId, originalTransactionId: payload.originalTransactionId,
    productId: payload.productId, expiresAt: payload.expiresDate, signedAt: payload.signedDate,
    purchaseAt: payload.purchaseDate, token: payload.appAccountToken.toLowerCase(),
    revoked: payload.revocationDate !== undefined,
    outcome: payload.revocationDate !== undefined || payload.expiresDate <= now ? "not_entitled" : "verified",
  } };
}
async function handleAppleRequest(body, uid, { config, verify, repository, validateLegacy }) {
  try {
    if (body.action === "prepare_apple_purchase") {
      return { status: 200, body: { uid, appAccountToken: await repository.tokenFor(uid),
        environment: config.environment } };
    }
    if (typeof body.receiptData !== "string" || body.receiptData.length > 100000 || !body.receiptData) {
      return unavailable("apple_request_invalid");
    }
    if (body.receiptFormat !== "storekit2_jws") {
      // Legacy receipts cannot prove the per-transaction appAccountToken binding.
      // Never send even a malformed JWS to verifyReceipt; never fall back from JWS.
      if (body.receiptFormat !== "legacy_receipt" || body.receiptData.includes(".")) {
        return unavailable("apple_format_invalid");
      }
      await validateLegacy(body.receiptData);
      return unavailable("apple_ownership_recovery_required");
    }
    if (!id(body.transactionId) || !PRODUCT_IDS.includes(body.productId)) return unavailable("apple_request_invalid");
    const decoded = await verify(body.receiptData);
    const decision = classifyTransaction(decoded, body, config);
    if (decision.error) return decision.error;
    return await repository.apply(uid, decision.transaction);
  } catch (_) {
    // No receipts, token, decoded payloads, credentials or verifier errors in logs.
    return unavailable("apple_validation_unavailable", true);
  }
}
module.exports = { configuration, classifyTransaction, handleAppleRequest, unavailable, uuid };
