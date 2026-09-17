"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");

// askCoach never calls the network in this suite: every test injects a fake
// Anthropic client via askCoach's `deps.client` hook (see fakeClient below),
// so no API key or network access is ever required.

// A fully-populated, page-aware modern passage (post PR #55/#56 shape).
const MODERN_PASSAGE = {
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
  source_revision: "Local Law 126",
  source_missing_metadata: [],
  source_not_applicable_metadata: [],
  source_policy_schema: "are-coach.source-policy.v1",
  source_family_id: "nyc.building-code",
  source_title: "New York City Building Code",
  source_issuing_authority: "NYC Department of Buildings",
  source_jurisdictions: ["NYC"],
  source_scope: "NYC Building Code requirements in the reviewed chapters",
  source_exam_divisions: ["NYC Building Codes"],
  // Internal governance fields -- must never reach the prompt. The nested
  // object under source_policy_decisions in particular must not leak even
  // though selectFields() copies that field wholesale rather than inspecting
  // its shape.
  source_applicability_status: "approved",
  source_applicability_evidence:
    "Verbal permission from the author's estate pending a written contract; do not distribute publicly",
  source_usage_permission_status: "approved",
  source_permitted_uses: ["human_review", "coach_index"],
  source_usage_permission_note:
    "Licensed for internal training use only per vendor legal email dated 2024-06-01; do not republish outside the app",
  source_policy_profiles: ["are-coach.nyc-2026.v1"],
  source_policy_decisions: [
    {
      schema: "are-coach.source-policy-decision.v1",
      outcome: "eligible",
      reasons: [],
      restrictions: [],
      request: { purpose: "coach_index", target_division: "NYC Building Codes" },
      reviewer_internal_note:
        "Legal flagged this chapter as disputed with the publisher; do not cite externally until settled",
      reviewer_email: "legal-review@internal.are-coach.example",
      vendor_license_terms: "Per contract #4521 section 9(b), redistribution outside app UI is prohibited",
    },
  ],
  sections: ["1005.3", "1005.3.1"],
  text:
    "The capacity, in inches, of means of egress stairways shall be calculated by " +
    "multiplying the occupant load served by that stairway by a means of egress capacity factor.",
};

// A legacy pre-page-aware-ingestion row: only {source, ref, sections, text}.
const LEGACY_PASSAGE = {
  source: "ada_2010_standards.pdf",
  ref: "403.5.1",
  sections: ["403.5.1"],
  text:
    "Accessible routes shall have a clear width of 36 inches minimum, reducible to 32 " +
    "inches minimum at a point for a maximum depth of 24 inches.",
};

/** Builds a fake Anthropic client that records the prompt and returns a canned reply. */
function fakeClient(replyText = "A canned answer.") {
  const calls = [];
  return {
    calls,
    messages: {
      create: async (params) => {
        calls.push(params);
        return {
          stop_reason: "end_turn",
          content: [{ type: "text", text: replyText }],
          usage: { input_tokens: 10, output_tokens: 5 },
        };
      },
    },
  };
}

/** Points lib/retrieval's retrieve() at a fixed passage list for one test. */
function withRetrieval(passages, fn) {
  const retrieval = require("../lib/retrieval");
  const original = retrieval.retrieve;
  // askCoach imports { retrieve } by destructuring at module load, so coach.js
  // holds its own reference -- monkeypatching the export object after the
  // fact does not redirect it. Instead we stub the underlying search the way
  // retrieval.js itself would, by replacing retrieve on the shared module
  // object AND re-requiring coach fresh via the cache so it picks up the
  // stubbed reference.
  delete require.cache[require.resolve("../lib/coach")];
  retrieval.retrieve = () => passages;
  try {
    const fresh = require("../lib/coach");
    return fn(fresh.askCoach);
  } finally {
    retrieval.retrieve = original;
    delete require.cache[require.resolve("../lib/coach")];
  }
}

