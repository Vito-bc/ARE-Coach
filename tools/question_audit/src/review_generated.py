"""Create a versioned, non-overwriting review workbook for new candidates.

Usage (from tools/question_audit/):
    python -m src.review_generated
    python -m src.review_generated --output generated_review_20260914.xlsx
"""
from __future__ import annotations

import argparse
from pathlib import Path

from src import config
from src.generated_approval import ApprovalError, load_candidates, write_review_workbook


def _reports_path(value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else config.REPORTS_DIR / path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default="generated_accepted.json")
    parser.add_argument("--output", default="generated_review.xlsx")
    args = parser.parse_args(argv)

    source_path = _reports_path(args.input)
    output_path = _reports_path(args.output)
    try:
        candidates = load_candidates(source_path)
        write_review_workbook(candidates, output_path, source_path=source_path)
    except (ApprovalError, FileExistsError, OSError) as exc:
        print(f"REFUSED: {exc}")
        return 2

    print(
        f"Wrote {output_path}: {len(candidates)} candidates. Existing review files are never overwritten."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
