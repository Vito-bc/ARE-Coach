# ARE Coach — Question-Bank Quality Tool

A Python toolchain that **audits, remediates, and grows** the ARE 5.0 question bank
(`assets/seeds/questions_ny.json`) using LLM evaluation (Claude) + sentence-transformer
embeddings. It runs alongside the Flutter app but is independent of it.

Two kinds of tool, with different rules:

- **Audit / graders** (`validate`, `run_audit`, `run_batch`, `dedupe`, `worklist`) —
  **read-only**: they only score, flag, and report. They never change a question.
- **Remediation / generation** (`fix_positions`, `remove_dups`, `generate`, `merge_accepted`) —
  these **do** modify `questions_ny.json`, but always **back up first** (`backups/`),
  re-validate after, and default to a dry-run. You approve each change.

## Setup

```bash
cd tools/question_audit
python -m venv .venv && source .venv/Scripts/activate     # Windows Git Bash
pip install -r requirements.txt                            # pypdf only needed for PDF corpus
cp .env.example .env                                       # then paste ANTHROPIC_API_KEY
```

The `.env` (your key) is git-ignored. Grading and generation cost API money; a local
result cache (`.cache/`) means re-runs don't re-pay for unchanged questions.

---

## Phase 0 — Audit (find what's weak)

Five graders score each question; a free structural check finds answer-position bias.

| Grader | Flags |
|---|---|
| judgment vs factual | shallow recall (the low-value failure mode) |
| distractor plausibility (1-5) | throwaway wrong options |
| internal consistency | answer ↔ explanation ↔ citation conflicts |
| answer leakage | answerable from the stem alone |
| duplicates (embeddings) | near-duplicate pairs |

```bash
python -m src.validate                     # schema + position-bias (free)
python -m src.run_audit --limit 50         # grade a random sample (live)
python -m src.run_batch                    # full bank via Batch API (~50% cheaper)
python -m src.dedupe --threshold 0.90      # near-duplicate pairs
python -m src.worklist                     # -> reports/maryana_worklist.xlsx (review sheet)
```

**Full-bank result (1,100 questions, $7.60):** 63% factual, 53% weak distractors,
28% leakage-prone, 76 near-duplicate pairs, answer-position skew (38% at position 1).
Output: `reports/audit_1100.csv` (ranked worst-first) and `maryana_worklist.xlsx`
(one Excel sheet with a guide tab + a verdict dropdown for the architect).

---

## Phase 1 — Remediate (fixes that need no domain expertise)

```bash
python -m src.fix_positions --apply        # shuffle options -> even answer positions
python -m src.remove_dups --apply          # drop same-division near-duplicates (keep 1/cluster)
```

Both back up to `backups/` and re-validate. (Content fixes — rewriting factual questions,
improving distractors, verifying citations — need the architect, via `maryana_worklist.xlsx`.)

---

## Phase 2 — Generate (grow the bank with RAG)

Pipeline: **retrieve source chunk → generate a grounded question → 5-grader gate →
distractor-repair → dedup vs bank → explicit human approval of the exact candidate
version.** The automated gate only creates review candidates; it never authorizes import.

### Page-aware provenance and fail-closed source policy

Newly ingested chunks carry `source_metadata_schema=are-coach.corpus-chunk.v1`
alongside the existing `source`, `ref`, and `text` fields. The versioned metadata is:

- `source_document`: deterministic document identity derived from the corpus-relative
  path and SHA-256 of the exact source bytes;
- `source_sha256` and `source_path`: the tagged source hash and POSIX path relative to
  `corpus/`, so equal basenames in different directories do not collide;
- `source_page`: the 1-based physical PDF page, or `null` for MD/TXT;
- `source_locator` and `source_chunk_id`: deterministic location and identity within
  that document and processing version;
- `source_extraction_version`: extractor/chunker version plus `min_len`/`max_len`;
- `source_edition` and `source_revision`: values from explicit metadata only;
- `source_missing_metadata` and `source_not_applicable_metadata`: explicit unknown
  and non-applicable fields.

The chunk identity contract remains `are-coach.corpus-chunk.v1`: adding or editing
policy metadata does not change the source hash, document ID, physical PDF page,
locator, or chunk ID. Source policy is a separate versioned dimension. A governed
chunk carries `source_policy_schema=are-coach.source-policy.v1` plus:

- `source_family_id`, `source_title`, and `source_issuing_authority`;
- explicit `source_jurisdictions`, `source_scope`, and `source_exam_divisions`;
- `source_applicability_status` with owner-supplied evidence;
- `source_usage_permission_status`, `source_permitted_uses`, and an owner note;
- `source_policy_profiles`, which bind the reviewed edition/revision and
  applicability declaration to an explicit target policy.

Applicability and permission are independent. The code does not decide whether a
source is licensed; it enforces the status recorded by the owner. Missing, unknown,
pending, malformed, or mismatched metadata never becomes permission for generation
or indexing. Permission for `human_review` does not imply permission for
`question_generation` or `coach_index`.

