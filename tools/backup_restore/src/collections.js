"use strict";

// Single source of truth for what this tool backs up. Both export and
// restore import this list rather than each hardcoding their own -- if a
// collection is ever added here, both sides pick it up together.
//
// Every entry is a TOP-LEVEL Firestore collection. Nested data (attempts's
// `sessions`, coach_chats's `threads/{id}/messages`, appleBilling's
// `{namespace}/{kind}/{key}`) is walked recursively by src/tree.js -- it
// does not need its own entry here.
const COVERED_COLLECTIONS = [
  // Account profile: role, entitlement snapshot fields written by the Apple/
  // Play verifiers, and the Terms/Privacy assent record.
  "users",
  // Legacy/secondary per-user subscription record (see functions/index.js
  // deleteAccount, which treats it as its own document tree).
  "subscriptions",
  // Per-user question-attempt history: attempts/{uid}/sessions/{sessionId}.
  "attempts",
  // Per-user weak-topic analytics: analytics/{uid}/weakTopics/{topicId}.
  "analytics",
  // AI Coach chat history: coach_chats/{uid}/threads/{id}/messages/{id}.
  "coach_chats",
  // Daily/minute rate-limit counters: usage/{uid}/daily/{dateKey} (and a
  // `minute` subcollection). Low value on its own, but cheap to keep and
  // walked automatically since subcollections aren't hardcoded by name.
  "usage",
  // User-submitted question-flag reports (stored flat with a `uid` field,
  // not nested under the user -- see functions/index.js deleteReportsByUid).
  "reports",
  // Apple purchase ownership/idempotency ledger: appleBilling/{namespace}/
  // {owners,accounts,tokens,transactions,sandboxEntitlements}/{key}. This is
  // the entitlement source of truth for Apple purchases -- losing it does
  // not just lose history, it can let a re-processed receipt be granted or
  // rejected incorrectly. firestore.rules denies ALL client read/write on
  // this collection (`allow read, write: if false`); this tool reaches it
  // only via the Admin SDK, which always bypasses rules.
  "appleBilling",
];

// Deliberately NOT covered, and why -- see docs/BACKUP_RESTORE.md for the
// operator-facing version of this list.
const EXCLUDED_COLLECTIONS = [
  {
    name: "questions",
    reason:
      "The exam question bank. Already durable and reproducible: it lives " +
      "in git at assets/seeds/questions_ny.json, not only in Firestore.",
  },
];

module.exports = { COVERED_COLLECTIONS, EXCLUDED_COLLECTIONS };
