"""Fix answer-position bias: shuffle each question's options so the correct answer
isn't clustered on one position.

Safe because the app matches the correct answer by TEXT, not index — reordering
options preserves meaning. Skips questions with positional options ("All/None of
the above", "Both A and B", ...) which must stay last. Backs up before writing.

Usage (from tools/question_audit/):
    python -m src.fix_positions            # dry-run (writes nothing)
    python -m src.fix_positions --apply    # back up + rewrite the bank
"""
from __future__ import annotations

import argparse
import json
import random
import shutil
from collections import Counter
from datetime import datetime

from src import config

# If any option contains these, leave the question's order untouched.
_POSITIONAL = ("above", "all of", "none of", "both ", "neither", "a and b", "i and ii", "answers")


def _positional(options: list[str]) -> bool:
    return any(any(p in o.lower() for p in _POSITIONAL) for o in options)


def _pos_counts(items: list[dict]) -> Counter:
    c: Counter = Counter()
    for q in items:
        c[q["options"].index(q["correctOption"]) + 1] += 1
    return c


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="write the change (default: dry-run)")
    ap.add_argument("--seed", type=int, default=config.RANDOM_SEED)
    args = ap.parse_args()

    data = json.loads(config.QUESTIONS_PATH.read_text(encoding="utf-8-sig"))
    rng = random.Random(args.seed)
    n = len(data)

    before = _pos_counts(data)
    shuffled = skipped = 0
    for q in data:
        opts = q["options"]
        if _positional(opts):
            skipped += 1
            continue
        order = opts[:]
        rng.shuffle(order)
        if order != opts:
            q["options"] = order
            shuffled += 1
    after = _pos_counts(data)

    def show(label: str, c: Counter) -> None:
        cells = "  ".join(f"pos{p}={c.get(p, 0)} ({c.get(p, 0) * 100 // n}%)" for p in (1, 2, 3, 4))
        print(f"  {label}: {cells}")

    print(f"Questions: {n} | shuffled: {shuffled} | skipped (positional options): {skipped}")
    show("BEFORE", before)
    show("AFTER ", after)

    # Integrity: nothing lost, correct answer still present, option SET unchanged.
    assert len(data) == n
    for q in data:
        assert q["correctOption"] in q["options"], q["id"]
    print("Integrity OK: count unchanged, every correctOption still present in its options.")

    if args.apply:
        backups = config.TOOL_DIR / "backups"
        backups.mkdir(exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        bak = backups / f"questions_ny_{ts}.json"
        shutil.copy2(config.QUESTIONS_PATH, bak)
        config.QUESTIONS_PATH.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(f"\nBACKED UP original -> backups/{bak.name}")
        print("WROTE shuffled bank. Restore anytime by copying the backup back.")
    else:
        print("\nDRY-RUN — nothing written. Re-run with --apply to write (a backup is made first).")


if __name__ == "__main__":
    main()