PDF pages are extracted and chunked independently. Empty or unextractable pages emit
an `are-coach.corpus-ingestion-diagnostic.v1` diagnostic at their unchanged physical
page number; OCR is not attempted. A physical PDF page is not a printed page number.
Long single paragraphs are split deterministically and never exceed `max_len`.

Explicit version and policy metadata belongs in local
`corpus/source_metadata.json`:

```json
{
  "schema": "are-coach.corpus-source-metadata.v2",
  "sources": {
    "codes/example.pdf": {
      "family_id": "publisher.document-family",
      "title": "Owner-verified document title",
      "issuing_authority": "Owner-verified authority",
      "edition": "2021",
      "revision": "R2",
      "jurisdictions": ["ARE"],
      "scope": "Owner-verified scope and limitations",
      "exam_divisions": ["Practice Management"],
      "applicability_status": "approved",
      "applicability_evidence": "Owner-reviewed evidence or decision reference",
      "usage_permission_status": "approved",
      "permitted_uses": ["human_review", "question_generation"],
      "usage_permission_note": "Owner-recorded permission basis",
      "policy_profiles": ["are-coach.are5-2026.v1"]
    }
  }
}
```

Every v2 entry must contain every documented key. Two different kinds of field
represent "not decided yet", and they are not interchangeable:

- `applicability_status` and `usage_permission_status` are enums whose own
  values include the explicit states `"unknown"` and `"pending"` -- use those
  states, not `null`, to record that a decision has not been made yet.
- Every other field -- `edition`, `revision`, `family_id`, `title`,
  `issuing_authority`, `scope`, `jurisdictions`, `exam_divisions`,
  `permitted_uses`, `policy_profiles` -- is free text or a structured value,
  not a status enum. An unknown value there is recorded as JSON `null`, never
  as the string `"unknown"` or `"pending"`. The loader rejects `edition`,
  `revision`, `family_id`, `title`, `issuing_authority`, or `scope` set to
  exactly (trimmed, case-insensitive) `"unknown"` or `"pending"` with a clean
  `CorpusMetadataError` -- those two words are reserved placeholders that must
  never be mistaken for a real value, and the policy selector independently
  refuses to treat them as known even for a chunk built outside this loader.
  Ordinary prose that merely contains one of those words (e.g. a scope
  description) is unaffected -- only an exact, whole-field match is rejected.
  `applicability_evidence` and `usage_permission_note` are audit prose, not
  identity, and may legitimately discuss why something is still undecided
  (including using the words "unknown"/"pending" in a sentence); they are not
  subject to this placeholder check.

Paths must match the corpus-relative path exactly. Edition, revision, jurisdiction,
applicability, and usage permission are never inferred from a filename. The old
`are-coach.corpus-source-metadata.v1` edition/revision sidecar remains readable for
inventory and review, but it has no policy permission and is ineligible for generation
and indexing. Policy candidates use `are-coach.generated-review.v3`; page-aware v2
and legacy v1 review books keep their existing shapes and never gain inferred policy.

```bash
# put source files (.md/.txt/.pdf) in corpus/ first (see corpus/README.md, SOURCES.md)
python -m src.corpus --query "accessible route width"           # test retrieval (free)
python -m src.generate --grounded --source-policy-profile are-coach.are5-2026.v1 --n 40 --repair-attempts 2
python -m src.review_generated --output generated_review_YYYYMMDD.xlsx
# architect fills REVIEW: verdict; do not edit candidate content in the workbook
python -m src.merge_accepted --review-book generated_review_YYYYMMDD.xlsx
python -m src.merge_accepted --review-book generated_review_YYYYMMDD.xlsx --apply
```

Grounded generation chooses the target division first and then selects only an
eligible chunk for that division, jurisdiction, and policy profile. If any requested
division has no eligible source, it exits with code 2 before loading an embedding
model or creating an API client. There is no fallback to legacy or unverified text.
The exact `are-coach.source-policy-decision.v1` is stored in candidate JSON, shown in
the v3 review workbook, and retained in the provenance journal; distractor repair
cannot replace it.

Coach index construction uses the same policy independently:

```bash
python -m src.build_coach_index \
  --division "Practice Management" \
  --jurisdiction ARE \
  --policy-profile are-coach.are5-2026.v1
# inspect the deterministic dry-run report, then repeat with --apply
```

Dry-run never writes `functions/coach_index.json` or a report file. `--apply` refuses
before writing anything if `--output` and `--report` resolve to the same file
(literally, via a resolved/relative alias, a Windows case-only alias, or a
symlink/hardlink) -- a refusal must never be able to replace an existing index with
the policy report. Given distinct paths, `--apply` writes the deterministic policy
report, but refuses to replace the index if metadata is invalid or no eligible rows
remain; on every refusal path the existing index is left byte-for-byte unchanged.
A successful replacement of either file is atomic (write to a sibling temp file,
then one platform-appropriate rename) so a failed write cannot leave a truncated
index or report behind. Typical machine-readable reasons include
`source_policy_missing`, `usage_permission_missing`, `purpose_not_permitted`,
`applicability_pending`, `jurisdiction_mismatch`, `division_mismatch`,
`policy_profile_mismatch`, `edition_unknown`, `revision_unknown`, `edition_mismatch`,
`revision_mismatch`, and `metadata_field_invalid:<field>`.

