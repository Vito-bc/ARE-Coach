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
distractor-repair → dedup vs bank.** Only strong items survive; a human reviews a sample.

```bash
# put source files (.md/.txt/.pdf) in corpus/ first (see corpus/README.md)
python -m src.corpus --query "accessible route width"      # test retrieval (free)
python -m src.generate --grounded --n 20                   # RAG-generate + auto-filter
python -m src.merge_accepted --apply                       # append accepted -> bank (after review)
```

The gate is strict (judgment, distractor avg ≥3.3 with no throwaway, consistent, no
leakage, not a duplicate). Distractor-repair regenerates only weak distractors instead
of discarding a good question — **yield ~80%, ~$0.07 per accepted question.**

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
  corpus.py  generate.py  merge_accepted.py  # RAG generation
reports/           generated CSV/JSON/XLSX (git-ignored)
corpus/            source documents for RAG
backups/           question-bank safety copies (git-ignored)
```

## Résumé line

> Built an LLM-evaluation + RAG pipeline (Claude, pydantic, sentence-transformers,
> Anthropic Batch API) to audit a 1,100-question exam bank across 5 quality dimensions —
> flagged 63% factual-recall and 53% weak-distractor for ~$8 — then a grounded
> generation loop with an automated quality gate (~80% yield) to scale the bank.
