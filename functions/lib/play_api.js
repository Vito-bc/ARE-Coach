"use strict";

/**
 * Google Play Developer API access — the IO half of Android receipt validation.
 *
 * Kept separate from `receipts.js` so the decision logic stays pure and
 * testable without a network or a service account (same split as
 * retrieval.js / coach.js).
 *
 * Auth is a service-account JWT. `google-auth-library` is already in the tree
 * as a firebase-admin dependency; it is listed explicitly in package.json
 * because we import it directly, not because it adds anything new to install.
 */

const { JWT } = require("google-auth-library");

const ANDROIDPUBLISHER_SCOPE = "https://www.googleapis.com/auth/androidpublisher";
const API_BASE = "https://androidpublisher.googleapis.com/androidpublisher/v3";

// A Cloud Functions instance serves many requests; minting a fresh JWT per
// request would be a needless round trip. Cached per credential so rotating
// the secret takes effect without a redeploy.
let cachedClient = null;
let cachedClientEmail = null;

function notConfigured(message) {
  const err = new Error(message);
  err.statusCode = 503;
  return err;
}

function getClient(serviceAccountJson) {
  // Both failures below are 503 "not configured", never 4xx: the user's
  // purchase is fine, our server isn't. Answering 4xx here would tell a paying
  // customer their receipt was bad. A placeholder secret of `{}` (used to
  // unblock a deploy before the Play service account exists) lands here too.
  let creds;
  try {
    creds = JSON.parse(serviceAccountJson);
  } catch (_) {
    throw notConfigured("GOOGLE_PLAY_SERVICE_ACCOUNT is not valid JSON");
  }

  if (!creds || !creds.client_email || !creds.private_key) {
    throw notConfigured(
      "GOOGLE_PLAY_SERVICE_ACCOUNT is missing client_email or private_key"
    );
  }

  if (cachedClient && cachedClientEmail === creds.client_email) {
    return cachedClient;
  }

  cachedClient = new JWT({
    email: creds.client_email,
    key: creds.private_key,
    scopes: [ANDROIDPUBLISHER_SCOPE],
  });
  cachedClientEmail = creds.client_email;
  return cachedClient;
}

/**
 * Fetches a subscription purchase from Play.
 *
 * Returns `{ ok: false, reason: "invalid_token" }` rather than throwing when
 * Play says it has never heard of this token: that is a real answer about a
 * real purchase (a forged or already-void token), not an outage. Anything else
 * throws, so a Play outage surfaces as 502 and never as "your receipt is bad".
 *
 * @param {{packageName: string, purchaseToken: string, serviceAccountJson: string}} args
 * @returns {Promise<{ok: true, subscription: object}|{ok: false, reason: string, status: number}>}
 */
async function fetchPlaySubscription({ packageName, purchaseToken, serviceAccountJson }) {
  const client = getClient(serviceAccountJson);
  const url =
    `${API_BASE}/applications/${encodeURIComponent(packageName)}` +
    `/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;

  try {
    const response = await client.request({ url, method: "GET" });
    return { ok: true, subscription: response.data };
  } catch (err) {
    const status = err?.response?.status;
    // 400 = malformed token, 404 = no such purchase, 410 = token no longer
    // valid. All three mean "this is not a purchase we should honour".
    if (status === 400 || status === 404 || status === 410) {
      return { ok: false, reason: "invalid_token", status };
    }
    const wrapped = new Error(
      `Google Play API error: ${status || err?.message || "unknown"}`
    );
    wrapped.statusCode = 502;
    throw wrapped;
  }
}

/** Test seam — drops the cached JWT client. */
function resetClientCache() {
  cachedClient = null;
  cachedClientEmail = null;
}

module.exports = {
  ANDROIDPUBLISHER_SCOPE,
  fetchPlaySubscription,
  resetClientCache,
};