This slice does **not** populate or approve the real source manifest, decide legal
rights, declare supersession/equivalence between editions, add provenance to the
Coach prompt or Flutter UI, recover short pages filtered by `min_len`, add OCR, make
an independent external backup, complete Maryana's review, or address payment
release blockers. Those remain explicit owner/recovery tasks.

The gate is strict (judgment, distractor avg ≥3.3 with no throwaway, consistent, no
leakage, not a duplicate). Distractor-repair regenerates only weak distractors instead
of discarding a good question — **yield ~80%, ~$0.07 per accepted question.**

`review_generated` refuses to overwrite an existing workbook. Choose a new `--output`
name for every review snapshot. Each row contains a hidden SHA-256 fingerprint of the
complete candidate record, and the workbook contains a hash of the complete candidate
snapshot. `merge_accepted` also compares the visible question, options, correct answer,
explanation and source cells with that snapshot. A candidate change or a manual content
edit in Excel therefore requires a new workbook and a new human verdict.

Human approval is mandatory even when `--reviewed` is omitted (the old flag is retained
only as a command-line compatibility no-op). Only an exact `Approve` can pass. Blank,
`Reject`, `Needs edit`, invalid verdicts, missing/legacy workbooks, duplicate IDs and
fingerprint mismatches fail closed. Legacy review books have no trustworthy fingerprint
and are not migrated or approved automatically.

Dry-run remains the default and prints `ADD`, `BLOCK` and `ALREADY` decisions without
writing. On `--apply`, the assigned `gen_qN` mapping, reviewed fingerprint, complete
candidate snapshot, `grounded_on`, all available source fields and an explicit list of
missing source fields are written to
`assets/seeds/questions_ny.provenance.json`. This sidecar is outside the Flutter asset
manifest; review it and commit it together with any real bank update. Review notes are
represented by presence and SHA-256, not copied into the journal.

The bank and provenance journal are staged as one recoverable transaction. If either
replacement fails, the pending marker records before/after hashes and the ignored
`backups/generated_import_transactions/` directory retains recovery evidence. Re-run
the same `--apply` command to roll a verified partial transaction forward. Dry-run only
reports a pending transaction and never changes it. Reapplying an already recorded
candidate version reports `ALREADY` and creates no duplicate. An OS lock on the
normalized bank path covers pending inspection, recovery, planning, commit and
cleanup. An overlapping `--apply` exits with code 2 and can be retried after the
owner exits. Windows uses `msvcrt.locking`; Linux uses `fcntl.flock`. The adjacent
`.questions_ny.json.generated-import.lock` file remains on disk: the kernel releases
ownership on close or process termination. Never delete it to clear a lock.

Recovery validates both target states, every prepared after-image still needed,
and bank/journal cross-references before replacing either target. Unknown contents
or damaged staged files stop recovery before any replacement. The manifest stays
immutable; a crash before pending-marker cleanup leaves enough evidence for an
idempotent retry. Error output describes the current pending/verified state, since
recovery may already have written data before a later validation failure.

The lock coordinates cooperating processes on one host using a local filesystem.
It is not a distributed lock for separate machines, cloud-sync replicas, or editors
that bypass this importer. Dry-run does not create/acquire a lock or recover data.
See [recovery regression evidence](../../docs/GENERATED_IMPORT_RECOVERY_EVIDENCE.md)
for fault boundaries, subprocess tests and platform coverage.

⚠️ `corpus/` ships with a tiny **public-fact sample** (ADA, NYC codes) to prove the
pipeline. Replace/expand with real sources for full coverage. Do **not** ingest full
copyrighted texts (AIA contracts, full IBC) — cite them instead.

---

## Layout

```
src/
  schema.py        pydantic Question model + loader (the input gate)
  llm.py           Claude client, JSON-validated grader call, cost tracking
  graders.py       the 5 grader specs (shared by live + batch)
  cache.py  config.py  report.py
  validate.py  run_audit.py  run_batch.py   # audit
  dedupe.py  worklist.py                     # dedup + architect worklist
  fix_positions.py  remove_dups.py           # remediation
  corpus.py  generate.py                       # RAG generation
  generated_approval.py  generated_import.py   # exact-version review + provenance
  review_generated.py  merge_accepted.py       # protected human-review import
tests/              generated-candidate approval/transaction regressions
reports/           generated CSV/JSON/XLSX (git-ignored)
corpus/            source documents for RAG
backups/           question-bank safety copies (git-ignored)
```

## Résumé line

> Built an LLM-evaluation + RAG pipeline (Claude, pydantic, sentence-transformers,
> Anthropic Batch API) to audit a 1,100-question exam bank across 5 quality dimensions —
> flagged 63% factual-recall and 53% weak-distractor for ~$8 — then a grounded
> generation loop with an automated quality gate (~80% yield) to scale the bank.
