"use strict";
const { parentPort, workerData } = require("node:worker_threads");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const { SignedDataVerifier } = require("@apple/app-store-server-library");
const { configuration } = require("./apple_transactions");

(async () => {
  try {
    const { jws, config } = workerData;
    // No Xcode/LocalTesting modes, offline switch or caller-supplied trust roots.
    const checked = configuration({ APPLE_BUNDLE_ID: config.bundleId,
      APPLE_ENVIRONMENT: config.environment, APPLE_APP_ID: String(config.appAppleId) });
    const roots = ["AppleIncRootCertificate.cer", "AppleRootCA-G2.cer", "AppleRootCA-G3.cer"]
      .map(name => readFileSync(path.join(__dirname, "../certificates", name)));
    const verifier = new SignedDataVerifier(roots, true, checked.environment, checked.bundleId, checked.appAppleId);
    parentPort.postMessage({ ok: true, payload: await verifier.verifyAndDecodeTransaction(jws) });
  } catch (_) { parentPort.postMessage({ ok: false }); }
})();
