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
from contextlib import nullcontext
from pathlib import Path

from src import config
from src.generated_approval import ApprovalError, load_candidates, read_review_workbook
from src.generated_import import (
    BankImportLock,
    ImportSafetyError,
    apply_import_plan,
    bank_import_lock,
    build_import_plan,
    load_bank,
    load_journal,
    pending_transaction_state,
    recover_pending_transaction,
    transaction_pointer_for,
    verify_bank_journal_consistency,
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

    args.bank = args.bank.resolve()
    args.journal = args.journal.resolve()
    try:
        # Take ownership BEFORE inspecting pending state; keep it until every
        # recovery, plan, write, cleanup and error-state inspection has finished.
        with bank_import_lock(args.bank) if args.apply else nullcontext(None) as lock:
            return _run(args, lock)
    except (ImportSafetyError, OSError) as exc:
        print(f"REFUSED: {exc}")
        return 2


def _report_current_state(bank_path: Path, journal_path: Path, pointer: Path) -> None:
    try:
        pending = pending_transaction_state(pointer)
        if pending:
            print(f"Pending transaction: {pending}.")
            print("Re-run --apply to attempt recovery only after both targets and prepared images validate.")
            return
        bank, journal = load_bank(bank_path), load_journal(journal_path)
        verify_bank_journal_consistency(bank, journal)
        print(f"Current bank/journal are consistent: {len(bank)} questions, {len(journal['imports'])} recorded imports; no pending transaction.")
    except (ImportSafetyError, OSError, ValueError) as exc:
        print(f"Current state cannot be verified: {exc}. Preserve transaction evidence for manual recovery.")


def _run(args: argparse.Namespace, lock: BankImportLock | None) -> int:
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
                lock=lock,
            )
            print("RECOVERY: bank and provenance journal now match the staged transaction.")

        candidates = load_candidates(source_path)
        review = read_review_workbook(candidates, review_path, source_path=source_path)
        bank = load_bank(bank_path)
        journal = load_journal(journal_path)
        plan = build_import_plan(bank, journal, review, review_path=review_path)

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
            print("No additional candidates to import.")
            return 0

        transaction_dir = apply_import_plan(
            plan,
            bank_path=bank_path,
            journal_path=journal_path,
            backups_dir=args.backups_dir.resolve(),
            transaction_pointer=transaction_pointer,
            lock=lock,
        )
    except (ApprovalError, ImportSafetyError, OSError, ValueError) as exc:
        print(f"REFUSED / INTERRUPTED: {exc}")
        if args.apply:
            _report_current_state(bank_path, journal_path, transaction_pointer)
        else:
            print("DRY-RUN: no data was changed; recovery was not attempted.")
        return 2

    print(
        f"Imported {len(plan.additions)} question(s). Bank and provenance journal verified. "
        f"Recovery evidence: {transaction_dir}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
