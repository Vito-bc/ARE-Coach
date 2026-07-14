const { onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

const { askCoach: generateCoachAnswer } = require("./lib/coach");
const { decideEntitlement } = require("./lib/entitlement");

admin.initializeApp();
const db = admin.firestore();

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
const APPLE_SHARED_SECRET = defineSecret("APPLE_SHARED_SECRET");

const FREE_DAILY_LIMIT = 10;
const PREMIUM_DAILY_LIMIT = 200;
const PER_MINUTE_LIMIT = 3;

// Bounds the prompt so a pathological input can't blow up the token bill.
const MAX_PROMPT_CHARS = 2000;

const APPLE_PRODUCT_IDS = ["are_coach_monthly", "are_coach_yearly"];
const APPLE_PRODUCTION_URL = "https://buy.itunes.apple.com/verifyReceipt";
const APPLE_SANDBOX_URL = "https://sandbox.itunes.apple.com/verifyReceipt";

exports.askCoach = onRequest(
  {
    region: "us-central1",
    cors: true,
    // Grounded generation reads the corpus index at cold start and Claude can
    // take a while on a hard question, so give it room.
    timeoutSeconds: 120,
    memory: "512MiB",
    maxInstances: 10,
    secrets: [ANTHROPIC_API_KEY],
  },
  async (req, res) => {
    const startedAt = Date.now();
    if (req.method !== "POST") {
      return sendError(res, 405, "Method not allowed");
    }

    const prompt = String(req.body?.prompt || "").trim();
    let reserved = null;

    try {
      const uid = await verifyBearerToken(req);
      await verifyAppCheck(req);

      if (!prompt) {
        return sendError(res, 400, "Prompt is required");
      }
      if (prompt.length > MAX_PROMPT_CHARS) {
        return sendError(res, 400, `Question is too long (max ${MAX_PROMPT_CHARS} characters)`);
      }

      const entitlement = await getEntitlement(uid);

      // Reserve the quota slot up front so concurrent requests can't overrun the
      // limit, then refund it if the model never produced an answer. The user is
      // only ever charged for a request that actually answered.
      const usage = await reserveUsage(uid, entitlement.isPremium);
      reserved = { uid, usage };

      const answerData = await generateCoachAnswer(prompt, ANTHROPIC_API_KEY.value());
      reserved = null; // answered -- the reservation is now a real charge

      await persistChat(uid, prompt, answerData.answer);

      logger.info("coach_request", {
        uid,
        isPremium: entitlement.isPremium,
        dailyUsed: usage.dailyUsed,
        dailyLimit: usage.dailyLimit,
        minuteUsed: usage.minuteUsed,
        model: answerData.model,
        grounded: answerData.grounded,
        sources: answerData.sources.map((s) => s.ref || s.source),
        inputTokens: answerData.inputTokens,
        outputTokens: answerData.outputTokens,
        latencyMs: Date.now() - startedAt,
      });

      return res.status(200).json({
        answer: answerData.answer,
        grounded: answerData.grounded,
        sources: answerData.sources,
        limit: usage.dailyLimit,
        used: usage.dailyUsed,
        remaining: Math.max(0, usage.dailyLimit - usage.dailyUsed),
      });
    } catch (err) {
      // The question was never answered, so don't make the user pay for it.
      if (reserved) await refundUsage(reserved.uid).catch(() => {});

      logger.error("askCoach failed", err);
      if (err instanceof HttpsError) {
        return sendError(res, mapHttpsErrorStatus(err.code), err.message);
      }
      if (err.code && String(err.code).startsWith("coach_")) {
        // Be honest: the Coach is down. Never dress a failure up as an answer.
        const status = err.code === "coach_rate_limited" ? 429 : 503;
        return sendError(res, status, err.message || "Coach temporarily unavailable");
      }
      return sendError(res, err.statusCode || 500, err.message || "Internal error");
    }
  }
);

exports.validateReceipt = onRequest(
  {
    region: "us-central1",
    cors: true,
    timeoutSeconds: 30,
    memory: "256MiB",
    maxInstances: 10,
    secrets: [APPLE_SHARED_SECRET],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      return sendError(res, 405, "Method not allowed");
    }

    try {
      const uid = await verifyBearerToken(req);
      await verifyAppCheck(req);

      const { receiptData, platform } = req.body || {};
      if (!receiptData || typeof receiptData !== "string") {
        return sendError(res, 400, "receiptData is required");
      }
      if (platform !== "ios" && platform !== "app_store") {
        return sendError(res, 400, "Only iOS/App Store platform is supported");
      }

      const appleResult = await callAppleVerify(APPLE_PRODUCTION_URL, {
        "receipt-data": receiptData,
        password: APPLE_SHARED_SECRET.value(),
        "exclude-old-transactions": true,
      });

      const appleData = appleResult.status === 21007
        ? await callAppleVerify(APPLE_SANDBOX_URL, {
            "receipt-data": receiptData,
            password: APPLE_SHARED_SECRET.value(),
            "exclude-old-transactions": true,
          })
        : appleResult;

      if (appleData.status !== 0) {
        await markUserFree(uid);
        logger.warn("validateReceipt: invalid receipt", { uid, appleStatus: appleData.status });
        return res.status(200).json({ valid: false });
      }

      const now = Date.now();
      const transactions = (appleData.latest_receipt_info || [])
        .filter(
          (t) =>
            APPLE_PRODUCT_IDS.includes(t.product_id) &&
            Number(t.expires_date_ms) > now
        )
        .sort((a, b) => Number(b.expires_date_ms) - Number(a.expires_date_ms));

      if (transactions.length === 0) {
        await markUserFree(uid);
        logger.info("validateReceipt: subscription expired", { uid });
        return res.status(200).json({ valid: false });
      }

      const latest = transactions[0];
      const expiresAt = Number(latest.expires_date_ms);

      await db.collection("users").doc(uid).set(
        {
          role: "premium",
          subscriptionStatus: "active",
          subscriptionId: latest.product_id,
          premiumUntil: admin.firestore.Timestamp.fromMillis(expiresAt),
          lastActiveAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      logger.info("validateReceipt: subscription activated", {
        uid,
        productId: latest.product_id,
        expiresAt,
      });

      return res.status(200).json({ valid: true, expiresAt });
    } catch (err) {
      logger.error("validateReceipt failed", err);
      if (err instanceof HttpsError) {
        return sendError(res, mapHttpsErrorStatus(err.code), err.message);
      }
      return sendError(res, err.statusCode || 500, err.message || "Internal error");
    }
  }
);

exports.deleteAccount = onRequest(
  {
    region: "us-central1",
    cors: true,
    timeoutSeconds: 120,
    memory: "256MiB",
    maxInstances: 5,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      return sendError(res, 405, "Method not allowed");
    }

    try {
      // The account to delete is always the authenticated caller's own uid,
      // derived from a verified, fresh ID token — a user can never delete
      // another account. App Check confirms the request is from the real app.
      const uid = await verifyBearerToken(req);
      await verifyAppCheck(req);

      // 1. Delete every per-user document tree (doc + all nested subcollections).
      //    recursiveDelete is a no-op on a path that doesn't exist, so this is
      //    safe even for users with partial data.
      const userTrees = [
        db.collection("users").doc(uid),
        db.collection("subscriptions").doc(uid),
        db.collection("attempts").doc(uid),
        db.collection("analytics").doc(uid),
        db.collection("coach_chats").doc(uid),
        db.collection("usage").doc(uid),
      ];
      for (const ref of userTrees) {
        await db.recursiveDelete(ref);
      }

      // 2. Delete the user's question reports (stored flat with a uid field).
      await deleteReportsByUid(uid);

      // 3. Delete the Firebase Auth user last, once their data is gone.
      await admin.auth().deleteUser(uid);

      logger.info("account_deleted", { uid });
      return res.status(200).json({ deleted: true });
    } catch (err) {
      logger.error("deleteAccount failed", err);
      if (err instanceof HttpsError) {
        return sendError(res, mapHttpsErrorStatus(err.code), err.message);
      }
      return sendError(res, err.statusCode || 500, err.message || "Internal error");
    }
  }
);

async function deleteReportsByUid(uid) {
  const snap = await db.collection("reports").where("uid", "==", uid).get();
  if (snap.empty) return;
  const docs = snap.docs;
  // Commit in chunks of 500 to respect the Firestore batch limit.
  for (let i = 0; i < docs.length; i += 500) {
    const batch = db.batch();
    for (const d of docs.slice(i, i + 500)) {
      batch.delete(d.ref);
    }
    await batch.commit();
  }
}

async function callAppleVerify(url, payload) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    const err = new Error(`Apple API error: ${response.status}`);
    err.statusCode = 502;
    throw err;
  }
  return response.json();
}

