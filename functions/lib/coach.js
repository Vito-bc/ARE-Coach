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

const { retrieve, sourceProvenance } = require("./retrieval");

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
  every item as one point, pass/fail only.

CITATION LABELS AND PROVENANCE
- Cite using the exact [Source N] labels given in SOURCES (e.g. "[Source 1]").
  Do not renumber, relabel, or invent a source that was not given to you.
- Never state a page number, edition, revision, or issuing authority that is
  not printed in that source's own header block below. The header shows only
  what is actually known for that source -- nothing is hidden from you.
- If a source's header has no page, edition, revision, or authority line, that
  information does not exist for this citation. Do not supply it from memory
  or from what a document like that "usually" says.
- If the SOURCES do not support the answer, say so explicitly and name what is
  missing (e.g. "none of the sources give a page number for this" or "no
  source here covers occupancy classification").`;

const NO_SOURCES_SYSTEM = `${BASE_SYSTEM}

NO SOURCES WERE RETRIEVED for this question. You may still answer general
questions about exam structure, study strategy, or professional practice from
general knowledge -- but you MUST NOT cite any code section, standard number,
table, or specific numeric code requirement. If answering properly would require
one, say that you cannot source it and name the document the candidate should
open.`;

// The prompt's citation header is deliberately built from the SAME
// sourceProvenance()/PUBLIC_SOURCE_FIELDS projection that produces the HTTP
// `sources` array (retrieval.js), never from the raw retrieved passage and
// never from the broader PASSAGE_SOURCE_FIELDS. That makes it structurally
// impossible for an internal governance/audit field (e.g.
// source_applicability_status, source_usage_permission_note,
// source_policy_decisions) to reach the model: those fields never survive
// sourceProvenance() in the first place, so there is nothing to filter out
// here. The prompt is downstream of the public contract, not a parallel path
// that could quietly diverge from it.
//
// Within that already-public projection, only the fields below are
// citation-relevant enough to print in a source header; the rest (e.g.
// source_document, source_sha256, source_chunk_id) stay in the HTTP response
// only. This is a second, explicit allowlist -- not a widening of what's
// public, just a narrowing of what's shown to the model.
const PROMPT_PROVENANCE_FIELDS = [
  ["source", "Document"],
  ["source_title", "Title"],
  ["source_issuing_authority", "Issuing authority"],
  ["source_edition", "Edition"],
  ["source_revision", "Revision"],
  ["source_jurisdictions", "Jurisdiction(s)"],
  ["source_scope", "Scope"],
  ["source_page", "Page"],
  ["source_locator", "Locator"],
  ["ref", "Ref"],
];

function hasValue(value) {
  if (value === undefined || value === null || value === "") return false;
  if (Array.isArray(value) && value.length === 0) return false;
  return true;
}

function formatValue(value) {
  return Array.isArray(value) ? value.join(", ") : String(value);
}

/**
 * Builds the [Source N] label list once, from the public provenance
 * projection, so the prompt and the HTTP `sources` array are guaranteed to
 * agree on both order and content -- the N-th entry here is [Source N] in
 * the prompt AND sources[N-1] in askCoach's return value.
 */
function labelSources(passages) {
  return passages.map((p, i) => ({
    label: i + 1,
    provenance: sourceProvenance(p),
    text: p.text,
  }));
}

/** Renders labelled sources into the prompt, tagged so citations are checkable. */
function renderSources(labelledSources) {
  return labelledSources
    .map(({ label, provenance, text }) => {
      const lines = [`[Source ${label}]`];
      for (const [field, heading] of PROMPT_PROVENANCE_FIELDS) {
        const value = provenance[field];
        if (!hasValue(value)) continue;
        lines.push(`${heading}: ${formatValue(value)}`);
      }
      lines.push("", text);
      return lines.join("\n");
    })
    .join("\n\n");
}

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
    // Same labelled list the prompt was built from, in the same order, so
    // sources[N-1] is always what the model saw as [Source N]. Legacy rows
    // still yield the original {source, ref} shape.
    sources: labelledSources.map((s) => s.provenance),
    inputTokens: message.usage?.input_tokens ?? null,
    outputTokens: message.usage?.output_tokens ?? null,
  };
}

module.exports = { askCoach, renderSources, labelSources };
