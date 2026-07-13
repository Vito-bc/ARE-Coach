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
    .map((s) => ({
      source: s.doc.source,
      ref: s.doc.ref,
      text: s.doc.text,
      sections: s.doc.sections || [],
      score: Number(s.score.toFixed(2)),
    }));
}

/**
 * Top-k passages for a question from the deployed corpus index. Thin IO wrapper
 * over `search` so production keeps the same `retrieve(query, k)` call.
 */
function retrieve(query, k = 5) {
  return search(getIndex(), query, k);
}

module.exports = { retrieve, tokenize, getIndex, prepareIndex, search };
