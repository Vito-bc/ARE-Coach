/**
 * BM25 retrieval over the ARE source corpus (NYC codes, ADA, NCARB, ASHRAE...).
 *
 * Lexical, not semantic, and that is the right call here: candidates ask about
 * precise technical terms ("egress width", "occupant load factor", "§1005.3.1"),
 * which is exactly where BM25 beats embeddings -- and it needs no second API
 * provider, no embedding key, and no cold-start model load.
 *
 * The index (coach_index.json) is built by
 * tools/question_audit/src/build_coach_index.py and is git-ignored: it holds
 * extracted source text, which we ground on but do not redistribute.
 */
const fs = require("fs");
const path = require("path");

const K1 = 1.5; // term-frequency saturation
const B = 0.75; // length normalisation
const MIN_SCORE = 10; // below this the "match" is noise, not a source

// Fields kept on the internal passage object used to build the Coach prompt.
// Deliberately broader than PUBLIC_SOURCE_FIELDS below -- everything here is
// filtered again by sourceProvenance() before it can reach an HTTP response,
// so this list is where index-carried provenance (including internal policy
// governance data) is allowed to live for prompt-building or future
// server-side use, without that alone making it public.
const PASSAGE_SOURCE_FIELDS = Object.freeze([
  "source",
  "ref",
  "source_metadata_schema",
  "source_document",
  "source_sha256",
  "source_path",
  "source_page",
  "source_locator",
  "source_chunk_id",
  "source_extraction_version",
  "source_edition",
  "source_revision",
  "source_missing_metadata",
  "source_not_applicable_metadata",
  "source_policy_schema",
  "source_family_id",
  "source_title",
  "source_issuing_authority",
  "source_jurisdictions",
  "source_scope",
  "source_exam_divisions",
  "source_applicability_status",
  "source_applicability_evidence",
  "source_usage_permission_status",
  "source_permitted_uses",
  "source_usage_permission_note",
  "source_policy_profiles",
  "source_policy_decisions",
]);

// The public citation contract for askCoach's HTTP `sources` response. This
// is intentionally a hand-written subset of PASSAGE_SOURCE_FIELDS, not a
// derived one: a field only reaches a paying end user by being listed here
// explicitly, so a future addition to the index row (or to nested content
// under an already-listed key, e.g. source_policy_decisions) never becomes
// public just by existing upstream.
//
// Excluded on purpose -- internal governance/audit data, not citation data:
// source_applicability_status, source_applicability_evidence (owner's
// reviewed evidence/decision reference), source_usage_permission_status,
// source_permitted_uses, source_usage_permission_note (owner's recorded
// permission basis), source_policy_profiles, and source_policy_decisions
// (the full nested policy-decision objects, including internal reasons,
// restrictions and the request that was evaluated). These may still appear
// in the index row, generated candidates, review workbooks, the import
// journal and the Python policy reports -- just never in a Coach HTTP
// response.
const PUBLIC_SOURCE_FIELDS = Object.freeze([
  "source",
  "ref",
  "source_metadata_schema",
  "source_document",
  "source_sha256",
  "source_path",
  "source_page",
  "source_locator",
  "source_chunk_id",
  "source_extraction_version",
  "source_edition",
  "source_revision",
  "source_missing_metadata",
  "source_not_applicable_metadata",
  "source_policy_schema",
  "source_family_id",
  "source_title",
  "source_issuing_authority",
  "source_jurisdictions",
  "source_scope",
  "source_exam_divisions",
]);

function selectFields(value, fields) {
  const selected = {};
  for (const field of fields) {
    if (Object.prototype.hasOwnProperty.call(value, field)) selected[field] = value[field];
  }
  return selected;
}

// Words that carry no retrieval signal in this domain.
const STOP = new Set([
  "the", "a", "an", "of", "for", "to", "in", "on", "at", "is", "are", "be",
  "and", "or", "not", "with", "by", "as", "it", "that", "this", "shall",
  "which", "from", "any", "all", "may", "must", "can", "when", "what", "how",
  "i", "my", "me", "do", "does", "if", "was", "were", "has", "have",
]);