async function markUserFree(uid) {
  try {
    await db.collection("users").doc(uid).set(
      {
        role: "free",
        subscriptionStatus: "expired",
        lastActiveAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  } catch (_) {}
}

async function verifyBearerToken(req) {
  const authHeader = req.headers.authorization || "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token) {
    throw new HttpsError("unauthenticated", "Missing auth token");
  }
  try {
    const decoded = await admin.auth().verifyIdToken(token);
    return decoded.uid;
  } catch (_) {
    throw new HttpsError("unauthenticated", "Invalid auth token");
  }
}

async function verifyAppCheck(req) {
  const appCheckToken = req.headers["x-firebase-appcheck"];
  if (!appCheckToken || typeof appCheckToken !== "string") {
    throw new HttpsError("unauthenticated", "App Check token required");
  }
  try {
    await admin.appCheck().verifyToken(appCheckToken);
  } catch (_) {
    throw new HttpsError("unauthenticated", "App Check failed");
  }
}

async function getEntitlement(uid) {
  const snap = await db.collection("users").doc(uid).get();
  // The decision (subscription, never role) lives in lib/entitlement.js so it
  // can be unit-tested without Firestore. See that file for the rationale.
  return decideEntitlement(snap.data());
}

/**
 * Claims one request against the user's quota.
 *
 * Claiming BEFORE the model call is what keeps concurrent requests from
 * overrunning the limit. If the model then fails, `refundUsage` gives the slot
 * back -- so a user is never charged for a question that went unanswered.
 */
async function reserveUsage(uid, isPremium) {
  const dailyLimit = isPremium ? PREMIUM_DAILY_LIMIT : FREE_DAILY_LIMIT;
  const dailyRef = usageDailyDocRef(uid);
  const minuteRef = usageMinuteDocRef(uid);

  const usage = await db.runTransaction(async (tx) => {
    const dailySnap = await tx.get(dailyRef);
    const minuteSnap = await tx.get(minuteRef);

    const dailyUsed = Number(dailySnap.data()?.aiMessagesUsed || 0);
    const minuteUsed = Number(minuteSnap.data()?.aiMessagesUsed || 0);

    if (dailyUsed >= dailyLimit) {
      throw new HttpsError("resource-exhausted", "Daily quota exceeded");
    }
    if (minuteUsed >= PER_MINUTE_LIMIT) {
      throw new HttpsError("resource-exhausted", "Slow down (per-minute limit reached)");
    }

    tx.set(
      dailyRef,
      {
        aiMessagesUsed: dailyUsed + 1,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    tx.set(
      minuteRef,
      {
        aiMessagesUsed: minuteUsed + 1,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 1000 * 60 * 60)),
      },
      { merge: true }
    );

    return {
      dailyUsed: dailyUsed + 1,
      minuteUsed: minuteUsed + 1,
      dailyLimit,
    };
  });

  return usage;
}

/** Hands back a reserved slot after a request that never produced an answer. */
async function refundUsage(uid) {
  const dec = admin.firestore.FieldValue.increment(-1);
  await Promise.all([
    usageDailyDocRef(uid).set({ aiMessagesUsed: dec }, { merge: true }),
    usageMinuteDocRef(uid).set({ aiMessagesUsed: dec }, { merge: true }),
  ]);
}

async function persistChat(uid, prompt, answer) {
  const threadRef = db.collection("coach_chats").doc(uid).collection("threads").doc("default");
  await threadRef.set({ updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
  await threadRef.collection("messages").add({
    role: "user",
    text: prompt,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await threadRef.collection("messages").add({
    role: "coach",
    text: answer,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

function usageDailyDocRef(uid) {
  const now = new Date();
  const mm = String(now.getMonth() + 1).padStart(2, "0");
  const dd = String(now.getDate()).padStart(2, "0");
  const key = `${now.getFullYear()}_${mm}_${dd}`;
  return db.collection("usage").doc(uid).collection("daily").doc(key);
}

function usageMinuteDocRef(uid) {
  const now = new Date();
  const yyyy = now.getFullYear();
  const mm = String(now.getMonth() + 1).padStart(2, "0");
  const dd = String(now.getDate()).padStart(2, "0");
  const hh = String(now.getHours()).padStart(2, "0");
  const min = String(now.getMinutes()).padStart(2, "0");
  const minuteKey = `${yyyy}${mm}${dd}_${hh}${min}`;
  return db.collection("usage").doc(uid).collection("minute").doc(minuteKey);
}

function mapHttpsErrorStatus(code) {
  if (code === "unauthenticated") return 401;
  if (code === "permission-denied") return 403;
  if (code === "resource-exhausted") return 429;
  if (code === "invalid-argument") return 400;
  return 500;
}

function sendError(res, status, message) {
  return res.status(status).json({ error: message });
}