test("modern passage: prompt renders every present provenance field plus text", async () => {
  await withRetrieval([MODERN_PASSAGE], async (freshAskCoach) => {
    const client = fakeClient();
    const result = await freshAskCoach("required egress width", "fake-api-key", { client });

    assert.equal(client.calls.length, 1);
    const prompt = client.calls[0].messages[0].content;

    assert.match(prompt, /\[Source 1\]/);
    assert.match(prompt, /Document: nyc_bc_ch10_egress\.pdf/);
    assert.match(prompt, /Title: New York City Building Code/);
    assert.match(prompt, /Issuing authority: NYC Department of Buildings/);
    assert.match(prompt, /Edition: 2022/);
    assert.match(prompt, /Revision: Local Law 126/);
    assert.match(prompt, /Jurisdiction\(s\): NYC/);
    assert.match(prompt, /Scope: NYC Building Code requirements in the reviewed chapters/);
    assert.match(prompt, /Page: 17/);
    assert.match(prompt, /Locator: pdf-page:17:section:1:piece:1/);
    assert.match(prompt, /Ref: 1005\.3/);
    assert.match(prompt, /means of egress stairways shall be calculated/);

    assert.equal(result.grounded, true);
    assert.equal(result.sources.length, 1);
    assert.equal(result.sources[0].source_title, "New York City Building Code");
  });
});

test("legacy passage: prompt renders only what the row has, nothing invented", async () => {
  await withRetrieval([LEGACY_PASSAGE], async (freshAskCoach) => {
    const client = fakeClient();
    const result = await freshAskCoach("accessible route clear width", "fake-api-key", { client });

    const prompt = client.calls[0].messages[0].content;
    assert.match(prompt, /\[Source 1\]/);
    assert.match(prompt, /Document: ada_2010_standards\.pdf/);
    assert.match(prompt, /Ref: 403\.5\.1/);
    assert.match(prompt, /clear width of 36 inches minimum/);

    // None of the modern-only fields exist on this row, so none of their
    // labels should appear at all.
    for (const label of ["Title:", "Issuing authority:", "Edition:", "Revision:", "Jurisdiction(s):", "Scope:", "Page:", "Locator:"]) {
      assert.ok(!prompt.includes(label), `legacy prompt must not contain "${label}"`);
    }
    // And certainly no placeholder standing in for the missing fields.
    for (const placeholder of ["unknown", "n/a", "N/A", "null", "undefined"]) {
      assert.ok(
        !prompt.toLowerCase().includes(placeholder.toLowerCase()),
        `legacy prompt must not contain placeholder "${placeholder}"`
      );
    }

    assert.equal(result.sources.length, 1);
    assert.deepEqual(Object.keys(result.sources[0]).sort(), ["ref", "source"]);
  });
});

test("GATE: no internal governance field or nested policy content ever reaches the prompt", async () => {
  await withRetrieval([MODERN_PASSAGE], async (freshAskCoach) => {
    const client = fakeClient();
    await freshAskCoach("required egress width", "fake-api-key", { client });
    const prompt = client.calls[0].messages[0].content;
    const system = client.calls[0].system;
    const fullSent = `${system}\n${prompt}`;

    for (const field of [
      "source_applicability_status",
      "source_applicability_evidence",
      "source_usage_permission_status",
      "source_permitted_uses",
      "source_usage_permission_note",
      "source_policy_profiles",
      "source_policy_decisions",
    ]) {
      assert.ok(!fullSent.includes(field), `${field} name must not appear anywhere sent to the model`);
    }

    // The actual governance VALUES (including the nested policy-decision
    // object's contents) must not leak either, even though the field name
    // filter above would already catch a literal key dump.
    for (const leaked of [
      "approved",
      "author's estate",
      "vendor legal email",
      "reviewer_internal_note",
      "reviewer_email",
      "legal-review@internal.are-coach.example",
      "vendor_license_terms",
      "contract #4521",
      "human_review",
      "coach_index",
      "are-coach.nyc-2026.v1",
    ]) {
      assert.ok(!fullSent.includes(leaked), `"${leaked}" must not appear anywhere sent to the model`);
    }
  });
});

