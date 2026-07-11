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
 */
const Anthropic = require("@anthropic-ai/sdk");
const logger = require("firebase-functions/logger");

const { retrieve } = require("./retrieval");

// Opus 4.8: do NOT send temperature / top_p / top_k / budget_tokens -- all are
// rejected with a 400 on this model.
const MODEL = "claude-opus-4-8";
const MAX_TOKENS = 1500;
const TOP_K = 5;

const BASE_SYSTEM = `You are the ARE Coach: a study assistant for candidates taking the NCARB
Architect Registration Examination (ARE 5.0), many of them practising in New York City.

HOW TO ANSWER
- Lead with the direct answer in one or two sentences.
- Then give the rule, the number, or the procedure that supports it.
- Then one short line on how this is tested and where candidates slip up.
- Plain prose. No preamble, no restating the question, no meta-commentary about
  your own reasoning. Give the final answer only.

SOURCING -- THIS IS THE PART THAT MATTERS
- Cite a code section, standard, or numeric requirement ONLY if it appears
  verbatim in the SOURCES below. Quote the section number exactly as written there.
- You MUST NOT invent, guess, extrapolate, or "recall" a section number,
  table number, or code figure that is not in the SOURCES. A fabricated citation
  is the single worst thing you can do here -- it makes a candidate study
  something that does not exist.
- If the SOURCES do not answer the question, say so plainly, answer only as far
  as you honestly can, and tell the candidate which document to check.
- Never claim an item is worth a particular number of exam points. NCARB scores
  every item as one point, pass/fail only.`;

const NO_SOURCES_SYSTEM = `${BASE_SYSTEM}

NO SOURCES WERE RETRIEVED for this question. You may still answer general
questions about exam structure, study strategy, or professional practice from
general knowledge -- but you MUST NOT cite any code section, standard number,
table, or specific numeric code requirement. If answering properly would require
one, say that you cannot source it and name the document the candidate should
open.`;

/** Renders retrieved passages into the prompt, tagged so citations are checkable. */
function renderSources(passages) {
  return passages
    .map((p, i) => {
      const where = p.ref ? `${p.source} -- ${p.ref}` : p.source;
      return `[${i + 1}] ${where}\n${p.text}`;
    })
    .join("\n\n");
}

/**
 * Answers a candidate's question, grounded in the corpus.
 * Throws on failure -- the caller must NOT substitute a canned answer.
 */
async function askCoach(prompt, apiKey) {
  if (!apiKey) {
    const err = new Error("Coach is not configured");
    err.code = "coach_unconfigured";
    throw err;
  }

  const passages = retrieve(prompt, TOP_K);
  const grounded = passages.length > 0;

  const userContent = grounded
    ? `SOURCES\n${renderSources(passages)}\n\nCANDIDATE'S QUESTION\n${prompt}`
    : `CANDIDATE'S QUESTION\n${prompt}`;

  const client = new Anthropic({ apiKey, maxRetries: 2 });

  let message;
  try {
    message = await client.messages.create({
      model: MODEL,
      max_tokens: MAX_TOKENS,
      system: grounded ? BASE_SYSTEM : NO_SOURCES_SYSTEM,
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
    sources: passages.map((p) => ({ source: p.source, ref: p.ref })),
    inputTokens: message.usage?.input_tokens ?? null,
    outputTokens: message.usage?.output_tokens ?? null,
  };
}

module.exports = { askCoach };
