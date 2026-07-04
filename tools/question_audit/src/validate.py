"""STEP 0 — schema validation + structural profiling.

Read-only. No Claude calls, no cost. Run this first to confirm the bank is
well-formed and to see the free structural signals (e.g. answer-position bias).

Usage (from tools/question_audit/):
    python -m src.validate
"""
from __future__ import annotations

import collections
import json
from datetime import datetime, timezone

from src import config
from src.schema import load_questions


def main() -> None:
    res = load_questions(config.QUESTIONS_PATH)

    print(f"\nSource: {config.QUESTIONS_PATH}")
    print(f"Loaded: {res.total} questions  |  valid: {len(res.valid)}  |  invalid: {len(res.errors)}")

    if res.errors:
        print("\nMALFORMED ENTRIES (fix these by hand before grading):")
        for e in res.errors[:50]:
            print(f"  - {e['id']}: {e['error']}")
    else:
        print("No malformed entries -- schema is clean.")

    # ── Distribution by division / difficulty ──────────────────────────────
    by_section = collections.Counter(q.section for q in res.valid)
    by_diff = collections.Counter(q.difficulty for q in res.valid)
    print("\nBy section:")
    for s, c in by_section.most_common():
        print(f"  {s:30} {c}")
    print("By difficulty:", dict(by_diff))

    # ── FREE structural signal: answer-position bias ───────────────────────
    # If correct answers cluster on one position, an attentive test-taker can
    # game the pattern. Expected ~25% per position for 4 options.
    pos = collections.Counter(q.correct_index for q in res.valid)
    n = len(res.valid)
    print("\nAnswer-position distribution (expected ~25% each):")
    bias_flag = False
    for p in (1, 2, 3, 4):
        share = pos.get(p, 0) / n * 100 if n else 0
        marker = "  <-- skew" if share >= 30 or share <= 20 else ""
        if marker:
            bias_flag = True
        print(f"  position {p}: {pos.get(p, 0):4}  ({share:5.1f}%){marker}")
    print("Position bias:", "POSSIBLE SKEW -- worth a look" if bias_flag else "looks balanced")

    # ── Write the STEP 0 report artifact ───────────────────────────────────
    config.REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": str(config.QUESTIONS_PATH),
        "total": res.total,
        "valid": len(res.valid),
        "invalid": len(res.errors),
        "errors": res.errors,
        "by_section": dict(by_section),
        "by_difficulty": dict(by_diff),
        "answer_position": {str(p): pos.get(p, 0) for p in (1, 2, 3, 4)},
    }
    out = config.REPORTS_DIR / "step0_schema_report.json"
    out.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"\nReport written: {out}")


if __name__ == "__main__":
    main()
