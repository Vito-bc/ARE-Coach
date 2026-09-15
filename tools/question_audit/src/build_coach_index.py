"""Build the AI Coach's retrieval index from the RAG corpus.

Emits functions/coach_index.json — the chunks the Cloud Function retrieves from
so the Coach can ground its answers in real code text and cite real sections.

The index is deliberately NOT committed (see functions/.gitignore): it contains
extracted text from the source documents, and our corpus rule is "grounding
only, not redistributed". Firebase uploads everything under functions/ on
deploy regardless of .gitignore, so the function still gets it.

Usage (from tools/question_audit/):
    python -m src.build_coach_index
    python -m src.build_coach_index --max-chunks 2500
"""
from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from src import config
from src.corpus import (
    Chunk,
    CorpusMetadataError,
    IngestionDiagnostic,
    load_chunks,
    print_ingestion_diagnostics,
)
from src.source_policy import (
    PURPOSE_COACH_INDEX,
    PolicyRequest,
    evaluate_source,
)

# The Coach answers exam questions, so a chunk is only useful if it carries
# substantive prose or a numbered requirement. Table-of-contents fragments and
# stray headers are noise that crowds out real sections in retrieval.
MIN_CHARS = 200
MAX_CHARS = 1600

_SECTION_RE = re.compile(r"\b(?:§+\s*)?\d{3,4}(?:\.\d+){1,3}\b")
_TOC_RE = re.compile(r"\.{4,}\s*\d+\s*$", re.MULTILINE)  # "Foo....... 12"


def _useful(text: str) -> bool:
    if not (MIN_CHARS <= len(text) <= MAX_CHARS):
        return False
    if len(_TOC_RE.findall(text)) >= 2:  # a table-of-contents block
        return False
    # Needs some actual sentences, not just a column of numbers.
    letters = sum(ch.isalpha() for ch in text)
    return letters / len(text) > 0.55


@dataclass(frozen=True)
class IndexPlan:
    rows: tuple[dict[str, Any], ...]
    report: dict[str, Any]


def build_index_plan(
    chunks: list[Chunk], requests: list[PolicyRequest], max_chunks: int = 0
) -> IndexPlan:
    """Build rows and an exclusion report without writing or loading models."""
    if not requests or any(request.purpose != PURPOSE_COACH_INDEX for request in requests):
        raise ValueError("Coach index requires at least one coach_index policy request")
    rows: list[dict[str, Any]] = []
    decisions: list[dict[str, Any]] = []
    content_filtered = 0
    for chunk in chunks:
        evaluated = [evaluate_source(chunk, request) for request in requests]
        eligible = [decision for decision in evaluated if decision.eligible]
        if not eligible:
            outcome = (
                "invalid_metadata"
                if any(decision.outcome == "invalid_metadata" for decision in evaluated)
                else "excluded"
            )
            decisions.append(
                {
                    "source_path": chunk.source_path,
                    "source_document": chunk.source_document,
                    "source_chunk_id": chunk.source_chunk_id,
                    "outcome": outcome,
                    "reasons": sorted(
                        {
                            reason
                            for decision in evaluated
                            for reason in decision.reasons
                        }
                    ),
                    "requests": [decision.to_dict()["request"] for decision in evaluated],
                }
            )
            continue
        text = " ".join(chunk.text.split())  # normalise whitespace; shrinks the file
        if not _useful(text):
            content_filtered += 1
            decisions.append(
                {
                    "source_path": chunk.source_path,
                    "source_document": chunk.source_document,
                    "source_chunk_id": chunk.source_chunk_id,
                    "outcome": "excluded",
                    "reasons": ["content_not_indexable"],
                    "requests": [decision.to_dict()["request"] for decision in eligible],
                }
            )
            continue
        rows.append(
            {
                "source": chunk.source,
                "ref": chunk.ref,
                "text": text,
                # Real section numbers found in the chunk. The Coach may only
                # cite a section that actually appears in a retrieved chunk --
                # this is what makes fabricated citations impossible.
                "sections": sorted(set(_SECTION_RE.findall(text)))[:8],
                **chunk.candidate_source_metadata(),
                "source_policy_decisions": [decision.to_dict() for decision in eligible],
            }
        )

    # Prefer chunks that actually carry section numbers -- those are what a
    # candidate needs cited back at them.
    rows.sort(key=lambda row: (-len(row["sections"]), -len(row["text"])))
    rows = rows[:max_chunks] if max_chunks else rows
    decisions.sort(
        key=lambda item: (
            item["source_path"] or "",
            item["source_chunk_id"] or "",
        )
    )
    excluded_sources: dict[str, dict[str, Any]] = {}
    for item in decisions:
        key = item["source_path"] or "<unknown>"
        aggregate = excluded_sources.setdefault(
            key,
            {
                "source_path": item["source_path"],
                "source_document": item["source_document"],
                "outcome": item["outcome"],
                "chunk_count": 0,
                "reasons": set(),
            },
        )
        aggregate["chunk_count"] += 1
        aggregate["reasons"].update(item["reasons"])
        if item["outcome"] == "invalid_metadata":
            aggregate["outcome"] = "invalid_metadata"
    source_rows = []
    for key in sorted(excluded_sources):
        item = excluded_sources[key]
        item["reasons"] = sorted(item["reasons"])
        source_rows.append(item)
    report = {
        "schema": "are-coach.coach-index-policy-report.v1",
        "requests": [request.to_dict() for request in requests],
        "counts": {
            "input_chunks": len(chunks),
            "eligible_index_rows": len(rows),
            "excluded_chunks": sum(item["outcome"] == "excluded" for item in decisions),
            "invalid_metadata_chunks": sum(
                item["outcome"] == "invalid_metadata" for item in decisions
            ),
            "content_filtered_chunks": content_filtered,
        },
        "excluded_sources": source_rows,
        "excluded_chunks": decisions,
    }
    return IndexPlan(tuple(rows), report)


