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

```bash
# put source files (.md/.txt/.pdf) in corpus/ first (see corpus/README.md, SOURCES.md)
python -m src.corpus --query "accessible route width"           # test retrieval (free)
python -m src.generate --grounded --n 40 --repair-attempts 2    # RAG-generate + auto-filter
python -m src.review_generated --output generated_review_YYYYMMDD.xlsx
# architect fills REVIEW: verdict; do not edit candidate content in the workbook
python -m src.merge_accepted --review-book generated_review_YYYYMMDD.xlsx
python -m src.merge_accepted --review-book generated_review_YYYYMMDD.xlsx --apply
```

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
candidate version reports `ALREADY` and creates no duplicate. An exclusive pending
marker rejects an overlapping `--apply`; stale target hashes are refused instead of
overwriting another import.

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
