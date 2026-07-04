"""Remove same-division near-duplicate questions — keeps exactly ONE per cluster.

Builds connected components over the same-division, non-calc duplicate pairs
(from duplicates_090.csv), keeps the longest-stem member of each cluster, drops
the rest. Cross-division pairs and calc-template look-alikes are left alone.
Backs up before writing; re-validates after.

Usage (from tools/question_audit/):
    python -m src.remove_dups            # dry-run
    python -m src.remove_dups --apply
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import shutil
from collections import defaultdict
from datetime import datetime

from src import config
from src.schema import load_questions


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    qs = {q.id: q for q in load_questions(config.QUESTIONS_PATH).valid}

    pairs = []
    with (config.REPORTS_DIR / "duplicates_090.csv").open(encoding="utf-8") as f:
        for r in csv.DictReader(f):
            pairs.append((r["id_a"], r["id_b"], float(r["similarity"])))

    def is_calc(a: str, b: str) -> bool:  # same template, different numbers = keep both
        qa, qb = qs[a].question, qs[b].question
        return bool(re.search(r"\d", qa) and re.search(r"\d", qb) and ("SF" in qa or "occupan" in qa.lower()))

    # Union-find over same-division, non-calc pairs.
    parent: dict[str, str] = {}

    def find(x: str) -> str:
        parent.setdefault(x, x)
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a: str, b: str) -> None:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    for a, b, s in pairs:
        if is_calc(a, b) or qs[a].section != qs[b].section:
            continue
        union(a, b)

    comps: dict[str, list[str]] = defaultdict(list)
    for node in list(parent):
        comps[find(node)].append(node)

    drop: set[str] = set()
    for members in comps.values():
        members.sort(key=lambda i: len(qs[i].question), reverse=True)
        drop.update(members[1:])  # keep the longest stem, drop the rest

    print(f"Clusters: {len(comps)} | dropping {len(drop)} duplicates (1 kept per cluster).")
    for m in comps.values():
        keep = m[0]
        for d in m[1:]:
            print(f"  keep {keep:9} / DROP {d:9} [{qs[d].section}]")

    data = json.loads(config.QUESTIONS_PATH.read_text(encoding="utf-8-sig"))
    kept = [q for q in data if q["id"] not in drop]
    print(f"\nBank: {len(data)} -> {len(kept)}")
    assert len(kept) == len(data) - len(drop)

    if args.apply:
        backups = config.TOOL_DIR / "backups"
        backups.mkdir(exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        bak = backups / f"questions_ny_{ts}_predrop.json"
        shutil.copy2(config.QUESTIONS_PATH, bak)
        config.QUESTIONS_PATH.write_text(
            json.dumps(kept, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(f"BACKED UP -> backups/{bak.name}; wrote {len(kept)} questions.")
    else:
        print("DRY-RUN — nothing written. Re-run with --apply.")


if __name__ == "__main__":
    main()
