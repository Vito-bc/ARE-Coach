"use strict";
const { Worker } = require("node:worker_threads");
const path = require("node:path");

// Library OCSP requests default to 30s. Terminating the worker bounds all
// verification work (including network requests) to 6s, without orphan IO.
function verifyAppleTransaction(jws, config) {
  return new Promise((resolve, reject) => {
    const worker = new Worker(path.join(__dirname, "apple_verifier_worker.js"), { workerData: { jws, config } });
    let settled = false;
    const finish = (error, payload) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      void worker.terminate();
      error ? reject(new Error("apple_verification_unavailable")) : resolve(payload);
    };
    const timer = setTimeout(() => finish(true), 6000);
    worker.once("message", result => finish(!result.ok, result.payload));
    worker.once("error", () => finish(true));
    worker.once("exit", () => finish(true));
  });
}
module.exports = { verifyAppleTransaction };
