"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");

const { prepareIndex, search, sourceProvenance, tokenize } = require("../lib/retrieval");

// A tiny stand-in corpus. Deterministic, so the anti-fabrication gates can be
// asserted exactly without shipping the real 1,503-chunk index into CI.
const CORPUS = [
  {
    source: "nyc_bc_ch10_egress.pdf",
    ref: "1005.3",
    source_metadata_schema: "are-coach.corpus-chunk.v1",
    source_document: "doc:synthetic-egress",
    source_sha256: "sha256:synthetic-egress",
    source_path: "codes/nyc_bc_ch10_egress.pdf",
    source_page: 17,
    source_locator: "pdf-page:17:section:1:piece:1",
    source_chunk_id: "chunk:synthetic-egress-page-17",
    source_extraction_version: "are-coach.pypdf-page-chunker.v1;min_len=80;max_len=1200",
    source_edition: "2022",
    source_revision: null,
    source_missing_metadata: ["source_revision"],
    source_not_applicable_metadata: [],
    source_policy_schema: "are-coach.source-policy.v1",
    source_family_id: "nyc.building-code",
    source_title: "New York City Building Code",
    source_issuing_authority: "NYC Department of Buildings",
    source_jurisdictions: ["NYC"],
    source_scope: "NYC Building Code requirements in the reviewed chapters",
    source_exam_divisions: ["NYC Building Codes"],
    source_applicability_status: "approved",
    source_applicability_evidence: "Synthetic owner-reviewed evidence",
    source_usage_permission_status: "approved",
    source_permitted_uses: ["human_review", "coach_index"],
    source_usage_permission_note: "Synthetic fixture may be indexed",
    source_policy_profiles: ["are-coach.nyc-2026.v1"],
    source_policy_decisions: [
      {
        schema: "are-coach.source-policy-decision.v1",
        outcome: "eligible",
        reasons: [],
      },
    ],
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

test("returned passages preserve versioned source provenance", () => {
  const [top] = search(IDX, "egress stairway capacity per occupant", 1);
  assert.equal(top.source_document, "doc:synthetic-egress");
  assert.equal(top.source_path, "codes/nyc_bc_ch10_egress.pdf");
  assert.equal(top.source_page, 17);
  assert.equal(top.source_chunk_id, "chunk:synthetic-egress-page-17");
  assert.deepEqual(top.source_missing_metadata, ["source_revision"]);
  assert.equal(top.source_policy_schema, "are-coach.source-policy.v1");
  assert.equal(top.source_family_id, "nyc.building-code");
  assert.deepEqual(top.source_jurisdictions, ["NYC"]);
  assert.equal(top.source_scope, "NYC Building Code requirements in the reviewed chapters");
  assert.deepEqual(top.source_permitted_uses, ["human_review", "coach_index"]);
  assert.equal(top.source_policy_decisions[0].outcome, "eligible");
  const publicSource = sourceProvenance(top);
  assert.equal(publicSource.source_chunk_id, "chunk:synthetic-egress-page-17");
  // Citation-safe policy fields are public.
  assert.equal(publicSource.source_policy_schema, "are-coach.source-policy.v1");
  assert.equal(publicSource.source_family_id, "nyc.building-code");
  assert.equal(publicSource.source_title, "New York City Building Code");
  assert.equal(publicSource.source_issuing_authority, "NYC Department of Buildings");
  assert.deepEqual(publicSource.source_jurisdictions, ["NYC"]);
  assert.equal(publicSource.source_scope, "NYC Building Code requirements in the reviewed chapters");
  assert.deepEqual(publicSource.source_exam_divisions, ["NYC Building Codes"]);
  // Internal policy governance/audit fields never reach the public source,
  // even though the internal passage (top) legitimately carries them.
  for (const field of [
    "source_applicability_status",
    "source_applicability_evidence",
    "source_usage_permission_status",
    "source_permitted_uses",
    "source_usage_permission_note",
    "source_policy_profiles",
    "source_policy_decisions",
  ]) {
    assert.ok(field in top, `${field} should still be on the internal passage`);
    assert.ok(!(field in publicSource), `${field} must not enter the HTTP source`);
  }
  assert.ok(!("text" in publicSource));
  assert.ok(!("sections" in publicSource));
  assert.ok(!("score" in publicSource));
});

test("index-only fields cannot escape through passages or public sources", () => {
  const injected = prepareIndex([
    {
      ...CORPUS[0],
      internal_note: "DO NOT PUBLISH",
      raw_page_text: "full copyrighted page text",
      license: "restricted",
    },
    ...filler,
  ]);

  const [top] = search(injected, "egress stairway capacity per occupant", 1);
  const publicSource = sourceProvenance(top);
  for (const field of ["internal_note", "raw_page_text", "license"]) {
    assert.ok(!(field in top), `${field} must not leave the prepared index row`);
    assert.ok(!(field in publicSource), `${field} must not enter the HTTP source`);
  }
  assert.equal(publicSource.source_chunk_id, "chunk:synthetic-egress-page-17");
});

// Adversarial: source_policy_decisions is an allowlisted top-level field, but
// selectFields() copies its value wholesale -- it does not look inside the
// array. This proves internal audit content nested in there (and the whole
// field itself) still never reaches an HTTP response, even though nothing
// filters the nested shape specifically.
test("internal policy audit data -- nested or top-level -- never reaches a public source", () => {
  const adversarial = prepareIndex([
    {
      ...CORPUS[0],
      source_applicability_evidence:
        "Verbal permission from the author's estate pending a written contract; do not distribute publicly",
      source_usage_permission_note:
        "Licensed for internal training use only per vendor legal email dated 2024-06-01; do not republish outside the app",
      source_policy_decisions: [
        {
          schema: "are-coach.source-policy-decision.v1",
          outcome: "eligible",
          reasons: [],
          restrictions: [],
          request: { purpose: "coach_index", target_division: "NYC Building Codes" },
          source_path: "codes/nyc_bc_ch10_egress.pdf",
          // Hypothetical future/nested fields a PolicyDecision.to_dict() (or
          // any other code populating this key) might one day add. Nothing
          // in the allowlist mechanism inspects this shape -- the whole
          // field must simply never be public.
          reviewer_internal_note:
            "Legal flagged this chapter as disputed with the publisher; do not cite externally until settled",
          reviewer_email: "legal-review@internal.are-coach.example",
          vendor_license_terms:
            "Per contract #4521 section 9(b), redistribution outside app UI is prohibited",
        },
      ],
    },
    ...filler,
  ]);

  const [top] = search(adversarial, "egress stairway capacity per occupant", 1);
  const publicSource = sourceProvenance(top);

  // The internal passage legitimately carries this data (for prompt-building
  // or future server-side use) -- the point is it goes no further.
  assert.ok(Array.isArray(top.source_policy_decisions));
  assert.equal(top.source_applicability_evidence.includes("author's estate"), true);

  assert.ok(!("source_policy_decisions" in publicSource), "the whole nested container must not be public");
  assert.ok(!("source_applicability_evidence" in publicSource));
  assert.ok(!("source_usage_permission_note" in publicSource));
  assert.ok(!("source_applicability_status" in publicSource));
  assert.ok(!("source_usage_permission_status" in publicSource));
  assert.ok(!("source_permitted_uses" in publicSource));
  assert.ok(!("source_policy_profiles" in publicSource));

  const serialized = JSON.stringify(publicSource);
  for (const leaked of [
    "reviewer_internal_note",
    "reviewer_email",
    "vendor_license_terms",
    "author's estate",
    "vendor legal email",
    "legal-review@internal.are-coach.example",
    "contract #4521",
  ]) {
    assert.ok(!serialized.includes(leaked), `"${leaked}" must not appear anywhere in the public source`);
  }

  // Citation-safe fields are unaffected by any of the above.
  assert.equal(publicSource.source_title, "New York City Building Code");
  assert.equal(publicSource.source_issuing_authority, "NYC Department of Buildings");
  assert.deepEqual(publicSource.source_jurisdictions, ["NYC"]);
  assert.equal(publicSource.source_scope, "NYC Building Code requirements in the reviewed chapters");
});
