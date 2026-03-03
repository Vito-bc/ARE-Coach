
const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const serviceAccountPath = path.join(__dirname, "..", "serviceAccountKey.json");
if (!fs.existsSync(serviceAccountPath)) {
  throw new Error("serviceAccountKey.json not found in project root.");
}

const serviceAccount = require(serviceAccountPath);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function run() {
  const filePath = path.join(__dirname, "..", "assets", "seeds", "questions_ny.json");
  const raw = fs.readFileSync(filePath, "utf8");
  const questions = JSON.parse(raw);

  const batch = db.batch();
  for (const q of questions) {
    const id = q.id || db.collection("questions").doc().id;
    const ref = db.collection("questions").doc(id);

    batch.set(
      ref,
      {
        state: q.state || "NY",
        section: q.section || "",
        difficulty: q.difficulty || "medium",
        question: q.question || "",
        options: Array.isArray(q.options) ? q.options : [],
        correctOption: q.correctOption || "",
        explanation: q.explanation || "",
        codeReference: q.codeReference || "",
        examWeight: Number(q.examWeight || 0),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }

  await batch.commit();
  console.log(`Imported ${questions.length} question(s) into questions collection.`);
}

run()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