def build_index_rows(
    chunks: list[Chunk], requests: list[PolicyRequest], max_chunks: int = 0
) -> list[dict[str, Any]]:
    """Compatibility wrapper for callers that only need policy-approved rows."""
    return list(build_index_plan(chunks, requests, max_chunks).rows)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-chunks", type=int, default=0, help="0 = no cap")
    ap.add_argument("--division", action="append", required=True)
    ap.add_argument("--jurisdiction", required=True)
    ap.add_argument("--policy-profile", required=True)
    ap.add_argument("--expected-edition")
    ap.add_argument("--expected-revision")
    ap.add_argument("--apply", action="store_true", help="write index and policy report")
    ap.add_argument("--output", type=Path, default=config.REPO_ROOT / "functions" / "coach_index.json")
    ap.add_argument(
        "--report",
        type=Path,
        default=config.REPORTS_DIR / "coach_index_policy_report.json",
    )
    args = ap.parse_args(argv)

    diagnostics: list[IngestionDiagnostic] = []
    try:
        chunks = load_chunks(diagnostics=diagnostics)
    except (CorpusMetadataError, OSError, ValueError) as exc:
        print(f"REFUSED: invalid source metadata or corpus input: {exc}")
        return 2
    print_ingestion_diagnostics(diagnostics)
    print(f"corpus chunks: {len(chunks)}")

    requests = [
        PolicyRequest(
            PURPOSE_COACH_INDEX,
            division,
            args.jurisdiction,
            args.policy_profile,
            args.expected_edition,
            args.expected_revision,
        )
        for division in args.division
    ]
    plan = build_index_plan(chunks, requests, args.max_chunks)
    rows = list(plan.rows)

    counts = plan.report["counts"]
    print(
        "policy: "
        f"{counts['eligible_index_rows']} eligible, {counts['excluded_chunks']} excluded, "
        f"{counts['invalid_metadata_chunks']} invalid metadata"
    )
    if not args.apply:
        print(json.dumps(plan.report, indent=2, ensure_ascii=False, sort_keys=True))
        print("DRY-RUN - Coach index and policy report were not changed.")
        return 0 if rows and not counts["invalid_metadata_chunks"] else 2
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(
        json.dumps(plan.report, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    if counts["invalid_metadata_chunks"]:
        print(f"REFUSED: invalid source metadata; report written to {args.report}")
        return 2
    if not rows:
        print(f"REFUSED: no eligible Coach index rows; report written to {args.report}")
        return 2

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")

    size_mb = args.output.stat().st_size / 1_000_000
    with_sections = sum(1 for r in rows if r["sections"])
    print(f"kept {len(rows)} chunks ({with_sections} carry section numbers)")
    print(f"wrote {args.output} -- {size_mb:.1f} MB")
    print(f"policy report: {args.report}")
    print("NOTE: git-ignored on purpose; `firebase deploy` still uploads it.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
