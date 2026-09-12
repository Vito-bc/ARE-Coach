"use strict";

const { PRODUCT_IDS, RECEIPT_OUTCOME } = require("./receipts");

async function applyReceiptDecision(
  decision,
  { grant, downgrade, now = Date.now() }
) {
  const verifiedShape =
    decision &&
    decision.outcome === RECEIPT_OUTCOME.VERIFIED &&
    decision.valid === true &&
    PRODUCT_IDS.includes(decision.productId) &&
    Number.isSafeInteger(decision.expiresAt) &&
    decision.expiresAt > now;
  if (verifiedShape) {
    await grant(decision);
    return {
      action: "granted",
      status: 200,
      body: {
        valid: true,
        outcome: RECEIPT_OUTCOME.VERIFIED,
        expiresAt: decision.expiresAt,
      },
    };
  }

  const notEntitledShape =
    decision &&
    decision.outcome === RECEIPT_OUTCOME.NOT_ENTITLED &&
    decision.valid === false &&
    decision.retryable === false &&
    typeof decision.reason === "string" &&
    decision.reason !== "";
  if (notEntitledShape) {
    await downgrade(decision);
    return {
      action: "downgraded",
      status: 200,
      body: {
        valid: false,
        outcome: RECEIPT_OUTCOME.NOT_ENTITLED,
        reason: decision.reason,
        // Apple verifyReceipt answers for an account-level receipt, not the
        // exact PurchaseDetails event. The client may unblock repurchase, but
        // cannot safely finish that individual transaction from this response.
        transactionFinalization: "not_safe",
      },
    };
  }

  const knownUnavailable =
    decision && decision.outcome === RECEIPT_OUTCOME.UNAVAILABLE;
  return {
    action: "unavailable",
    status:
      knownUnavailable &&
      Number.isInteger(decision.httpStatus) &&
      decision.httpStatus >= 500 &&
      decision.httpStatus <= 599
        ? decision.httpStatus
        : 502,
    body: {
      error: "Purchase validation is unavailable",
      code: "validation_unavailable",
      retryable: knownUnavailable && decision.retryable === true,
    },
  };
}

module.exports = { applyReceiptDecision };
