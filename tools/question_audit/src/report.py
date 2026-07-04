"""Shared reporting: severity ranking, summary dashboard, CSV+JSON output."""
from __future__ import annotations

import csv
import json
from collections import defaultdict
from datetime import datetime, timezone

from src import config


def severity(row: dict) -> float:
    """Higher = worse. Drives the ranked 'needs review' list."""
    s = 0.0
    if row["judgment"]["label"] == "factual":
        s += 2
    dists = row["distractors"]["distractors"]
    if dists:
        avg = sum(d["plausibility"] for d in dists) / len(dists)
        s += max(0.0, 5 - avg)  # weak distractors add up to +4
    if row["consistency"]["verdict"] == "fail":
        s += 3
    if row["leakage"]["leakage_prone"]:
        s += 2
    return round(s, 2)


def _flat(row: dict) -> dict:
    dists = row["distractors"]["distractors"]
    plaus = [d["plausibility"] for d in dists] or [0]
    return {
        "id": row["id"],
        "section": row["section"],
        "difficulty": row["difficulty"],
        "judgment": row["judgment"]["label"],
        "judgment_reason": row["judgment"]["reason"],
        "distractor_avg": round(sum(plaus) / len(plaus), 2),
        "distractor_min": min(plaus),
        "consistency": row["consistency"]["verdict"],
        "consistency_reason": row["consistency"]["reason"],
        "leakage_prone": row["leakage"]["leakage_prone"],
        "leakage_confidence": row["leakage"]["confidence"],
        "severity": row["severity"],
    }


def summarize(rows: list[dict]) -> str:
    by_sec: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        by_sec[r["section"]].append(r)

    lines = ["", "=" * 64, "AUDIT SUMMARY (by division)", "=" * 64]
    lines.append(f"{'Division':28} {'n':>4} {'judg%':>6} {'distr':>6} {'incons':>7} {'leak':>5}")
    for sec, rs in sorted(by_sec.items()):
        n = len(rs)
        judg = sum(1 for r in rs if r["judgment"]["label"] == "judgment") / n * 100
        davgs = []
        for r in rs:
            d = r["distractors"]["distractors"]
            if d:
                davgs.append(sum(x["plausibility"] for x in d) / len(d))
        distr = sum(davgs) / len(davgs) if davgs else 0
        incons = sum(1 for r in rs if r["consistency"]["verdict"] == "fail")
        leak = sum(1 for r in rs if r["leakage"]["leakage_prone"])
        lines.append(f"{sec:28} {n:>4} {judg:>5.0f}% {distr:>6.2f} {incons:>7} {leak:>5}")

    n = len(rows)
    judg = sum(1 for r in rows if r["judgment"]["label"] == "judgment") / n * 100
    incons = sum(1 for r in rows if r["consistency"]["verdict"] == "fail")
    leak = sum(1 for r in rows if r["leakage"]["leakage_prone"])
    weak = sum(
        1
        for r in rows
        if r["distractors"]["distractors"]
        and sum(d["plausibility"] for d in r["distractors"]["distractors"])
        / len(r["distractors"]["distractors"])
        < 2.5
    )
    lines += [
        "-" * 64,
        f"TOTAL {n} | judgment {judg:.0f}% / factual {100 - judg:.0f}% | "
        f"weak-distractor {weak} ({weak / n * 100:.0f}%) | "
        f"consistency-fails {incons} | leakage-prone {leak} ({leak / n * 100:.0f}%)",
    ]
    return "\n".join(lines)


def write_and_print(rows: list[dict], model: str, tag: str) -> None:
    """Compute severity, write CSV+JSON, print the summary and top-20."""
    for r in rows:
        r["severity"] = severity(r)
    ranked = sorted(rows, key=lambda r: r["severity"], reverse=True)

    config.REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    json_path = config.REPORTS_DIR / f"audit_{tag}.json"
    json_path.write_text(
        json.dumps(
            {
                "generated_at": datetime.now(timezone.utc).isoformat(),
                "model": model,
                "count": len(rows),
                "results": ranked,
            },
            indent=2,
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    csv_path = config.REPORTS_DIR / f"audit_{tag}.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        flat = [_flat(r) for r in ranked]
        writer = csv.DictWriter(f, fieldnames=list(flat[0].keys()))
        writer.writeheader()
        writer.writerows(flat)

    print(summarize(rows))
    print("\nTOP 20 NEEDS-REVIEW (worst first):")
    for r in ranked[:20]:
        j, c = r["judgment"]["label"], r["consistency"]["verdict"]
        print(f"  {r['severity']:>4}  {r['id']:10} [{j}/{c}] {r['section']}")
    print(f"\nReports: {csv_path.name}, {json_path.name}")
