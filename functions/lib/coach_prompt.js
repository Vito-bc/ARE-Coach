/**
 * The pure, dependency-free half of the Coach prompt: system prompt text and
 * the [Source N] citation-header renderer. Split out of lib/coach.js so it
 * can be unit-tested with node's built-in test runner and NO npm install --
 * lib/coach.js itself pulls in @anthropic-ai/sdk, which only exists once
 * `npm ci` has run, and the "Cloud Functions tests" CI job deliberately runs
 * `node --test` with no install step (see .github/workflows/flutter-ci.yml).
 *
 * Requires nothing beyond node builtins and ./retrieval. Do not add an
 * @anthropic-ai/sdk (or any other npm-installed) dependency to this file.
 */
const { sourceProvenance } = require("./retrieval");

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

// Only appended when passages were actually retrieved -- a prompt with no
// SOURCES block has no [Source N] labels or header blocks for these rules to
// refer to, so applying them to the ungrounded path would tell the model to
// follow instructions about content it was never sent.
const CITATION_LABEL_RULES = `CITATION LABELS AND PROVENANCE
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

const GROUNDED_SYSTEM = `${BASE_SYSTEM}

${CITATION_LABEL_RULES}`;

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
const PROMPT_PROVENANCE_FIELDS = Object.freeze([
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
]);

/** A string that's empty or all whitespace carries no citation information. */
function isBlank(v) {
  return v === undefined || v === null || (typeof v === "string" && v.trim() === "");
}

// A field only counts as present if it has at least one non-blank value --
// [""] or "  " must be omitted exactly like undefined, or the system prompt's
// promise that a missing line means "this information does not exist" breaks.
function hasValue(value) {
  if (Array.isArray(value)) return value.some((v) => !isBlank(v));
  return !isBlank(value);
}

function formatValue(value) {
  if (Array.isArray(value)) return value.filter((v) => !isBlank(v)).join(", ");
  return String(value).trim();
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

module.exports = {
  BASE_SYSTEM,
  CITATION_LABEL_RULES,
  GROUNDED_SYSTEM,
  NO_SOURCES_SYSTEM,
  PROMPT_PROVENANCE_FIELDS,
  isBlank,
  hasValue,
  formatValue,
  labelSources,
  renderSources,
};
