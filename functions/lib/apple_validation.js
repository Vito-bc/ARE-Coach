"use strict";

const { decideAppleReceipt, unavailable } = require("./receipts");

const APPLE_PRODUCTION_URL = "https://buy.itunes.apple.com/verifyReceipt";
const APPLE_SANDBOX_URL = "https://sandbox.itunes.apple.com/verifyReceipt";
// At most two calls (production, then sandbox) fit inside the client's
// 15-second validation bound, leaving time for auth and response handling.
const APPLE_REQUEST_TIMEOUT_MS = 6000;

async function callAppleVerify(
  url,
  payload,
  { fetchImpl = fetch, timeoutMs = APPLE_REQUEST_TIMEOUT_MS } = {}
) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchImpl(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
    if (!response.ok) {
      const error = new Error(`Apple API error: ${response.status}`);
      error.statusCode = 502;
      throw error;
    }
    return await response.json();
  } finally {
    clearTimeout(timeout);
  }
}

async function validateAppleReceipt(
  receiptData,
  {
    sharedSecret,
    callApple = (url, payload) => callAppleVerify(url, payload),
  }
) {
  if (typeof sharedSecret !== "string" || sharedSecret.trim() === "") {
    return unavailable("apple_not_configured", {
      retryable: false,
      httpStatus: 503,
    });
  }
  const payload = {
    "receipt-data": receiptData,
    password: sharedSecret,
    "exclude-old-transactions": true,
  };

  try {
    const production = await callApple(APPLE_PRODUCTION_URL, payload);
    if (
      production &&
      typeof production === "object" &&
      !Array.isArray(production) &&
      production.status === 21007
    ) {
      const sandbox = await callApple(APPLE_SANDBOX_URL, payload);
      if (
        sandbox &&
        typeof sandbox === "object" &&
        !Array.isArray(sandbox) &&
        (sandbox.status === 21007 || sandbox.status === 21008)
      ) {
        return unavailable("apple_routing_error", {
          retryable: false,
          httpStatus: 502,
        });
      }
      return decideAppleReceipt(sandbox);
    }
    return decideAppleReceipt(production);
  } catch (error) {
    return unavailable(
      error && error.name === "AbortError"
        ? "apple_timeout"
        : "apple_transport_error",
      {
        retryable: true,
        httpStatus: error && error.name === "AbortError" ? 504 : 502,
      }
    );
  }
}

module.exports = {
  APPLE_PRODUCTION_URL,
  APPLE_SANDBOX_URL,
  APPLE_REQUEST_TIMEOUT_MS,
  callAppleVerify,
  validateAppleReceipt,
};
