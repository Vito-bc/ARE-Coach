"use strict";
const { Worker } = require("node:worker_threads");
const path = require("node:path");
const { revalidateConfiguration } = require("./apple_transactions");

function unavailable(stage) {
  const error = new Error("apple_verification_unavailable");
  error.verificationStage = stage;
  return error;
}

// Library OCSP requests default to 30s. Terminating the worker bounds all
// verification work (including network requests) to 6s, without orphan IO.
function verifyAppleTransaction(jws, config) {
  let checked;
  try {
    checked = revalidateConfiguration(config);
  } catch (_) {
    return Promise.reject(unavailable("configuration"));
  }
  return new Promise((resolve, reject) => {
    const worker = new Worker(path.join(__dirname, "apple_verifier_worker.js"), { workerData: { jws, config: checked } });
    let settled = false;
    const finish = (error, payload, stage = "worker") => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      void worker.terminate();
      error ? reject(unavailable(stage)) : resolve(payload);
    };
    const timer = setTimeout(() => finish(true, undefined, "timeout"), 6000);
    worker.once("message", result => finish(!result.ok, result.payload, result.stage));
    worker.once("error", () => finish(true));
    worker.once("exit", () => finish(true));
  });
}
module.exports = { verifyAppleTransaction };
