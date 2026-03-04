const { onRequest } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

const FREE_DAILY_LIMIT = 10;
const PREMIUM_DAILY_LIMIT = 200;

exports.askCoach = onRequest(
  {
    region: "us-central1",
    cors: true,
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (req, res) => {
    if (req.method !== "POST") {
      return res.status(405).json({ error: "Method not allowed" });
    }

    try {
      const uid = await verifyBearerToken(req);
      const prompt = String(req.body?.prompt || "").trim();
      if (!prompt) {
        return res.status(400).json({ error: "Prompt is required" });
      }

      const role = await getUserRole(uid);
      const dailyLimit = role === "premium" ? PREMIUM_DAILY_LIMIT : FREE_DAILY_LIMIT;
      const usageRef = usageDocRef(uid);
      const usageSnap = await usageRef.get();
      const used = Number(usageSnap.data()?.aiMessagesUsed || 0);

      if (used >= dailyLimit) {
        return res.status(429).json({
          error: "Daily AI limit reached",
          limit: dailyLimit,
          used,
          remaining: 0,
        });
      }

      await usageRef.set(
        {
          aiMessagesUsed: admin.firestore.FieldValue.increment(1),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      const answer = await generateCoachAnswer(prompt);

      await db.collection("coach_chats").doc(uid).collection("threads").doc("default").set(
        { updatedAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true }
      );
      await db
        .collection("coach_chats")
        .doc(uid)
        .collection("threads")
        .doc("default")
        .collection("messages")
        .add({
          role: "user",
          text: prompt,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      await db
        .collection("coach_chats")
        .doc(uid)
        .collection("threads")
        .doc("default")
        .collection("messages")
        .add({
          role: "coach",
          text: answer,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

      return res.status(200).json({
        answer,
        limit: dailyLimit,
        used: used + 1,
        remaining: Math.max(0, dailyLimit - used - 1),
      });
    } catch (err) {
      logger.error("askCoach failed", err);
      const code = err.statusCode || 500;
      return res.status(code).json({
        error: err.message || "Internal error",
      });
    }
  }
);

async function verifyBearerToken(req) {
  const authHeader = req.headers.authorization || "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token) {
    const err = new Error("Missing auth token");
    err.statusCode = 401;
    throw err;
  }
  try {
    const decoded = await admin.auth().verifyIdToken(token);
    return decoded.uid;
  } catch (_) {
    const err = new Error("Invalid auth token");
    err.statusCode = 401;
    throw err;
  }
}

async function getUserRole(uid) {
  const userDoc = await db.collection("users").doc(uid).get();
  return userDoc.data()?.role === "premium" ? "premium" : "free";
}

function usageDocRef(uid) {
  const now = new Date();
  const mm = String(now.getMonth() + 1).padStart(2, "0");
  const dd = String(now.getDate()).padStart(2, "0");
  const key = `${now.getFullYear()}_${mm}_${dd}`;
  return db.collection("usage").doc(uid).collection("daily").doc(key);
}

async function generateCoachAnswer(prompt) {
  const apiKey = process.env.GEMINI_API_KEY || "";
  if (!apiKey) {
    return fallbackAnswer(prompt);
  }

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`,
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
    return fallbackAnswer(prompt);
  }

  const data = await response.json();
  const text =
    data?.candidates?.[0]?.content?.parts?.[0]?.text?.toString().trim() || "";
  return text || fallbackAnswer(prompt);
}

function fallbackAnswer(prompt) {
  return `Formula:\nRequired width = occupant load x egress factor.\n\nCode Reference:\nCheck IBC 2021 Section 1005.3.1 and NYC amendments.\n\nExam Weight:\nUsually 10-15 points in exam-style questions.\n\nCommon Mistakes:\nUsing wrong factor (0.15 vs 0.2), and forgetting minimum clear widths.\n\nYour question was: ${prompt}`;
}