test("label order matches the returned sources order, element-by-element", async () => {
  await withRetrieval([MODERN_PASSAGE, LEGACY_PASSAGE], async (freshAskCoach) => {
    const client = fakeClient();
    const result = await freshAskCoach("egress and accessible routes", "fake-api-key", { client });
    const prompt = client.calls[0].messages[0].content;

    const idx1 = prompt.indexOf("[Source 1]");
    const idx2 = prompt.indexOf("[Source 2]");
    assert.ok(idx1 >= 0 && idx2 > idx1);

    // [Source 1] must be the modern (egress) passage's block, [Source 2] the
    // legacy (ADA) block -- same order retrieve() returned them in.
    const block1 = prompt.slice(idx1, idx2);
    assert.match(block1, /nyc_bc_ch10_egress\.pdf/);

    assert.equal(result.sources.length, 2);
    assert.equal(result.sources[0].source, "nyc_bc_ch10_egress.pdf");
    assert.equal(result.sources[1].source, "ada_2010_standards.pdf");
  });
});

test("mixed legacy + modern passages both render valid, distinct blocks in one query", async () => {
  await withRetrieval([LEGACY_PASSAGE, MODERN_PASSAGE], async (freshAskCoach) => {
    const client = fakeClient();
    const result = await freshAskCoach("egress and accessible routes", "fake-api-key", { client });
    const prompt = client.calls[0].messages[0].content;

    assert.match(prompt, /\[Source 1\][\s\S]*Document: ada_2010_standards\.pdf/);
    assert.match(prompt, /\[Source 2\][\s\S]*Title: New York City Building Code/);
    assert.equal(result.sources[0].source, "ada_2010_standards.pdf");
    assert.equal(result.sources[1].source, "nyc_bc_ch10_egress.pdf");
  });
});

test("zero-passage path uses the no-sources system prompt and returns grounded:false", async () => {
  await withRetrieval([], async (freshAskCoach) => {
    const client = fakeClient();
    const result = await freshAskCoach("what is the capital of France", "fake-api-key", { client });

    const call = client.calls[0];
    assert.match(call.system, /NO SOURCES WERE RETRIEVED/);
    assert.doesNotMatch(call.messages[0].content, /SOURCES/);
    assert.equal(result.grounded, false);
    assert.deepEqual(result.sources, []);
  });
});

test("REGRESSION: the no-sources system prompt never references [Source N] labels or header rules", async () => {
  // Nothing in the ungrounded path ever sends a SOURCES block, so telling the
  // model to trust [Source N] header blocks there is dead instruction that
  // can only confuse it -- it must live only on the grounded system prompt.
  await withRetrieval([], async (freshAskCoach) => {
    const client = fakeClient();
    await freshAskCoach("what is the capital of France", "fake-api-key", { client });
    const system = client.calls[0].system;

    assert.doesNotMatch(system, /\[Source N\]/);
    assert.doesNotMatch(system, /CITATION LABELS AND PROVENANCE/);
  });

  await withRetrieval([MODERN_PASSAGE], async (freshAskCoach) => {
    const client = fakeClient();
    await freshAskCoach("required egress width", "fake-api-key", { client });
    // The grounded path is exactly where these rules belong.
    assert.match(client.calls[0].system, /\[Source N\]/);
    assert.match(client.calls[0].system, /CITATION LABELS AND PROVENANCE/);
  });
});

test("REGRESSION: a blank-string provenance value is omitted, not rendered as a dangling line", async () => {
  const blankJurisdiction = { ...MODERN_PASSAGE, source_jurisdictions: [""] };
  await withRetrieval([blankJurisdiction], async (freshAskCoach) => {
    const client = fakeClient();
    await freshAskCoach("required egress width", "fake-api-key", { client });
    const prompt = client.calls[0].messages[0].content;

    assert.ok(!prompt.includes("Jurisdiction(s):"), "an all-blank array must omit the field entirely");
  });
});
