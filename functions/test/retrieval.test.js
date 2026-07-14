"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");

const { prepareIndex, search, tokenize } = require("../lib/retrieval");

// A tiny stand-in corpus. Deterministic, so the anti-fabrication gates can be
// asserted exactly without shipping the real 1,503-chunk index into CI.
const CORPUS = [
  {
    source: "nyc_bc_ch10_egress.pdf",
    ref: "1005.3",
    sections: ["1005.3", "1005.3.1"],
    text:
      "The capacity, in inches, of means of egress stairways shall be calculated by " +
      "multiplying the occupant load served by that stairway by a means of egress " +
      "capacity factor per occupant. The required width of stairways serving the " +
      "occupant load shall not be less than the minimum width.",
  },
  {
    source: "ada_2010_standards.pdf",
    ref: "403.5.1",
    sections: ["403.5.1", "403.5.2"],
    text:
      "Accessible routes shall have a clear width of 36 inches minimum. The clear " +
      "width of an accessible route may be reduced to 32 inches minimum at a point " +
      "for a maximum depth of 24 inches, such as at a doorway.",
  },
  {
    source: "nyc_zoning_handbook.pdf",
    ref: "FAR",
    sections: [],
    text:
      "Floor area ratio, or FAR, is the ratio of a building's total floor area to the " +
      "area of its zoning lot. Each zoning district has a maximum FAR that limits the " +
      "bulk of buildings in a residential or commercial district.",
  },
  {
    source: "osha_2202_construction.pdf",
    ref: "fall protection",
    sections: [],
    text:
      "Employers must provide fall protection for workers on a construction site at " +
      "elevations of six feet or more above a lower level, using guardrails, safety " +
      "nets, or personal fall arrest systems.",
  },
];

// The gate's absolute score floor (MIN_SCORE) is tuned for a corpus of ~1,500
// chunks. BM25 scores scale with IDF, which depends on corpus size, so a
// 4-document fixture scores far too low to be realistic. Pad with neutral
// filler (vocabulary that never overlaps the test queries) so IDF — and the
// gate — behave the way they do in production, and we test the REAL threshold.
const FILLER_WORDS =
  "committee schedule invoice ledger vendor procurement warranty inspection " +
  "meeting agenda memorandum stakeholder timeline milestone deliverable budget " +
  "estimate proposal contractor subcontractor allowance retainage submittal " +
  "closeout warranty punchlist mobilization insurance surety indemnity";
const pool = FILLER_WORDS.split(" ");
const filler = Array.from({ length: 40 }, (_, i) => ({
  source: `filler_${i}.pdf`,
  ref: `note-${i}`,
  sections: [],
  // rotate a window over the pool so filler docs differ from each other
  text: pool
    .concat(pool)
    .slice(i % pool.length, (i % pool.length) + 12)
    .join(" "),
}));

const IDX = prepareIndex([...CORPUS, ...filler]);

test("prepareIndex computes a usable index", () => {
  const idx = prepareIndex(CORPUS);
  assert.equal(idx.n, CORPUS.length);
  assert.ok(idx.avgLen > 0);
  assert.equal(idx.df.get("egress"), 1); // appears in exactly one CORPUS doc
});

test("tokenizer keeps section numbers and drops stopwords/punctuation", () => {
  const toks = tokenize("What is the required §1005.3 egress width?");
  assert.ok(toks.includes("1005.3"), "section number survives");
  assert.ok(toks.includes("egress"));
  assert.ok(!toks.includes("the"), "stopword dropped");
  assert.ok(!toks.includes("is"));
});

test("an on-topic question retrieves the right passage", () => {
  const r = search(IDX, "required egress width per occupant for stairways", 3);
  assert.ok(r.length >= 1);
  assert.equal(r[0].source, "nyc_bc_ch10_egress.pdf");
  assert.ok(r[0].sections.includes("1005.3"));
});

test("accessible route question retrieves the ADA passage", () => {
  const r = search(IDX, "minimum clear width of an accessible route", 3);
  assert.equal(r[0].source, "ada_2010_standards.pdf");
});

test("FAR question retrieves the zoning passage", () => {
  const r = search(IDX, "what is the maximum FAR in my zoning district", 3);
  assert.equal(r[0].source, "nyc_zoning_handbook.pdf");
});

// The gates are the whole point: an irrelevant passage must never be handed to
// the model wearing a "SOURCE" label, because that is how fabricated citations
// start.
test("GATE: an off-topic question returns no sources", () => {
  for (const q of [
    "what is the capital of France",
    "who won the world cup",
    "recommend a good pizza recipe",
  ]) {
    assert.deepEqual(search(IDX, q, 5), [], `"${q}" must ground to nothing`);
  }
});

test("GATE: a single incidental word match is rejected (2-term coverage)", () => {
  // "width" appears in the corpus, but one lone term must not qualify as a
  // source on its own.
  const r = search(IDX, "width", 5);
  assert.deepEqual(r, []);
});

test("GATE: empty or whitespace query returns nothing", () => {
  assert.deepEqual(search(IDX, "", 5), []);
  assert.deepEqual(search(IDX, "   ", 5), []);
});

test("an empty index never returns a source", () => {
  const empty = prepareIndex([]);
  assert.deepEqual(search(empty, "egress width per occupant", 5), []);
});

test("k limits the number of returned passages", () => {
  const r = search(IDX, "egress width accessible route FAR fall protection", 2);
  assert.ok(r.length <= 2);
});

test("returned passages carry the fields the coach prompt needs", () => {
  const [top] = search(IDX, "egress stairway capacity per occupant", 1);
  assert.ok(top.source && typeof top.text === "string");
  assert.ok(Array.isArray(top.sections));
  assert.equal(typeof top.score, "number");
});
