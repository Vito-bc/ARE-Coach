"use strict";

// Exercises the real askCoach() (lib/coach.js), which requires
// @anthropic-ai/sdk -- so this file only runs after `npm ci`, in the
// apple-integration CI job, never in the dependency-free "Cloud Functions
// tests" job (see .github/workflows/flutter-ci.yml). The Anthropic client
// itself is stubbed via askCoach's `deps.client` hook: no network, no real
// LLM, no API key. Everything else about the prompt (field rendering,
// governance-field exclusion, blank-value omission) is covered without any
// npm dependency in functions/test/coach.test.js against lib/coach_prompt.js.
const { test } = require("node:test");
const assert = require("node:assert/strict");

const { askCoach } = require("../lib/coach");
const retrieval = require("../lib/retrieval");

const MODERN_PASSAGE = {
  source: "nyc_bc_ch10_egress.pdf",
  ref: "1005.3",
  source_title: "New York City Building Code",
  source_page: 17,
  text: "The capacity, in inches, of means of egress stairways shall be calculated by multiplying the occupant load.",
};

const LEGACY_PASSAGE = {
  source: "ada_2010_standards.pdf",
  ref: "403.5.1",
  text: "Accessible routes shall have a clear width of 36 inches minimum.",
};

/** Builds a fake Anthropic client that records the call and returns a canned reply. */
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

/**
 * Points lib/retrieval's retrieve() at a fixed passage list for one call.
 * askCoach imports { retrieve } by destructuring at module load, so
 * lib/coach.js holds its own reference to the original function --
 * overwriting retrieval.retrieve after the fact doesn't redirect it. Instead
 * this stubs the export on the shared retrieval module object and clears
 * lib/coach.js from the require cache so the next require re-destructures
 * against the now-stubbed reference.
 */
async function withRetrieval(passages, fn) {
  const original = retrieval.retrieve;
  delete require.cache[require.resolve("../lib/coach")];
  retrieval.retrieve = () => passages;
  try {
    const fresh = require("../lib/coach");
    return await fn(fresh.askCoach);
  } finally {
    retrieval.retrieve = original;
    delete require.cache[require.resolve("../lib/coach")];
  }
}

test("label order matches the RETURNED sources array, element-by-element", async () => {
  await withRetrieval([MODERN_PASSAGE, LEGACY_PASSAGE], async (freshAskCoach) => {
    const client = fakeClient();
    const result = await freshAskCoach("egress and accessible routes", "fake-api-key", { client });
    const prompt = client.calls[0].messages[0].content;

    const idx1 = prompt.indexOf("[Source 1]");
    const idx2 = prompt.indexOf("[Source 2]");
    assert.ok(idx1 >= 0 && idx2 > idx1);
    const block1 = prompt.slice(idx1, idx2);
    assert.match(block1, /nyc_bc_ch10_egress\.pdf/);

    assert.equal(result.sources.length, 2);
    assert.equal(result.sources[0].source, "nyc_bc_ch10_egress.pdf");
    assert.equal(result.sources[1].source, "ada_2010_standards.pdf");
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
