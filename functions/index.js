const { onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
const APPLE_SHARED_SECRET = defineSecret("APPLE_SHARED_SECRET");

const FREE_DAILY_LIMIT = 10;
const PREMIUM_DAILY_LIMIT = 200;
const PER_MINUTE_LIMIT = 3;

const APPLE_PRODUCT_IDS = ["are_coach_monthly", "are_coach_yearly"];
const APPLE_PRODUCTION_URL = "https://buy.itunes.apple.com/verifyReceipt";
const APPLE_SANDBOX_URL = "https://sandbox.itunes.apple.com/verifyReceipt";

exports.askCoach = onRequest(
  {
    region: "us-central1",
    cors: true,
    timeoutSeconds: 60,
    memory: "256MiB",
    secrets: [GEMINI_API_KEY],
  },
  async (req, res) => {
    const startedAt = Date.now();
    if (req.method !== "POST") {
      return sendError(res, 405, "Method not allowed");
    }

    try {
      const uid = await verifyBearerToken(req);
      await verifyAppCheck(req);

      const prompt = String(req.body?.prompt || "").trim();
      if (!prompt) {
        return sendError(res, 400, "Prompt is required");
      }

      const entitlement = await getEntitlement(uid);
      const usage = await enforceUsageLimits(uid, entitlement.isPremium);
      const answerData = await generateCoachAnswer(prompt, GEMINI_API_KEY.value());

      await persistChat(uid, prompt, answerData.answer);

      logger.info("coach_request", {
        uid,
        isPremium: entitlement.isPremium,
        dailyUsed: usage.dailyUsed,
        dailyLimit: usage.dailyLimit,
        minuteUsed: usage.minuteUsed,
        model: answerData.model,
        inputTokens: answerData.inputTokens,
        outputTokens: answerData.outputTokens,
        latencyMs: Date.now() - startedAt,
      });

      return res.status(200).json({
        answer: answerData.answer,
        limit: usage.dailyLimit,
        used: usage.dailyUsed,
        remaining: Math.max(0, usage.dailyLimit - usage.dailyUsed),
      });
    } catch (err) {
      logger.error("askCoach failed", err);
      if (err instanceof HttpsError) {
        return sendError(res, mapHttpsErrorStatus(err.code), err.message);
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
    secrets: [APPLE_SHARED_SECRET],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      return sendError(res, 405, "Method not allowed");
    }

    try {
      const uid = await verifyBearerToken(req);

      const { receiptData, platform } = req.body || {};
      if (!receiptData || typeof receiptData !== "string") {
        return sendError(res, 400, "receiptData is required");
      }
      if (platform !== "ios") {
        return sendError(res, 400, "Only ios platform is supported");
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
  const data = snap.data() || {};

  const role = data.role === "premium" ? "premium" : "free";
  const subscriptionStatus = String(data.subscriptionStatus || "").toLowerCase();
  const premiumUntil = data.premiumUntil?.toDate?.() || null;
  const now = new Date();

  const premiumByRole = role === "premium";
  const premiumBySubscription =
    subscriptionStatus === "active" &&
    premiumUntil instanceof Date &&
    premiumUntil.getTime() > now.getTime();

  return {
    role,
    isPremium: premiumByRole || premiumBySubscription,
  };
}

async function enforceUsageLimits(uid, isPremium) {
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

async function generateCoachAnswer(prompt, apiKey) {
  if (!apiKey) {
    return {
      answer: fallbackAnswer(prompt),
      model: "fallback",
      inputTokens: null,
      outputTokens: null,
    };
  }

  const model = "gemini-1.5-flash";
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              {
                text:
                  "You are an ARE architecture coach. Reply with: Formula, Code Reference, Exam Weight, Common Mistakes. Keep it concise and practical.\n\nQuestion: " +
                  prompt,
              },
            ],
          },
        ],
      }),
    }
  );

  if (!response.ok) {
    logger.warn("Gemini request failed", { status: response.status });
    return {
      answer: fallbackAnswer(prompt),
      model,
      inputTokens: null,
      outputTokens: null,
    };
  }

  const data = await response.json();
  const text =
    data?.candidates?.[0]?.content?.parts?.[0]?.text?.toString().trim() || "";
  const usage = data?.usageMetadata || {};

  return {
    answer: text || fallbackAnswer(prompt),
    model,
    inputTokens: usage.promptTokenCount || null,
    outputTokens: usage.candidatesTokenCount || null,
  };
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

function fallbackAnswer(prompt) {
  return `Formula:\nRequired width = occupant load x egress factor.\n\nCode Reference:\nCheck IBC 2021 Section 1005.3.1 and NYC amendments.\n\nExam Weight:\nUsually 10-15 points in exam-style questions.\n\nCommon Mistakes:\nUsing wrong factor (0.15 vs 0.2), and forgetting minimum clear widths.\n\nYour question was: ${prompt}`;
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
