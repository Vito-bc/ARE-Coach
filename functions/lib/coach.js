/**
 * The AI Coach: Claude, grounded in the ARE source corpus.
 *
 * The failure mode this is built to prevent is a coach that invents code
 * section numbers. A candidate who studies "NYC BC §1005.7" because we made it
 * up will fail the exam and blame us. So:
 *
 *   1. Passages are retrieved from the real corpus (BM25, lib/retrieval.js).
 *   2. Claude may only cite a section that literally appears in those passages.
 *   3. If retrieval finds nothing, Claude is told to say so -- not to guess.
 *
 * There is deliberately NO canned fallback answer. If the model fails, the
 * caller surfaces an honest error. Serving a stock paragraph dressed up as a
 * real answer is worse than showing an outage.
 *
 * The system-prompt text and the [Source N] citation-header renderer live in
 * ./coach_prompt (pure, no npm dependencies) so they can be unit-tested
 * without `npm ci`. This file adds the parts that need the installed
 * @anthropic-ai/sdk: the actual model call and its error mapping.
 */
const Anthropic = require("@anthropic-ai/sdk");
const logger = require("firebase-functions/logger");

const { retrieve } = require("./retrieval");
const { GROUNDED_SYSTEM, NO_SOURCES_SYSTEM, labelSources, renderSources } = require("./coach_prompt");

// Opus 4.8: do NOT send temperature / top_p / top_k / budget_tokens -- all are
// rejected with a 400 on this model.
const MODEL = "claude-opus-4-8";
const MAX_TOKENS = 1500;
const TOP_K = 5;

/**
 * Answers a candidate's question, grounded in the corpus.
 * Throws on failure -- the caller must NOT substitute a canned answer.
 *
 * `deps.client`, if given, replaces the real Anthropic client -- the only
 * hook this module exposes for tests to stub the model call without a
 * network or an API key. Production callers (index.js) never pass it.
 */
async function askCoach(prompt, apiKey, deps = {}) {
  if (!apiKey) {
    const err = new Error("Coach is not configured");
    err.code = "coach_unconfigured";
    throw err;
  }

  const passages = retrieve(prompt, TOP_K);
  const grounded = passages.length > 0;
  const labelledSources = labelSources(passages);

  const userContent = grounded
    ? `SOURCES\n${renderSources(labelledSources)}\n\nCANDIDATE'S QUESTION\n${prompt}`
    : `CANDIDATE'S QUESTION\n${prompt}`;

  const client = deps.client || new Anthropic({ apiKey, maxRetries: 2 });

  let message;
  try {
    message = await client.messages.create({
      model: MODEL,
      max_tokens: MAX_TOKENS,
      system: grounded ? GROUNDED_SYSTEM : NO_SOURCES_SYSTEM,
      messages: [{ role: "user", content: userContent }],
    });
  } catch (e) {
    // Most-specific first. In the TS/JS SDK APIConnectionError extends APIError,
    // so it has to be checked before it.
    let code = "coach_upstream";
    if (e instanceof Anthropic.RateLimitError) code = "coach_rate_limited";
    else if (e instanceof Anthropic.AuthenticationError) code = "coach_unconfigured";
    else if (e instanceof Anthropic.APIConnectionError) code = "coach_unreachable";

    logger.error("coach: model call failed", {
      code,
      status: e.status,
      requestId: e.request_id,
      message: e.message,
    });
    const err = new Error("Coach temporarily unavailable");
    err.code = code;
    throw err;
  }

  if (message.stop_reason === "refusal") {
    const err = new Error("Coach declined to answer this question");
    err.code = "coach_refused";
    throw err;
  }

  const answer = message.content
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("")
    .trim();

  if (!answer) {
    const err = new Error("Coach returned an empty answer");
    err.code = "coach_empty";
    throw err;
  }

  return {
    answer,
    model: MODEL,
    grounded,
    // Same labelled list the prompt was built from, in the same order, so
    // sources[N-1] is always what the model saw as [Source N]. Legacy rows
    // still yield the original {source, ref} shape.
    sources: labelledSources.map((s) => s.provenance),
    inputTokens: message.usage?.input_tokens ?? null,
    outputTokens: message.usage?.output_tokens ?? null,
  };
}

module.exports = { askCoach };
