"""Grader 5 — duplicate / near-duplicate detection (bank-wide, NO API cost).

Embeds every question with sentence-transformers and flags pairs above a cosine
similarity threshold, so you can merge or drop near-duplicates by hand. Prints a
pair-count-per-threshold table so you can tune the cut. Never edits the bank.

Usage (from tools/question_audit/):
    python -m src.dedupe                  # default threshold 0.85
    python -m src.dedupe --threshold 0.90
"""
from __future__ import annotations

import argparse
import csv

from src import config
from src.schema import load_questions


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--threshold", type=float, default=0.85, help="cosine similarity cut (0-1)")
    ap.add_argument("--model", default="all-MiniLM-L6-v2", help="sentence-transformers model")
    args = ap.parse_args()

    import numpy as np
    from sentence_transformers import SentenceTransformer

    qs = load_questions(config.QUESTIONS_PATH).valid
    print(f"Embedding {len(qs)} questions with {args.model} ...")
    model = SentenceTransformer(args.model)
    emb = model.encode(
        [q.question for q in qs],
        normalize_embeddings=True,
        show_progress_bar=True,
        batch_size=64,
    )
    sims = emb @ emb.T  # cosine (embeddings are normalized)
    n = len(qs)

    # Distribution across thresholds — lets you tune the cut sensibly.
    upper = sims[np.triu_indices(n, 1)]
    print("\nPair-count at thresholds (tune --threshold from here):")
    for t in (0.80, 0.85, 0.90, 0.95, 0.98, 1.00):
        print(f"  >= {t:.2f}:  {int((upper >= t).sum())} pairs")

    pairs = []
    for i in range(n):
        row = sims[i]
        for j in range(i + 1, n):
            s = float(row[j])
            if s >= args.threshold:
                pairs.append((qs[i], qs[j], s))
    pairs.sort(key=lambda x: -x[2])
    print(f"\nFound {len(pairs)} pairs >= {args.threshold}")

    config.REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    tag = f"{args.threshold:.2f}".replace(".", "")
    csv_path = config.REPORTS_DIR / f"duplicates_{tag}.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(
            ["id_a", "id_b", "similarity", "section_a", "section_b", "question_a", "question_b"]
        )
        for a, b, s in pairs:
            w.writerow([a.id, b.id, round(s, 3), a.section, b.section, a.question, b.question])

    print(f"\nTop 10 most-similar pairs:")
    for a, b, s in pairs[:10]:
        cross = "" if a.section == b.section else "  [cross-division]"
        print(f"  {s:.3f}  {a.id} ~ {b.id}{cross}")
        print(f"        A: {a.question[:75]}")
        print(f"        B: {b.question[:75]}")
    print(f"\nWritten: {csv_path.name}")


if __name__ == "__main__":
    main()
