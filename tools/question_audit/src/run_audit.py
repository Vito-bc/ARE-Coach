"""STEP 1 — run the graders LIVE and produce reports. COSTS MONEY (Claude calls).

Usage (from tools/question_audit/):
    python -m src.run_audit --limit 50          # random 50-question sample
    python -m src.run_audit --limit all         # full bank (live; see run_batch for cheaper)

Never edits the question bank. For the cheap full run, use run_batch instead.
"""
from __future__ import annotations

import argparse
import random

from src import cache, config, report
from src.graders import GRADER_SPECS
from src.llm import Usage, grade, make_client
from src.schema import Question, load_questions


def load_env() -> None:
    try:
        from dotenv import load_dotenv

        load_dotenv(config.TOOL_DIR / ".env")
    except ImportError:
        pass  # key may already be in the environment


def grade_one(client, model: str, q: Question) -> tuple[dict, Usage]:
    """Run all 4 API graders for one question, using the cache."""
    row: dict = {"id": q.id, "section": q.section, "difficulty": q.difficulty}
    total = Usage()
    for spec in GRADER_SPECS:
        cached = cache.load(spec.name, model, q)
        if cached is not None:
            row[spec.name] = cached
            continue
        parsed, usage = grade(client, model, spec.system, spec.build_payload(q), spec.out_model)
        total += usage
        data = spec.finalize(q, parsed)
        cache.save(spec.name, model, q, data)
        row[spec.name] = data
    return row, total


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", default="50", help="'all' or an integer sample size")
    ap.add_argument("--model", default="claude-opus-4-8")
    ap.add_argument("--seed", type=int, default=config.RANDOM_SEED)
    args = ap.parse_args()

    load_env()
    res = load_questions(config.QUESTIONS_PATH)
    if res.errors:
        print(f"WARNING: {len(res.errors)} malformed questions skipped (fix via validate).")

    questions = res.valid
    if args.limit != "all":
        n = min(int(args.limit), len(questions))
        questions = random.Random(args.seed).sample(questions, n)

    print(f"Grading {len(questions)} questions with {args.model} (live) ...")
    client = make_client()

    rows: list[dict] = []
    total = Usage()
    graded = 0
    for i, q in enumerate(questions, 1):
        row, usage = grade_one(client, args.model, q)
        rows.append(row)
        total += usage
        if usage.input_tokens or usage.output_tokens:
            graded += 1
        print(f"  [{i}/{len(questions)}] {q.id}")

    report.write_and_print(rows, args.model, tag=str(len(rows)))

    cost = total.cost(args.model)
    per = cost / graded if graded else 0
    print("\n" + "-" * 64)
    print(
        f"Newly graded this run: {graded} (rest from cache). "
        f"Tokens in={total.input_tokens:,} out={total.output_tokens:,}\n"
        f"COST this run: ${cost:.2f}  (~${per:.4f}/newly-graded question)"
    )
    if graded:
        print(f"Projected full 1,100 live: ~${per * 1100:.2f}  (Batch API ~50% less)")


if __name__ == "__main__":
    main()
