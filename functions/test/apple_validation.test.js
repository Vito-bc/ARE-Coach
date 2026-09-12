"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");

const { RECEIPT_OUTCOME } = require("../lib/receipts");
const {
  APPLE_PRODUCTION_URL,
  APPLE_REQUEST_TIMEOUT_MS,
  APPLE_SANDBOX_URL,
  callAppleVerify,
  validateAppleReceipt,
} = require("../lib/apple_validation");

const receipt = { status: 0, latest_receipt_info: [] };

test("Apple HTTP calls have a bounded abort timeout", async () => {
  let signal;
  const fetchImpl = async (_url, options) => {
    signal = options.signal;
    return await new Promise((_, reject) => {
      options.signal.addEventListener("abort", () => {
        const error = new Error("aborted");
        error.name = "AbortError";
        reject(error);
      });
    });
  };
  await assert.rejects(
    callAppleVerify("https://apple.example", {}, { fetchImpl, timeoutMs: 5 }),
    { name: "AbortError" },
  );
  assert.equal(signal.aborted, true);
  assert.equal(APPLE_REQUEST_TIMEOUT_MS, 6000);
});

test("Apple non-2xx and malformed JSON responses reject for unavailable handling", async () => {
  await assert.rejects(
    callAppleVerify("https://apple.example", {}, {
      fetchImpl: async () => ({ ok: false, status: 503 }),
    }),
    { statusCode: 502 },
  );
  await assert.rejects(
    callAppleVerify("https://apple.example", {}, {
      fetchImpl: async () => ({
        ok: true,
        json: async () => {
          throw new SyntaxError("bad JSON");
        },
      }),
    }),
    SyntaxError,
  );
});

test("apple validator routes production 21007 to sandbox exactly once", async () => {
  const calls = [];
  const decision = await validateAppleReceipt("receipt", {
    sharedSecret: "secret",
    callApple: async (url) => {
      calls.push(url);
      return calls.length === 1 ? { status: 21007 } : receipt;
    },
  });
  assert.deepEqual(calls, [APPLE_PRODUCTION_URL, APPLE_SANDBOX_URL]);
  assert.equal(decision.outcome, RECEIPT_OUTCOME.NOT_ENTITLED);
});

test("apple validator never loops when sandbox returns another routing status", async () => {
  const calls = [];
  const decision = await validateAppleReceipt("receipt", {
    sharedSecret: "secret",
    callApple: async (url) => {
      calls.push(url);
      return { status: 21007 };
    },
  });
  assert.equal(calls.length, 2);
  assert.equal(decision.outcome, RECEIPT_OUTCOME.UNAVAILABLE);
  assert.equal(decision.reason, "apple_routing_error");
});

test("apple validator does not call Apple without a configured secret", async () => {
  let calls = 0;
  const decision = await validateAppleReceipt("receipt", {
    sharedSecret: "",
    callApple: async () => {
      calls++;
      return receipt;
    },
  });
  assert.equal(calls, 0);
  assert.equal(decision.outcome, RECEIPT_OUTCOME.UNAVAILABLE);
  assert.equal(decision.reason, "apple_not_configured");
  assert.equal(decision.retryable, false);
});

test("transport failure is unavailable and a later retry can recover", async () => {
  let attempts = 0;
  const callApple = async () => {
    attempts++;
    if (attempts === 1) throw new Error("socket closed");
    return receipt;
  };
  const first = await validateAppleReceipt("receipt", {
    sharedSecret: "secret",
    callApple,
  });
  const second = await validateAppleReceipt("receipt", {
    sharedSecret: "secret",
    callApple,
  });
  assert.equal(first.outcome, RECEIPT_OUTCOME.UNAVAILABLE);
  assert.equal(first.retryable, true);
  assert.equal(second.outcome, RECEIPT_OUTCOME.NOT_ENTITLED);
  assert.equal(attempts, 2);
});

test("Apple request timeout is reported as retryable unavailability", async () => {
  const decision = await validateAppleReceipt("receipt", {
    sharedSecret: "secret",
    callApple: async () => {
      const error = new Error("timed out");
      error.name = "AbortError";
      throw error;
    },
  });
  assert.equal(decision.outcome, RECEIPT_OUTCOME.UNAVAILABLE);
  assert.equal(decision.reason, "apple_timeout");
  assert.equal(decision.httpStatus, 504);
  assert.equal(decision.retryable, true);
});