/** "§1005.3.1" -> "1005.3.1"; keeps alphanumerics and dots (section numbers). */
function tokenize(text) {
  return String(text)
    .toLowerCase()
    .replace(/[§#]/g, " ")
    .split(/[^a-z0-9.]+/)
    .map((t) => t.replace(/^\.+|\.+$/g, "")) // strip bare leading/trailing dots
    .filter((t) => t.length > 1 && !STOP.has(t));
}

let INDEX = null;

/** Loads and prepares the index once per container (cold start only). */
function getIndex() {
  if (INDEX) return INDEX;

  const file = path.join(__dirname, "..", "coach_index.json");
  if (!fs.existsSync(file)) {
    // Deployed without an index: the Coach must say so, never invent sections.
    INDEX = prepareIndex([]);
    return INDEX;
  }

  INDEX = prepareIndex(JSON.parse(fs.readFileSync(file, "utf8")));
  return INDEX;
}

/**
 * Turn raw `[{source, ref, text, sections}, ...]` rows into a scored index
 * (term frequencies, document frequencies, average length). Pure — no IO — so
 * tests can build a fixture index without a corpus file on disk.
 */
function prepareIndex(raw) {
  const df = new Map();
  let totalLen = 0;

  const docs = raw.map((r) => {
    const terms = tokenize(`${r.text} ${r.ref}`);
    const tf = new Map();
    for (const t of terms) tf.set(t, (tf.get(t) || 0) + 1);
    for (const t of tf.keys()) df.set(t, (df.get(t) || 0) + 1);
    totalLen += terms.length;
    return { ...r, tf, len: terms.length };
  });

  return { docs, df, n: docs.length, avgLen: docs.length ? totalLen / docs.length : 0 };
}

/**
 * Top-k passages for a question against a prepared index. Returns [] when
 * nothing clears the floor -- the caller MUST then let the Coach answer
 * "I don't have a source for that" rather than guessing. Pure and index-
 * injectable so the retrieval gates can be unit-tested.
 */
function search(idx, query, k = 5) {
  if (!idx || !idx.n) return [];

  const qTerms = tokenize(query);
  if (!qTerms.length) return [];

  const scored = [];
  for (const doc of idx.docs) {
    let score = 0;
    let matched = 0;
    for (const t of qTerms) {
      const f = doc.tf.get(t);
      if (!f) continue;
      matched++;
      const n = idx.df.get(t) || 0;
      // BM25 IDF, floored so a term in almost every doc can't go negative.
      const idf = Math.max(0.01, Math.log(1 + (idx.n - n + 0.5) / (n + 0.5)));
      const norm = f * (K1 + 1);
      const denom = f + K1 * (1 - B + (B * doc.len) / (idx.avgLen || 1));
      score += idf * (norm / denom);
    }
    if (score > 0) scored.push({ doc, score, matched });
  }

  scored.sort((a, b) => b.score - a.score);
  if (!scored.length) return [];

  // Two gates, because an off-topic question ("what's the capital of France?")
  // will still brush against *some* chunk on one incidental word, and handing
  // the model an irrelevant passage labelled "SOURCE" is how bad citations start.
  //
  //   - absolute floor: real ARE questions score 15-25 here; noise scores ~5-7.
  //   - coverage: the best hit must match at least two distinct query terms,
  //     so a single coincidental word can never qualify as a source.
  const top = scored[0];
  const needed = Math.min(2, qTerms.length);
  if (top.score < MIN_SCORE || top.matched < needed) return [];

  const best = top.score;
  return scored
    .filter((s) => s.score >= best * 0.35 && s.matched >= needed)
    .slice(0, k)
    .map((s) => {
      // Only fields needed by the prompt or explicitly approved provenance may
      // leave the prepared index. New index-only fields stay private by default.
      // This is the broader PASSAGE list, not the public one: sourceProvenance()
      // below is the actual HTTP boundary and filters again with the narrower,
      // citation-safe PUBLIC_SOURCE_FIELDS.
      const passage = selectFields(s.doc, [
        ...PASSAGE_SOURCE_FIELDS,
        "text",
        "sections",
      ]);
      return {
        ...passage,
        sections: passage.sections || [],
        score: Number(s.score.toFixed(2)),
      };
    });
}

/**
 * Top-k passages for a question from the deployed corpus index. Thin IO wrapper
 * over `search` so production keeps the same `retrieve(query, k)` call.
 */
function retrieve(query, k = 5) {
  return search(getIndex(), query, k);
}

/**
 * Returns the explicit public source contract for an askCoach HTTP response.
 * Internal policy governance/audit fields (applicability/usage-permission
 * status, permitted uses, permission notes/evidence, policy profiles, and
 * the nested policy-decision objects) are never included, however they are
 * shaped or nested on `passage` -- see PUBLIC_SOURCE_FIELDS above.
 */
function sourceProvenance(passage) {
  return selectFields(passage, PUBLIC_SOURCE_FIELDS);
}

module.exports = { retrieve, tokenize, getIndex, prepareIndex, search, sourceProvenance };
