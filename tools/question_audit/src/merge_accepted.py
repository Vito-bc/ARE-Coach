"""Import generated candidates only after version-matched human approval.

Dry-run is the default.  Human review is mandatory in every mode; the legacy
``--reviewed`` switch is accepted only for command compatibility and never
changes the approval requirement.

Usage (from tools/question_audit/):
    python -m src.merge_accepted
    python -m src.merge_accepted --review-book generated_review_20260914.xlsx
    python -m src.merge_accepted --review-book generated_review_20260914.xlsx --apply
"""
from __future__ import annotations

import argparse
from pathlib import Path

from src import config
from src.generated_approval import ApprovalError, load_candidates, read_review_workbook
from src.generated_import import (
    ImportSafetyError,
    apply_import_plan,
    build_import_plan,
    load_bank,
    load_journal,
    pending_transaction_state,
    recover_pending_transaction,
    transaction_pointer_for,
)


def _reports_path(value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else config.REPORTS_DIR / path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--input", default="generated_accepted.json")
    parser.add_argument("--review-book", default="generated_review.xlsx")
    parser.add_argument("--bank", type=Path, default=config.QUESTIONS_PATH, help=argparse.SUPPRESS)
    parser.add_argument(
        "--journal", type=Path, default=config.GENERATED_IMPORT_JOURNAL, help=argparse.SUPPRESS
    )
    parser.add_argument("--backups-dir", type=Path, default=config.TOOL_DIR / "backups", help=argparse.SUPPRESS)
    parser.add_argument("--reviewed", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args(argv)

    source_path = _reports_path(args.input)
    review_path = _reports_path(args.review_book)
    bank_path = args.bank.resolve()
    journal_path = args.journal.resolve()
    transaction_pointer = transaction_pointer_for(journal_path)

    try:
        pending = pending_transaction_state(transaction_pointer)
        if pending:
            if not args.apply:
                raise ImportSafetyError(
                    f"pending bank/journal transaction detected ({pending}); dry-run will not mutate it. "
                    "Run the same command with --apply to complete verified recovery."
                )
            print(f"RECOVERY: {pending}")
            recover_pending_transaction(
                transaction_pointer,
                expected_bank_path=bank_path,
                expected_journal_path=journal_path,
            )
            print("RECOVERY: bank and provenance journal now match the staged transaction.")

        candidates = load_candidates(source_path)
        review = read_review_workbook(candidates, review_path, source_path=source_path)
        bank = load_bank(bank_path)
        journal = load_journal(journal_path)
        plan = build_import_plan(bank, journal, review, review_path=review_path)
    except (ApprovalError, ImportSafetyError, OSError) as exc:
        print(f"REFUSED: {exc}")
        print("No candidate was added.")
        return 2

    print(
        "Human review: "
        f"{len(plan.additions)} to add, {len(plan.already_imported)} already imported, "
        f"{len(plan.blocked)} blocked."
    )
    for item in plan.items:
        if item.status == "add":
            print(f"  ADD {item.candidate_id} -> {item.bank_id}: {item.reason}")
        elif item.status == "already_imported":
            print(f"  ALREADY {item.candidate_id} -> {item.bank_id}: {item.reason}")
        else:
            print(f"  BLOCK {item.candidate_id}: {item.reason}")

    if not args.apply:
        print("DRY-RUN - bank, provenance journal and review workbook were not changed.")
        return 0
    if not plan.additions:
        print("Nothing new to import; no files were changed.")
        return 0

    try:
        transaction_dir = apply_import_plan(
            plan,
            bank_path=bank_path,
            journal_path=journal_path,
            backups_dir=args.backups_dir.resolve(),
            transaction_pointer=transaction_pointer,
        )
    except (ImportSafetyError, OSError) as exc:
        pending = pending_transaction_state(transaction_pointer)
        print(f"IMPORT INTERRUPTED: {exc}")
        if pending:
            print(f"Detected recoverable state: {pending}")
            print("Re-run the same --apply command to complete verified recovery.")
        return 2

    print(
        f"Imported {len(plan.additions)} question(s). Bank and provenance journal verified. "
        f"Recovery evidence: {transaction_dir}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
